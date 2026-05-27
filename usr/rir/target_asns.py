#!/usr/bin/python3
"""
Generate BIRD ASN filter sets from RIR delegation statistics.

Pipeline:
  1. Download RIR delegation stats from all 5 registries (24h cache)
  2. Filter ASN records by country code per routing policy
  3. Merge with manual include/exclude lists from conf.d/
  4. Write BIRD "define" arrays to /etc/bird/bird.d/filters/
  5. Reload BIRD via birdc configure
"""

import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path
from urllib.request import urlopen
from shutil import copyfileobj

RIR_STATS_URLS = [
    "http://ftp.apnic.net/stats/afrinic/delegated-afrinic-extended-latest",
    "http://ftp.apnic.net/stats/apnic/delegated-apnic-extended-latest",
    "http://ftp.apnic.net/stats/arin/delegated-arin-extended-latest",
    "http://ftp.apnic.net/stats/lacnic/delegated-lacnic-extended-latest",
    "http://ftp.apnic.net/stats/ripe-ncc/delegated-ripencc-extended-latest",
]

CACHE_MAX_AGE = 86400
DOWNLOAD_TIMEOUT = 300

BIRD_FILTERS_DIR = Path("/etc/bird/bird.d/filters")

# Routing policy: which country codes are selected from each RIR
# overseas (CN2): all APNIC countries, US only from ARIN
OVERSEAS_APNIC_INCLUDE = re.compile(r".")
OVERSEAS_ARIN_INCLUDE = re.compile(r"^US$")
# CERNET: only JP/AU/NZ from APNIC (CN routes use a different upstream)
CERNET_APNIC_INCLUDE = re.compile(r"^(JP|AU|NZ)$")
# China Telecom: everything except CN from APNIC, US from ARIN
TEL_APNIC_EXCLUDE = re.compile(r"^CN$")
TEL_ARIN_INCLUDE = re.compile(r"^US$")

FILTERS = [
    {
        "name": "overseas_asns_inverted",
        "output": "overseas_asns_inverted.conf",
        "include_dir": "conf.d/overseas_exclude",
        "exclude_dir": "conf.d/overseas",
    },
    {
        "name": "cernet_asns",
        "output": "cernet_asns.conf",
        "include_dir": "conf.d/cernet",
        "exclude_dir": "conf.d/cernet_exclude",
    },
    {
        "name": "tel_asns",
        "output": "tel_asns.conf",
        "include_dir": "conf.d/tel",
        "exclude_dir": "conf.d/tel_exclude",
    },
    {
        "name": "tel_overseas_asns",
        "output": "tel_overseas_asns.conf",
        "include_dir": "conf.d/tel_overseas",
        "exclude_dir": "conf.d/tel_exclude",
    },
    {
        "name": "cmcc_asns",
        "output": "cmcc_asns.conf",
        "include_dir": "conf.d/cmcc",
        "exclude_dir": "conf.d/cmcc_exclude",
    },
]


def log(msg: str) -> None:
    print(msg, file=sys.stderr)


def read_conf_asns(path: Path) -> set[int]:
    """Read ASNs from a .conf file or directory of .conf files.

    Format: one ASN per line, '#' comments, blank lines ignored.
    """
    asns: set[int] = set()
    if not path.exists():
        return asns
    files = sorted(path.rglob("*.conf")) if path.is_dir() else [path]
    for f in files:
        for line in f.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            try:
                asns.add(int(line))
            except ValueError:
                pass
    return asns


def format_bird_define(name: str, asns: set[int]) -> str:
    lines = [f"# Automatically generated at {datetime.now()} CST"]
    lines.append(f"define {name} = [")
    sorted_asns = sorted(asns)
    for i, asn in enumerate(sorted_asns):
        sep = "," if i < len(sorted_asns) - 1 else ""
        lines.append(f"\t{asn}{sep}")
    lines.append("];")
    return "\n".join(lines) + "\n"


# RIR extended delegation format (pipe-delimited):
#   registry|CC|type|start|value|date|status|opaque-id

def parse_delegation_file(path: Path) -> list[tuple[str, int, int]]:
    """Parse a RIR delegation file into (country_code, start_asn, count) tuples."""
    records: list[tuple[str, int, int]] = []
    for line in path.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split("|")
        if len(parts) < 7 or parts[2] != "asn":
            continue
        if parts[6] not in ("assigned", "allocated"):
            continue
        try:
            records.append((parts[1], int(parts[3]), int(parts[4])))
        except (ValueError, IndexError):
            continue
    return records


def expand_asn_records(records: list[tuple[str, int, int]]) -> set[int]:
    asns: set[int] = set()
    for _, start, count in records:
        for i in range(count):
            asns.add(start + i)
    return asns


def filter_records_by_cc(
    records: list[tuple[str, int, int]],
    include: re.Pattern[str] | None = None,
    exclude: re.Pattern[str] | None = None,
) -> list[tuple[str, int, int]]:
    result = []
    for cc, start, count in records:
        if exclude and exclude.match(cc):
            continue
        if include and not include.match(cc):
            continue
        result.append((cc, start, count))
    return result


