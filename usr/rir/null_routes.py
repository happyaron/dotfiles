#!/usr/bin/python3
"""
Manage blackhole routes in kernel routing table 249.

Sources:
  - Static configuration (conf.d/null/null.conf)
  - fail2ban ipset (f2b-sshd)
  - FireHOL blocklists (firehol-mirror git repo, 6h cache)

Pipeline:
  1. Collect IPs from all sources
  2. Exclude whitelisted prefixes
  3. CIDR-merge to minimize route count
  4. Diff against current kernel table 249
  5. Apply only the delta (add/del)
"""

import os
import re
import subprocess
import sys
import tempfile
import time
from ipaddress import ip_network, collapse_addresses
from pathlib import Path

os.environ["PATH"] = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

WORKDIR = Path("/root/scripts/rir")
STATIC_CONF = WORKDIR / "conf.d/null/null.conf"
FIREHOL_CACHE_DIR = WORKDIR / "db/firehol"
FIREHOL_DB_DIR = WORKDIR / "db"
CACHE_MAX_AGE = 21600

DB_IPSETS = [
    "firehol_level1.netset",
    "firehol_level2.netset",
    "firehol_level3.netset",
    "firehol_webclient.netset",
    "firehol_abusers_1d.netset",
    "bitcoin_nodes_30d.ipset",
    "botscout_7d.ipset",
    "ciarmy.ipset",
    "dm_tor.ipset",
    "et_tor.ipset",
    "haley_ssh.ipset",
    "iblocklist_onion_router.netset",
    "myip.ipset",
    "tor_exits_30d.ipset",
    "socks_proxy_30d.ipset",
    "sslproxies_30d.ipset",
    "xroxy_30d.ipset",
]

GIT_REPO_DIR = "firehol-mirror"
GIT_REPO_URL = "https://github.com/borestad/firehol-mirror"

# Own infrastructure prefixes — must never be blackholed
FIREHOL_EXCLUDE_RE = re.compile(
    r"^(103\.94\.12|202\.204\.128|222\.28\.240|39\.155\.141|60\.247\.76)"
)

ROUTE_TABLE = 249


def log(msg: str) -> None:
    print(msg)


def banner(msg: str = "") -> None:
    print("=" * 52)
    if msg:
        print(msg)


def get_static() -> list[str]:
    if not STATIC_CONF.is_file():
        log(f"Warning: static config {STATIC_CONF} not found")
        return []
    ips = []
    for line in STATIC_CONF.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            ips.append(line)
    log(f"Collected from static configuration, {len(ips)} entries.")
    return ips


