#!/usr/bin/env python3
"""
Fetch and write IP prefix lists used by set-routes.sh.

Outputs (into --output-dir):
  chn.txt     — CN IPv4 prefixes from APNIC delegated stats (aggregated)
  chn-v6.txt  — CN IPv6 prefixes from APNIC delegated stats (aggregated)
  google.txt  — Google Services IPv4 netblocks (All Google minus Cloud)
  gcp.txt     — Google Cloud Platform IPv4 netblocks
  google-v6.txt — Google Services IPv6 netblocks (All Google minus Cloud)
  gcp-v6.txt    — Google Cloud Platform IPv6 netblocks
  aws.txt     — AWS US-region IPv4 prefixes via ip-ranges.json
  aws-v6.txt  — AWS US-region IPv6 prefixes via ip-ranges.json
  oci.txt     — Oracle Cloud Infrastructure IPv4 prefixes
  oci-v6.txt  — Oracle Cloud Infrastructure IPv6 prefixes

Use --skip-cn, --skip-google, --skip-gcp, --skip-aws, --skip-oci to disable individual fetches.
"""
# cnroutes portion forked from https://github.com/fivesheep/chnroutes

import argparse
import ipaddress
import json
import os
import re
import stat
import sys
import tempfile
import time
import urllib.request
from typing import Any

HTTP_TIMEOUT = 30  # seconds
HTTP_RETRIES = 2
HTTP_BACKOFF = 5  # seconds between retries
STALE_THRESHOLD = 7 * 86400

OUTPUT_FILES = {
    "cn_ipv4": "chn.txt",
    "cn_ipv6": "chn-v6.txt",
    "google_ipv4": "google.txt",
    "google_ipv6": "google-v6.txt",
    "gcp_ipv4": "gcp.txt",
    "gcp_ipv6": "gcp-v6.txt",
    "aws_ipv4": "aws.txt",
    "aws_ipv6": "aws-v6.txt",
    "oci_ipv4": "oci.txt",
    "oci_ipv6": "oci-v6.txt",
}


def _is_ipv6(cidr: str) -> bool:
    """Heuristic: IPv6 CIDRs contain ':', IPv4 never do. Only used for OCI dispatch."""
    return ":" in cidr


def _fetch_and_parse_json(url: str, label: str) -> dict[str, Any] | None:
    raw = _fetch_url(url, label)
    if raw is None:
        return None
    try:
        return json.loads(raw.decode())
    except Exception as e:
        print(f"WARNING: Failed to parse {label}: {e}", file=sys.stderr)
        return None


def _fetch_url(url, label="URL"):
    """Fetch URL content with retry. Returns bytes or None on failure."""
    max_attempts = HTTP_RETRIES + 1
    for attempt in range(1, max_attempts + 1):
        try:
            with urllib.request.urlopen(url, timeout=HTTP_TIMEOUT) as resp:
                return resp.read()
        except Exception as e:
            if attempt < max_attempts:
                print(
                    f"  {label}: attempt {attempt} failed ({e}), retrying in {HTTP_BACKOFF}s...",
                    file=sys.stderr,
                )
                time.sleep(HTTP_BACKOFF)
            else:
                print(f"WARNING: Failed to fetch {label}: {e}", file=sys.stderr)
                return None


# ---------------------------------------------------------------------------
# CN routes (from APNIC delegated stats)
# ---------------------------------------------------------------------------

APNIC_URL = "https://ftp.apnic.net/stats/apnic/delegated-apnic-latest"

# Stricter regex patterns with anchors and explicit status values
APNIC_IPV4_PATTERN = re.compile(
    r"^apnic\|CN\|ipv4\|([0-9.]+)\|([0-9]+)\|\d+\|(?:allocated|assigned)$"
)
APNIC_IPV6_PATTERN = re.compile(
    r"^apnic\|CN\|ipv6\|([0-9a-f:]+)\|([0-9]+)\|\d+\|(?:allocated|assigned)$"
)