def download_file(url: str, dest: Path) -> None:
    log(f"  Downloading {url}")
    with urlopen(url, timeout=DOWNLOAD_TIMEOUT) as resp, open(dest, "wb") as out:
        copyfileobj(resp, out)


def ensure_rir_data(db_dir: Path) -> dict[str, Path]:
    """Download RIR delegation files if stale (>24h) or missing."""
    db_dir.mkdir(parents=True, exist_ok=True)
    apnic_file = db_dir / "delegated-apnic-extended-latest"

    need_download = True
    if apnic_file.exists():
        age = time.time() - apnic_file.stat().st_mtime
        if age < CACHE_MAX_AGE:
            log("Using cached stats information")
            need_download = False

    if need_download:
        log("Downloading RIR delegation stats...")
        for f in db_dir.glob("delegated-*"):
            f.unlink()
        for url in RIR_STATS_URLS:
            filename = url.rsplit("/", 1)[-1]
            download_file(url, db_dir / filename)
        log("Downloaded stats information")

    files = {}
    for f in db_dir.glob("delegated-*-extended-latest"):
        registry = f.name.split("-")[1]
        files[registry] = f
    return files


AsnRecords = list[tuple[str, int, int]]


def build_overseas_asns(apnic_records: AsnRecords, arin_records: AsnRecords) -> set[int]:
    filtered = filter_records_by_cc(apnic_records, include=OVERSEAS_APNIC_INCLUDE)
    filtered += filter_records_by_cc(arin_records, include=OVERSEAS_ARIN_INCLUDE)
    return expand_asn_records(filtered)


def build_cernet_asns(apnic_records: AsnRecords) -> set[int]:
    filtered = filter_records_by_cc(apnic_records, include=CERNET_APNIC_INCLUDE)
    return expand_asn_records(filtered)


def build_tel_asns(apnic_records: AsnRecords, arin_records: AsnRecords) -> set[int]:
    filtered = filter_records_by_cc(apnic_records, exclude=TEL_APNIC_EXCLUDE)
    filtered += filter_records_by_cc(arin_records, include=TEL_ARIN_INCLUDE)
    return expand_asn_records(filtered)


def generate_filter(
    name: str,
    rir_asns: set[int],
    include_dir: Path,
    exclude_dir: Path,
) -> str:
    members = set(rir_asns)
    members |= read_conf_asns(include_dir)
    members -= read_conf_asns(exclude_dir)
    return format_bird_define(name, members)


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    db_dir = script_dir / "db"

    rir_files = ensure_rir_data(db_dir)

    apnic = rir_files.get("apnic")
    arin = rir_files.get("arin")
    if not apnic or not arin:
        log("ERROR: Missing required delegation files (apnic, arin)")
        return 1

    log("Parsing delegation files...")
    apnic_records = parse_delegation_file(apnic)
    arin_records = parse_delegation_file(arin)
    log(f"  APNIC: {len(apnic_records)} ASN records")
    log(f"  ARIN:  {len(arin_records)} ASN records")

    rir_sets = {
        "overseas_asns_inverted": build_overseas_asns(apnic_records, arin_records),
        "cernet_asns": build_cernet_asns(apnic_records),
        "tel_asns": build_tel_asns(apnic_records, arin_records),
        "tel_overseas_asns": set(),
        "cmcc_asns": set(),
    }

    BIRD_FILTERS_DIR.mkdir(parents=True, exist_ok=True)
    if not BIRD_FILTERS_DIR.is_dir():
        log(f"ERROR: Cannot create output directory {BIRD_FILTERS_DIR}")
        return 1
    errors = []

    def _gen(filt: dict[str, str]) -> tuple[str, str]:
        name = filt["name"]
        content = generate_filter(
            name=name,
            rir_asns=rir_sets[name],
            include_dir=script_dir / filt["include_dir"],
            exclude_dir=script_dir / filt["exclude_dir"],
        )
        out_path = BIRD_FILTERS_DIR / filt["output"]
        out_path.write_text(content)
        return name, str(out_path)

    with ThreadPoolExecutor(max_workers=len(FILTERS)) as pool:
        futures = {pool.submit(_gen, f): f["name"] for f in FILTERS}
        for future in as_completed(futures):
            name = futures[future]
            try:
                _, path = future.result()
                log(f"Generated {name} -> {path}")
            except Exception as exc:
                log(f"ERROR generating {name}: {exc}")
                errors.append(name)

    if errors:
        log(f"Aborting birdc configure — {len(errors)} filter(s) failed: {errors}")
        return 1

    log("Reloading BIRD configuration...")
    result = subprocess.run(["birdc", "configure"], capture_output=True, text=True)
    if result.returncode != 0:
        log(f"birdc configure failed (rc={result.returncode}):")
        log(result.stderr or result.stdout)
        return result.returncode

    log("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