def get_f2b() -> list[str]:
    try:
        result = subprocess.run(
            ["ipset", "list", "f2b-sshd", "-output", "save"],
            capture_output=True, text=True, timeout=30,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        log("Warning: could not read f2b-sshd ipset")
        return []
    ips = []
    for line in result.stdout.splitlines():
        if line.startswith("add "):
            parts = line.split()
            if len(parts) >= 3:
                ips.append(parts[2])
    log(f"Collected from f2b, {len(ips)} entries.")
    return ips


def _truncate_history(repo_dir: Path, keep: int = 10) -> None:
    """Truncate the local repo to only the latest *keep* commits.

    Uses ``git fetch --depth`` to re-shallow, then prunes unreachable
    objects so the on-disk size actually shrinks.
    """
    subprocess.run(
        ["git", "fetch", "--depth", str(keep)],
        cwd=str(repo_dir),
    )
    subprocess.run(
        ["git", "reflog", "expire", "--expire=now", "--all"],
        cwd=str(repo_dir),
    )
    subprocess.run(
        ["git", "gc", "--prune=now"],
        cwd=str(repo_dir),
    )


def git_update(repo_dir: Path, repo_url: str) -> bool:
    env = os.environ.copy()
    env["GIT_HTTP_LOW_SPEED_LIMIT"] = "100"
    env["GIT_HTTP_LOW_SPEED_TIME"] = "600"

    if not repo_dir.is_dir():
        rc = subprocess.run(
            ["git", "clone", "--depth", "10", repo_url, str(repo_dir)],
            env=env, cwd=str(repo_dir.parent),
        ).returncode
        if rc != 0:
            log(f"Error: git clone failed (rc={rc})")
            return False
    else:
        rc = subprocess.run(
            ["git", "pull"], env=env, cwd=str(repo_dir),
        ).returncode
        if rc != 0:
            log(f"Error: git pull failed (rc={rc})")
            return False
        _truncate_history(repo_dir, keep=10)
    return True


def get_db() -> list[str]:
    need_download = True
    sentinel = FIREHOL_CACHE_DIR / "firehol_level1.netset"

    if sentinel.is_file():
        age = time.time() - sentinel.stat().st_mtime
        if age < CACHE_MAX_AGE:
            log("Using cached firehol iplists.")
            need_download = False

    if need_download:
        log("Starting to update firehol iplists...")
        if FIREHOL_CACHE_DIR.exists():
            for f in FIREHOL_CACHE_DIR.iterdir():
                f.unlink()
        FIREHOL_CACHE_DIR.mkdir(parents=True, exist_ok=True)

        repo_dir = FIREHOL_DB_DIR / GIT_REPO_DIR
        if not git_update(repo_dir, GIT_REPO_URL):
            log("Error: failed to update firehol mirror, using stale data if available")
            if not sentinel.is_file():
                return []

        for ipset in DB_IPSETS:
            src = repo_dir / ipset
            if src.is_file():
                (FIREHOL_CACHE_DIR / ipset).write_bytes(src.read_bytes())
            else:
                log(f"Warning: {ipset} not found in mirror repo")
        log("Downloaded firehol blacklists")

    ips = []
    for path in sorted(FIREHOL_CACHE_DIR.iterdir()):
        if not path.is_file():
            continue
        for line in path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if FIREHOL_EXCLUDE_RE.match(line):
                continue
            ips.append(line)
    return ips


def cidr_merge(raw_ips: list[str]) -> list[str]:
    networks = []
    for entry in raw_ips:
        entry = entry.strip()
        if not entry:
            continue
        try:
            net = ip_network(entry, strict=False)
            networks.append(net)
        except ValueError:
            continue

    # collapse_addresses requires homogeneous IP versions
    v4 = sorted(n for n in networks if n.version == 4)
    v6 = sorted(n for n in networks if n.version == 6)
    merged = list(collapse_addresses(v4)) + list(collapse_addresses(v6))

    host_routes = sum(1 for n in merged if n.prefixlen == n.max_prefixlen)
    log(f"Total route count: {len(networks)}")
    log(f"Merged route count: {len(merged)}")
    log(f"Single host routes: {host_routes}")

    # Strip /32 — kernel shows host routes as bare IPs, diff needs to match
    result = []
    for net in merged:
        s = str(net)
        if s.endswith("/32"):
            s = s[:-3]
        result.append(s)
    return result


def get_kernel_blackholes() -> set[str]:
    routes = set()
    
    result4 = subprocess.run(
        ["ip", "-4", "route", "show", "table", str(ROUTE_TABLE)],
        capture_output=True, text=True,
    )
    for line in result4.stdout.splitlines():
        if line.startswith("blackhole "):
            parts = line.split()
            if len(parts) >= 2:
                routes.add(parts[1])

    result6 = subprocess.run(
        ["ip", "-6", "route", "show", "table", str(ROUTE_TABLE)],
        capture_output=True, text=True,
    )
    for line in result6.stdout.splitlines():
        if line.startswith("blackhole "):
            parts = line.split()
            if len(parts) >= 2:
                routes.add(parts[1])

    return routes


def diff_routes(desired: list[str]) -> tuple[list[str], list[str]]:
    desired_set = set(desired)
    current = get_kernel_blackholes()

    commands4 = []
    commands6 = []
    
    for route in sorted(current - desired_set):
        try:
            v = ip_network(route, strict=False).version
        except ValueError:
            continue
        if v == 4:
            commands4.append(f"route del {route} table {ROUTE_TABLE}")
        else:
            commands6.append(f"route del {route} table {ROUTE_TABLE}")
            
    for route in sorted(desired_set - current):
        try:
            v = ip_network(route, strict=False).version
        except ValueError:
            continue
        if v == 4:
            commands4.append(f"route add blackhole {route} table {ROUTE_TABLE}")
        else:
            commands6.append(f"route add blackhole {route} table {ROUTE_TABLE}")
            
    return commands4, commands6


def main() -> int:
    os.chdir(WORKDIR)

    banner("Starting to update dynamic blackhole configurations")

    all_ips: list[str] = []
    all_ips.extend(get_static())
    all_ips.extend(get_f2b())
    all_ips.extend(get_db())

    if not all_ips:
        log("Warning: no IPs collected from any source")

    merged = cidr_merge(all_ips)
    commands4, commands6 = diff_routes(merged)
    total_commands = len(commands4) + len(commands6)

    banner()

    if total_commands == 0:
        log("No changes found, not updating anything.")
    else:
        if commands4:
            with tempfile.NamedTemporaryFile(
                mode="w", prefix="null_routes_v4_", suffix=".batch", delete=False,
            ) as f:
                f.write("\n".join(commands4) + "\n")
                batch_path4 = f.name
            try:
                result = subprocess.run(
                    ["ip", "-4", "-force", "-batch", batch_path4],
                    capture_output=True, text=True,
                )
                if result.returncode != 0:
                    log(f"Error applying v4 batch: {result.stderr.strip()}")
                else:
                    log(f"Applied {len(commands4)} IPv4 changes to kernel rt_table {ROUTE_TABLE}.")
            finally:
                os.unlink(batch_path4)
                
        if commands6:
            with tempfile.NamedTemporaryFile(
                mode="w", prefix="null_routes_v6_", suffix=".batch", delete=False,
            ) as f:
                f.write("\n".join(commands6) + "\n")
                batch_path6 = f.name
            try:
                result = subprocess.run(
                    ["ip", "-6", "-force", "-batch", batch_path6],
                    capture_output=True, text=True,
                )
                if result.returncode != 0:
                    log(f"Error applying v6 batch: {result.stderr.strip()}")
                else:
                    log(f"Applied {len(commands6)} IPv6 changes to kernel rt_table {ROUTE_TABLE}.")
            finally:
                os.unlink(batch_path6)

    kernel_count = len(get_kernel_blackholes())

    # Give BIRD time to import the kernel table changes before querying
    if total_commands > 0:
        time.sleep(2)

    try:
        bird_result = subprocess.run(
            ["birdc", "show", "route", "count", "table", "table_nullroute"],
            capture_output=True, text=True,
        )
        bird_count = bird_result.stdout.strip().splitlines()[-1].split()[0] if bird_result.returncode == 0 else "?"
    except (FileNotFoundError, IndexError):
        bird_count = "?"

    banner()
    log(f"Summary - kernel rt_table: {kernel_count}, redistributed: {bird_count}")
    banner()

    return 0


if __name__ == "__main__":
    sys.exit(main())