def fetch_cn_prefixes():
    raw = _fetch_url(APNIC_URL, "APNIC")
    if raw is None:
        return [], []
    data = raw.decode()

    if not data:
        print("WARNING: Empty response from APNIC", file=sys.stderr)
        return [], []

    ipv4_nets = []
    ipv6_nets = []

    # Single-pass parsing of APNIC data
    for line in data.splitlines():
        line = line.strip()
        if not line:
            continue

        # Try IPv4 pattern first
        match = APNIC_IPV4_PATTERN.match(line)
        if match:
            try:
                ip = match.group(1)
                num_ip = int(match.group(2))

                # Validate power-of-2 assumption
                if num_ip <= 0 or (num_ip & (num_ip - 1)) != 0:
                    print(
                        f"WARNING: non-power-of-2 count {num_ip} for {ip}, skipping",
                        file=sys.stderr,
                    )
                    continue

                cidr = 32 - (num_ip - 1).bit_length()
                ipv4_nets.append(ipaddress.IPv4Network(f"{ip}/{cidr}"))
            except (ValueError, IndexError) as e:
                print(f"WARNING: Skipping malformed IPv4 line: {line!r}: {e}", file=sys.stderr)
                continue
            continue

        # Try IPv6 pattern
        match = APNIC_IPV6_PATTERN.match(line)
        if match:
            try:
                ip = match.group(1)
                length = int(match.group(2))
                ipv6_nets.append(ipaddress.IPv6Network(f"{ip}/{length}"))
            except (ValueError, IndexError) as e:
                print(f"WARNING: Skipping malformed IPv6 line: {line!r}: {e}", file=sys.stderr)
                continue

    # Aggregate adjacent/overlapping prefixes to reduce route table size
    ipv4_agg = list(ipaddress.collapse_addresses(ipv4_nets))
    ipv6_agg = list(ipaddress.collapse_addresses(ipv6_nets))

    print(f"  CN: {len(ipv4_nets)} IPv4 raw -> {len(ipv4_agg)} aggregated, {len(ipv6_nets)} IPv6 raw -> {len(ipv6_agg)} aggregated")
    return [str(n) for n in ipv4_agg], [str(n) for n in ipv6_agg]


# ---------------------------------------------------------------------------
# Google netblocks (Services vs Cloud)
# ---------------------------------------------------------------------------

GOOGLE_URL = "https://www.gstatic.com/ipranges/goog.json"
CLOUD_URL = "https://www.gstatic.com/ipranges/cloud.json"

def _nets_to_intervals(nets):
    return [(int(n.network_address), int(n.network_address) + n.num_addresses)
            for n in ipaddress.collapse_addresses(nets)]


def _carve_interval(intervals, exc_lo, exc_hi):
    result = []
    for lo, hi in intervals:
        if exc_hi <= lo or exc_lo >= hi:
            result.append((lo, hi))
        else:
            if lo < exc_lo:
                result.append((lo, exc_lo))
            if exc_hi < hi:
                result.append((exc_hi, hi))
    return result


def _intervals_to_nets(intervals, addr_cls):
    result = []
    for lo, hi in intervals:
        result.extend(ipaddress.summarize_address_range(addr_cls(lo), addr_cls(hi - 1)))
    return list(ipaddress.collapse_addresses(result))


def _subtract_networks(base_nets, exclude_nets):
    """Return base_nets with all exclude_nets carved out, collapsed and sorted.

    Uses integer-range arithmetic so partial overlaps are handled correctly.
    """
    if not base_nets:
        return []

    # Determine address class before consuming the list
    sample = next(iter(base_nets))
    addr_cls = ipaddress.IPv4Address if isinstance(sample, ipaddress.IPv4Network) else ipaddress.IPv6Address

    intervals = _nets_to_intervals(base_nets)

    for net in ipaddress.collapse_addresses(exclude_nets):
        exc_lo = int(net.network_address)
        exc_hi = exc_lo + net.num_addresses
        intervals = _carve_interval(intervals, exc_lo, exc_hi)

    if not intervals:
        return []

    return _intervals_to_nets(intervals, addr_cls)

def _parse_networks(prefixes: list[str], version: int = 4, as_strings: bool = False):
    """Parse and validate IP network prefixes, collapse, return networks or strings."""
    nets = []
    for p in prefixes:
        try:
            if version == 4:
                nets.append(ipaddress.IPv4Network(p))
            else:
                nets.append(ipaddress.IPv6Network(p))
        except ValueError as e:
            print(f"WARNING: Invalid IPv{version} prefix {p!r}: {e}", file=sys.stderr)
    collapsed = list(ipaddress.collapse_addresses(nets))
    return [str(n) for n in collapsed] if as_strings else collapsed


def fetch_google_and_cloud_prefixes():
    """
    Fetches Google IP ranges and separates them into:
    1. Google Services (excluding Cloud) - IPv4 and IPv6
    2. Google Cloud Platform (GCP) - IPv4 and IPv6
    """
    try:
        goog_raw = _fetch_url(GOOGLE_URL, "Google IPs")
        cloud_raw = _fetch_url(CLOUD_URL, "Cloud IPs")
        if goog_raw is None or cloud_raw is None:
            return [], [], [], []
        goog_data = json.loads(goog_raw.decode())
        cloud_data = json.loads(cloud_raw.decode())
    except Exception as e:
        print(f"WARNING: Failed to fetch Google/Cloud IPs: {e}", file=sys.stderr)
        return [], [], [], []

    if not goog_data.get("prefixes"):
        print("WARNING: Empty response from Google IP ranges", file=sys.stderr)
    if not cloud_data.get("prefixes"):
        print("WARNING: Empty response from Cloud IP ranges", file=sys.stderr)

    goog_ipv4 = [p["ipv4Prefix"] for p in goog_data.get("prefixes", []) if "ipv4Prefix" in p]
    cloud_ipv4 = [p["ipv4Prefix"] for p in cloud_data.get("prefixes", []) if "ipv4Prefix" in p]
    goog_ipv6 = [p["ipv6Prefix"] for p in goog_data.get("prefixes", []) if "ipv6Prefix" in p]
    cloud_ipv6 = [p["ipv6Prefix"] for p in cloud_data.get("prefixes", []) if "ipv6Prefix" in p]

    goog_ipv4_nets = _parse_networks(goog_ipv4, version=4)
    cloud_ipv4_nets = _parse_networks(cloud_ipv4, version=4)
    goog_ipv6_nets = _parse_networks(goog_ipv6, version=6)
    cloud_ipv6_nets = _parse_networks(cloud_ipv6, version=6)

    services_ipv4_nets = _subtract_networks(goog_ipv4_nets, cloud_ipv4_nets)
    services_ipv6_nets = _subtract_networks(goog_ipv6_nets, cloud_ipv6_nets)

    services_ipv4 = [str(n) for n in services_ipv4_nets]
    cloud_ipv4_str = [str(n) for n in cloud_ipv4_nets]
    services_ipv6 = [str(n) for n in services_ipv6_nets]
    cloud_ipv6_str = [str(n) for n in cloud_ipv6_nets]

    print(f"  Google: {len(goog_ipv4_nets)} IPv4 total, {len(services_ipv4)} services, {len(cloud_ipv4_str)} cloud; {len(goog_ipv6_nets)} IPv6 total, {len(services_ipv6)} services, {len(cloud_ipv6_str)} cloud")
    return services_ipv4, cloud_ipv4_str, services_ipv6, cloud_ipv6_str


# ---------------------------------------------------------------------------
# AWS US-region prefixes
# ---------------------------------------------------------------------------

AWS_URL = "https://ip-ranges.amazonaws.com/ip-ranges.json"


def _is_aws_us_region(p):
    r = p.get("region", "")
    return r.startswith("us-") or r in ("us", "us-gov")


def fetch_aws_prefixes():
    data = _fetch_and_parse_json(AWS_URL, "AWS IPs")
    if data is None:
        return [], []

    if not data.get("prefixes") and not data.get("ipv6_prefixes"):
        print("WARNING: Empty response from AWS IP ranges", file=sys.stderr)
        return [], []

    ipv4_prefixes = _parse_networks(
        [p["ip_prefix"] for p in data.get("prefixes", []) if "ip_prefix" in p and _is_aws_us_region(p)],
        version=4, as_strings=True,
    )

    ipv6_prefixes = _parse_networks(
        [p["ipv6_prefix"] for p in data.get("ipv6_prefixes", []) if "ipv6_prefix" in p and _is_aws_us_region(p)],
        version=6, as_strings=True,
    )

    print(f"  AWS: {len(ipv4_prefixes)} IPv4 US-region prefixes, {len(ipv6_prefixes)} IPv6")
    return ipv4_prefixes, ipv6_prefixes


# ---------------------------------------------------------------------------
# Oracle Cloud Infrastructure prefixes
# ---------------------------------------------------------------------------

OCI_URL = "https://docs.oracle.com/iaas/tools/public_ip_ranges.json"


def fetch_oci_prefixes():
    data = _fetch_and_parse_json(OCI_URL, "OCI IPs")
    if data is None:
        return [], []

    if not data.get("regions"):
        print("WARNING: Empty response from OCI IP ranges", file=sys.stderr)
        return [], []

    ipv4_list = []
    ipv6_list = []

    for region in data.get("regions", []):
        for cidr_obj in region.get("cidrs", []):
            cidr = cidr_obj.get("cidr")
            if not cidr:
                continue
            if _is_ipv6(cidr):
                ipv6_list.append(cidr)
            else:
                ipv4_list.append(cidr)

    ipv4_prefixes = _parse_networks(ipv4_list, version=4, as_strings=True)
    ipv6_prefixes = _parse_networks(ipv6_list, version=6, as_strings=True)

    print(f"  OCI: {len(ipv4_prefixes)} IPv4 prefixes, {len(ipv6_prefixes)} IPv6")
    return ipv4_prefixes, ipv6_prefixes


# ---------------------------------------------------------------------------
# Route Generation Logic
# ---------------------------------------------------------------------------

# Sanity thresholds: warn if a file has fewer prefixes than expected.
# Auto-generated files should have well-known minimum counts.
# Static files only need to be non-empty (threshold 1).
_PREFIX_THRESHOLDS: dict[str, int] = {
    OUTPUT_FILES["cn_ipv4"]: 1000,   # APNIC CN has thousands of allocations
    OUTPUT_FILES["google_ipv4"]: 10, # Google publishes ~60-100 service prefixes
    OUTPUT_FILES["gcp_ipv4"]: 10,
    OUTPUT_FILES["aws_ipv4"]: 10,
    OUTPUT_FILES["oci_ipv4"]: 10,
}

# Files that MUST exist for a valid route batch (auto-generated).
_REQUIRED_FILES: set[str] = {OUTPUT_FILES["cn_ipv4"]}

# Files that SHOULD exist but are optional (manually maintained).
_EXPECTED_FILES: set[str] = {"gateway.txt", "internal.txt", "subscriber.txt", "us.txt"}

# Cloud prefix files — subtracted from CN routes to ensure cloud traffic
# goes through VPN default rather than direct ISP.
_CLOUD_FILES: list[str] = [
    OUTPUT_FILES["google_ipv4"],
    OUTPUT_FILES["gcp_ipv4"],
    OUTPUT_FILES["aws_ipv4"],
    OUTPUT_FILES["oci_ipv4"],
]


def _write_route_cmd(f, cmd, ip_str, gw=None, dev=None, src=None):
    line = f"{cmd} {ip_str}"
    if gw:
        line += f" via {gw}"
    if dev:
        line += f" dev {dev}"
    if src:
        line += f" src {src}"
    if gw:
        line += " onlink"
    f.write(f"{line}\n")


def _load_prefixes_from_file(filepath: str) -> set[str]:
    """Load canonical IPv4 CIDR strings from a prefix list file."""
    prefixes: set[str] = set()
    if not os.path.exists(filepath):
        return prefixes
    try:
        with open(filepath) as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                try:
                    net = ipaddress.ip_network(line, strict=False)
                    if net.version == 4:
                        prefixes.add(str(net))
                except ValueError:
                    pass
    except OSError:
        pass
    return prefixes


def generate_routes(args):
    """Generate ip route batch file based on local .txt files.

    Route priority (highest first, first writer wins for exact CIDR dups):
      1. gateway.txt    — static manual overrides        → DEFAULTGW + src
      2. internal.txt   — internal network               → SECONDGW
      3. subscriber.txt — subscriber-facing               → DEFAULTGW
      4. us.txt         — explicit US tunnel              → ROUTEGW_1
      5. chn.txt        — CN traffic direct (auto-gen)    → DEFAULTGW + src

    Everything else (Google, AWS, OCI, etc.) has no explicit route and falls
    through to the WG default at the lowest metric → VPN.

    Cloud prefixes (google/gcp/aws/oci) are subtracted from CN routes to
    prevent cloud traffic from going direct instead of through VPN.
    """
    output_path = args.gen_routes
    txt_dir = args.output_dir

    print(f"Generating routes to {output_path}...")

    # --- Load cloud prefixes for CN subtraction ---
    cloud_prefixes: set[str] = set()
    for cloud_file in _CLOUD_FILES:
        cloud_prefixes |= _load_prefixes_from_file(os.path.join(txt_dir, cloud_file))

    # --- Define route file groups in priority order ---
    # Each entry: (filenames, gw, dev, src, gateway_required_args)
    route_groups: list[tuple[list[str], str | None, str | None, str | None]] = []

    # Priority 1: gateway.txt → DEFAULTGW + src
    if args.default_gw and args.default_dev:
        route_groups.append((["gateway.txt"], args.default_gw, args.default_dev, args.default_src))

    # Priority 2: internal.txt → SECONDGW
    if args.second_gw and args.second_dev:
        route_groups.append((["internal.txt"], args.second_gw, args.second_dev, None))

    # Priority 3: subscriber.txt → DEFAULTGW
    if args.default_gw and args.default_dev:
        route_groups.append((["subscriber.txt"], args.default_gw, args.default_dev, None))

    # Priority 4: us.txt → ROUTEGW_1
    if args.route_gw1 and args.route_dev1:
        route_groups.append((["us.txt"], args.route_gw1, args.route_dev1, None))

    # Priority 5: chn.txt → DEFAULTGW + src (cloud-subtracted)
    if args.default_gw and args.default_dev:
        route_groups.append(([OUTPUT_FILES["cn_ipv4"]], args.default_gw, args.default_dev, args.default_src))

    # --- Check required files ---
    for req_file in _REQUIRED_FILES:
        req_path = os.path.join(txt_dir, req_file)
        if not os.path.exists(req_path):
            print(f"ERROR: Required file missing: {req_file}", file=sys.stderr)
            return False

    # --- Generate batch file ---
    seen_prefixes: set[str] = set()
    total_routes = 0
    errors = False

    try:
        with open(output_path, "w") as f:
            # 1. WireGuard gateway host route (direct, no "via" — the
            #    gateway is a peer on a point-to-point interface)
            if args.route_gw0 and args.route_dev0:
                f.write(f"ro replace {args.route_gw0}/32 dev {args.route_dev0}\n")

            # 2. Default routes — 'onlink' is required because ip -batch
            #    validates nexthops within a single netlink session; without
            #    it, rapid sequential replacements can fail reachability checks.
            if args.route_gw0 and args.route_dev0:
                f.write(f"ro replace default via {args.route_gw0} dev {args.route_dev0} metric {args.metric_wg} onlink\n")

            if args.default_gw and args.default_dev:
                cmd = f"ro replace default via {args.default_gw} dev {args.default_dev}"
                if args.default_src:
                    cmd += f" src {args.default_src}"
                cmd += f" metric {args.metric_default} onlink\n"
                f.write(cmd)

            if args.second_gw and args.second_dev:
                cmd = f"ro replace default via {args.second_gw} dev {args.second_dev}"
                if args.second_src:
                    cmd += f" src {args.second_src}"
                cmd += f" metric {args.metric_second} onlink\n"
                f.write(cmd)

            # 3. File-based routes in priority order (deduped)
            for filenames, gw, dev, src in route_groups:
                for filename in filenames:
                    filepath = os.path.join(txt_dir, filename)

                    if not os.path.exists(filepath):
                        if filename in _REQUIRED_FILES:
                            # Already checked above, but guard anyway
                            print(f"ERROR: Required file missing: {filename}", file=sys.stderr)
                            errors = True
                        elif filename in _EXPECTED_FILES:
                            print(f"WARNING: Expected file not found, skipping: {filename}", file=sys.stderr)
                        continue

                    file_count = 0
                    file_skipped_dup = 0
                    file_skipped_v6 = 0
                    file_skipped_cloud = 0

                    try:
                        with open(filepath) as inf:
                            for line in inf:
                                line = line.strip()
                                if not line or line.startswith("#"):
                                    continue
                                try:
                                    net = ipaddress.ip_network(line, strict=False)
                                except ValueError:
                                    print(f"WARNING: Invalid IP in {filename}: {line}", file=sys.stderr)
                                    continue

                                # Reject IPv6 — ip route batch requires -6 flag for v6
                                if net.version != 4:
                                    file_skipped_v6 += 1
                                    continue

                                canon = str(net)

                                # Exact-match dedup: higher-priority file wins
                                if canon in seen_prefixes:
                                    file_skipped_dup += 1
                                    continue

                                # Cloud subtraction for CN routes
                                if filename == OUTPUT_FILES["cn_ipv4"] and canon in cloud_prefixes:
                                    file_skipped_cloud += 1
                                    print(f"WARNING: CN prefix {canon} overlaps cloud, routing via VPN instead", file=sys.stderr)
                                    continue

                                seen_prefixes.add(canon)
                                _write_route_cmd(f, "ro add", canon, gw, dev, src)
                                file_count += 1

                    except OSError as e:
                        print(f"ERROR: Failed to read {filename}: {e}", file=sys.stderr)
                        errors = True
                        continue

                    # Summary line
                    extras = []
                    if file_skipped_dup:
                        extras.append(f"{file_skipped_dup} dedup")
                    if file_skipped_v6:
                        extras.append(f"{file_skipped_v6} IPv6 skipped")
                    if file_skipped_cloud:
                        extras.append(f"{file_skipped_cloud} cloud overlap")
                    suffix = f" ({', '.join(extras)})" if extras else ""
                    gw_label = f"{gw} dev {dev}" if gw else dev or "default"
                    print(f"  {filename}: {file_count} prefixes → {gw_label}{suffix}")

                    total_routes += file_count

                    # Sanity threshold check
                    threshold = _PREFIX_THRESHOLDS.get(filename, 1)
                    if file_count < threshold:
                        print(
                            f"WARNING: {filename} has {file_count} prefixes "
                            f"(expected >= {threshold}), possible incomplete data",
                            file=sys.stderr,
                        )

    except OSError as e:
        print(f"ERROR: Failed to generate route file: {e}", file=sys.stderr)
        return False

    if errors:
        print(f"ERROR: Route generation completed with errors", file=sys.stderr)
        try:
            os.unlink(output_path)
        except OSError:
            pass
        return False

    # Unmatched traffic (Google, AWS, OCI, etc.) falls through to WG default
    # at metric {args.metric_wg} → VPN.  No explicit routes needed.
    print(f"  Total: {total_routes} route commands generated")
    return True


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def _check_dir_writable(dir_path: str) -> bool:
    if not os.path.isdir(dir_path):
        return False
    return os.access(dir_path, os.W_OK | os.X_OK)


def _atomic_write_file(path: str, lines: list[str]) -> None:
    dir_name = os.path.dirname(path) or "."

    old_mode = None
    try:
        old_mode = os.stat(path).st_mode
    except FileNotFoundError:
        pass

    fd, tmp = tempfile.mkstemp(dir=dir_name, prefix=".tmp-", suffix=".txt")
    try:
        with os.fdopen(fd, "w") as f:
            for line in lines:
                f.write(f"{line}\n")
        if old_mode is not None:
            os.chmod(tmp, stat.S_IMODE(old_mode))
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def write_list(path: str, lines: list[str]) -> bool:
    if not lines:
        if os.path.exists(path):
            age_days = (time.time() - os.path.getmtime(path)) / 86400
            stale = age_days > (STALE_THRESHOLD / 86400)
            age_info = f"WARNING: {age_days:.0f} days old" if stale else f"{age_days:.0f}d old"
            print(f"  SKIP: fetch returned 0 prefixes, keeping existing {os.path.basename(path)} ({age_info})", file=sys.stderr)
        else:
            print(f"  SKIP: fetch returned 0 prefixes, not creating {os.path.basename(path)}", file=sys.stderr)
        return False

    _atomic_write_file(path, lines)
    return True

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-o", "--output-dir", default="/root/routes")
    # Fetch options
    parser.add_argument("--skip-cn", action="store_true", help="Skip fetching CN/APNIC prefixes")
    parser.add_argument("--skip-google", action="store_true", help="Skip fetching Google Services / Cloud prefixes")
    parser.add_argument("--skip-gcp", action="store_true", help="Skip writing GCP prefix list (still fetched with Google)")
    parser.add_argument("--skip-aws", action="store_true", help="Skip fetching AWS US-region prefixes")
    parser.add_argument("--skip-oci", action="store_true", help="Skip fetching Oracle Cloud Infrastructure prefixes")
    parser.add_argument("--skip-ipv4", action="store_true", help="Skip writing IPv4 prefix lists")
    parser.add_argument("--skip-ipv6", action="store_true", help="Skip writing IPv6 prefix lists")

    # Route Generation options
    parser.add_argument("--gen-routes", metavar="FILE", help="Generate ip route batch file to this path")
    parser.add_argument("--route-gw0", help="Gateway 0 (VPN/WG)")
    parser.add_argument("--route-dev0", help="Device 0 (VPN/WG)")
    parser.add_argument("--route-gw1", help="Gateway 1 (US)")
    parser.add_argument("--route-dev1", help="Device 1 (US)")
    parser.add_argument("--default-gw", help="Default Gateway")
    parser.add_argument("--default-dev", help="Default Device")
    parser.add_argument("--default-src", help="Default Source IP")
    parser.add_argument("--second-gw", help="Second Gateway (Internal)")
    parser.add_argument("--second-dev", help="Second Device (Internal)")
    parser.add_argument("--second-src", help="Second Source IP")
    parser.add_argument("--route-peer0", help="Route 0 tunnel peer gateway")
    
    parser.add_argument("--metric-wg", default="100", help="Metric for WG routes")
    parser.add_argument("--metric-default", default="1000", help="Metric for Default routes")
    parser.add_argument("--metric-second", default="2000", help="Metric for Second routes")

    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)
    if not _check_dir_writable(args.output_dir):
        print(f"ERROR: Output directory is not writable: {args.output_dir}", file=sys.stderr)
        sys.exit(1)

    # If --gen-routes is specified, we ONLY generate routes unless a fetch is explicitly requested?
    # Actually, the original script structure suggests fetching happens IF flags allow, then generation.
    # However, to be safe, if the user provides config args, they likely want to generate routes.
    
    # 1. Fetch Phase (only if we are NOT strictly generating routes or if we want to refresh)
    # To keep compatibility: if we run without arguments, we fetch.
    # If we run with --gen-routes, we might want to skip fetching if not asked.
    # But usually, set-routes.sh manages the logic of "when to fetch".
    # So we will ALWAYS try to fetch UNLESS all skip flags are set OR if we want to be explicit.
    # Let's assume:
    # - If run with default args -> Fetch everything
    # - If run with --gen-routes -> We can still fetch if not skipped.
    
    # Let's execute fetch logic as before.
    failures = 0

    # Only fetch if we haven't been told to skip everything or if we aren't JUST generating
    # For now, preserve existing behavior: try to fetch unless skipped.
    
    should_fetch = not (args.skip_cn and args.skip_google and args.skip_aws and args.skip_oci)
    
    if should_fetch:
        if not args.skip_cn:
            try:
                print("Fetching CN prefixes from APNIC...")
                cn_ipv4, cn_ipv6 = fetch_cn_prefixes()
                if not cn_ipv4 and not cn_ipv6:
                    failures += 1
                if not args.skip_ipv4:
                    write_list(os.path.join(args.output_dir, OUTPUT_FILES["cn_ipv4"]), cn_ipv4)
                if not args.skip_ipv6:
                    write_list(os.path.join(args.output_dir, OUTPUT_FILES["cn_ipv6"]), cn_ipv6)
            except Exception as e:
                print(f"ERROR: CN prefix processing failed: {e}", file=sys.stderr)
                failures += 1
        else:
            print("Skipping CN/APNIC prefixes (--skip-cn)")

        if not args.skip_google:
            try:
                print("Fetching Google netblocks (Services and Cloud)...")
                services_ipv4, cloud_ipv4, services_ipv6, cloud_ipv6 = fetch_google_and_cloud_prefixes()
                if not services_ipv4 and not cloud_ipv4 and not services_ipv6 and not cloud_ipv6:
                    failures += 1

                if not args.skip_ipv4:
                    print(f"Writing Google Services (non-Cloud) to {OUTPUT_FILES['google_ipv4']}...")
                    write_list(os.path.join(args.output_dir, OUTPUT_FILES["google_ipv4"]), services_ipv4)

                if not args.skip_ipv6:
                    print(f"Writing Google Services IPv6 to {OUTPUT_FILES['google_ipv6']}...")
                    write_list(os.path.join(args.output_dir, OUTPUT_FILES["google_ipv6"]), services_ipv6)

                if not args.skip_gcp:
                    if not args.skip_ipv4:
                        print(f"Writing Google Cloud to {OUTPUT_FILES['gcp_ipv4']}...")
                        write_list(os.path.join(args.output_dir, OUTPUT_FILES["gcp_ipv4"]), cloud_ipv4)
                    if not args.skip_ipv6:
                        print(f"Writing Google Cloud IPv6 to {OUTPUT_FILES['gcp_ipv6']}...")
                        write_list(os.path.join(args.output_dir, OUTPUT_FILES["gcp_ipv6"]), cloud_ipv6)
            except Exception as e:
                print(f"ERROR: Google/Cloud prefix processing failed: {e}", file=sys.stderr)
                failures += 1
        else:
            print("Skipping Google/Cloud prefixes (--skip-google)")

        if not args.skip_aws:
            try:
                print("Fetching AWS US-region prefixes...")
                aws_ipv4, aws_ipv6 = fetch_aws_prefixes()
                if not aws_ipv4 and not aws_ipv6:
                    failures += 1
                if not args.skip_ipv4:
                    write_list(os.path.join(args.output_dir, OUTPUT_FILES["aws_ipv4"]), aws_ipv4)
                if not args.skip_ipv6:
                    write_list(os.path.join(args.output_dir, OUTPUT_FILES["aws_ipv6"]), aws_ipv6)
            except Exception as e:
                print(f"ERROR: AWS prefix processing failed: {e}", file=sys.stderr)
                failures += 1
        else:
            print("Skipping AWS prefixes (--skip-aws)")

        if not args.skip_oci:
            try:
                print("Fetching OCI prefixes...")
                oci_ipv4, oci_ipv6 = fetch_oci_prefixes()
                if not oci_ipv4 and not oci_ipv6:
                    failures += 1
                if not args.skip_ipv4:
                    write_list(os.path.join(args.output_dir, OUTPUT_FILES["oci_ipv4"]), oci_ipv4)
                if not args.skip_ipv6:
                    write_list(os.path.join(args.output_dir, OUTPUT_FILES["oci_ipv6"]), oci_ipv6)
            except Exception as e:
                print(f"ERROR: OCI prefix processing failed: {e}", file=sys.stderr)
                failures += 1
        else:
            print("Skipping OCI prefixes (--skip-oci)")

        print("IP lists regenerated.")

        if failures:
            print(f"WARNING: {failures} fetch operation(s) failed", file=sys.stderr)
            # If fetching failed, we generally shouldn't proceed to generate broken routes, 
            # BUT existing files might still be there. 
            # The original script exits on failure.
            sys.exit(1)

    # 2. Generation Phase
    if args.gen_routes:
        if not generate_routes(args):
            sys.exit(1)
        print(f"Routes generated successfully in {args.gen_routes}")



if __name__ == "__main__":
    main()
