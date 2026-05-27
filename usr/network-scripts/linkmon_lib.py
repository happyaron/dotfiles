#!/usr/bin/env python3
"""
linkmon_lib.py — Shared utility for link-mon.sh and set-routes.sh.

Subcommands:
  state read  <file>            Read state file, emit JSON to stdout.
  state write <file> [--KEY=VAL ...]  Atomically write state file from args.
  probe  --incumbent-gw GW --incumbent-dev DEV
         --challenger-gw GW --challenger-dev DEV
         [--hysteresis MS] [--cooldown SEC] [--last-switch EPOCH]
         [--count N] [--deadline SEC]
         Probe two gateways, apply hysteresis/cooldown, emit JSON result.
  validate ip    <addr>         Exit 0 if valid IPv4, 1 otherwise.
  validate iface <name>         Exit 0 if valid interface name, 1 otherwise.
  validate cidr  <prefix>       Exit 0 if valid IPv4 CIDR, 1 otherwise.

Requires: Python >= 3.11, jq >= 1.6 (for shell-side JSON parsing).
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import re
import subprocess
import sys
import tempfile
import time


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

_IFACE_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9._-]*$")


def validate_ip(addr: str) -> bool:
    """Validate a bare IPv4 address (no prefix length)."""
    try:
        ipaddress.IPv4Address(addr)
        return True
    except (ValueError, ipaddress.AddressValueError):
        return False


def validate_iface(name: str) -> bool:
    """Validate a Linux network interface name."""
    return bool(_IFACE_RE.match(name))


def validate_cidr(prefix: str) -> bool:
    """Validate an IPv4 CIDR notation — requires explicit prefix length."""
    if "/" not in prefix:
        return False
    try:
        ipaddress.IPv4Network(prefix, strict=False)
        return True
    except (ValueError, ipaddress.AddressValueError):
        return False


# ---------------------------------------------------------------------------
# State file
# ---------------------------------------------------------------------------

# Canonical field list — order matters for output stability.
_STATE_FIELDS = (
    "routing_mode",
    "active_gw",
    "active_dev",
    "active_rtt",
    "backup_gw",
    "backup_dev",
    "backup_rtt",
    "stamp_time",
    "check",
)

# Allowed values for routing_mode.
_VALID_ROUTING_MODES = frozenset({"NORMAL", "LOCAL", "FAILED", ""})


def _validate_state(data: dict) -> dict:
    """Validate and normalise state dict.  Returns cleaned copy."""
    out: dict[str, str] = {}

    rm = data.get("routing_mode", "")
    if rm not in _VALID_ROUTING_MODES:
        print(f"WARNING: ignoring invalid routing_mode: {rm}", file=sys.stderr)
        rm = ""
    out["routing_mode"] = rm

    for key in ("active_gw", "backup_gw"):
        val = data.get(key, "")
        if val and not validate_ip(val):
            print(f"WARNING: ignoring invalid {key}: {val}", file=sys.stderr)
            val = ""
        out[key] = val

    for key in ("active_dev", "backup_dev"):
        val = data.get(key, "")
        if val and not validate_iface(val):
            print(f"WARNING: ignoring invalid {key}: {val}", file=sys.stderr)
            val = ""
        out[key] = val

    for key in ("active_rtt", "backup_rtt"):
        val = data.get(key, "")
        if val:
            try:
                float(val)
            except ValueError:
                print(f"WARNING: ignoring invalid {key}: {val}", file=sys.stderr)
                val = ""
        out[key] = val

    st = data.get("stamp_time", "0")
    try:
        int(st)
    except (ValueError, TypeError):
        st = "0"
    out["stamp_time"] = str(st)

    out["check"] = data.get("check", "")

    return out


def state_read(path: str) -> dict:
    """Read state file (JSON or legacy KEY=VALUE), return validated dict."""
    if not os.path.isfile(path):
        return {k: "" for k in _STATE_FIELDS}

    with open(path) as fh:
        raw = fh.read()

    stripped = raw.lstrip()
    if stripped.startswith("{"):
        try:
            data = json.loads(stripped)
            data.pop("_timestamp", None)
            return _validate_state(data)
        except json.JSONDecodeError:
            print("WARNING: corrupt JSON state, trying legacy parse", file=sys.stderr)

    # Legacy KEY=VALUE format (migration path from old shell-written state).
    _LEGACY_KEY_MAP = {
        "ROUTING_MODE": "routing_mode",
        "LINKGW_ACTIVE": "active_gw",
        "LINKDEV_ACTIVE": "active_dev",
        "LINKRTT_ACTIVE": "active_rtt",
        "LINKGW_BACKUP": "backup_gw",
        "LINKDEV_BACKUP": "backup_dev",
        "LINKRTT_BACKUP": "backup_rtt",
        "STAMP_TIME": "stamp_time",
    }

    data: dict[str, str] = {}
    for line in raw.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            if line.startswith("# CHECK:"):
                data["check"] = line.split(":", 1)[1].strip()
            continue
        if "=" not in line:
            continue
        raw_key, _, raw_val = line.partition("=")
        json_key = _LEGACY_KEY_MAP.get(raw_key.strip())
        if json_key:
            data[json_key] = raw_val.strip()

    return _validate_state(data)


def state_write(path: str, data: dict) -> None:
    """Atomically write state as JSON."""
    clean = _validate_state(data)
    now = int(time.time())
    output = {"_timestamp": now, **clean}

    dir_name = os.path.dirname(path) or "."
    os.makedirs(dir_name, exist_ok=True)

    fd, tmp = tempfile.mkstemp(dir=dir_name, prefix=".linkmon-state-")
    try:
        with os.fdopen(fd, "w") as fh:
            json.dump(output, fh, indent=2)
            fh.write("\n")
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


# ---------------------------------------------------------------------------
# Probe
# ---------------------------------------------------------------------------

def _ping_gateway(target: str, count: int, deadline: int) -> tuple[bool, str]:
    """Ping a gateway.  Returns (alive, avg_rtt_ms_str).

    avg_rtt_ms_str is "" if no reply received.
    """
    try:
        result = subprocess.run(
            ["ping", "-q", "-c", str(count), "-w", str(deadline), target],
            capture_output=True,
            text=True,
            timeout=deadline + 5,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return False, ""

    output = result.stdout

    # Extract packets received — matches "X packets transmitted, Y received"
    # Works across iputils-ping and busybox.
    recv_match = re.search(r"(\d+)\s+(?:packets?\s+)?received", output)
    received = int(recv_match.group(1)) if recv_match else 0

    # Extract average RTT — matches "rtt min/avg/max/mdev = .../AVG/..."
    # or busybox "round-trip min/avg/max = .../AVG/..."
    rtt_match = re.search(
        r"(?:rtt|round-trip)\s+\S+\s*=\s*[\d.]+/([\d.]+)/", output
    )
    avg_rtt = rtt_match.group(1) if rtt_match else ""

    return received > 0, avg_rtt


def probe(args: argparse.Namespace) -> dict:
    """Probe incumbent and challenger, apply hysteresis + cooldown.

    Returns dict with:
      alive: 0 = incumbent stays, 1 = switch to challenger, 2 = both down
      active_gw, active_dev, active_rtt
      backup_gw, backup_dev, backup_rtt
    """
    inc_alive, inc_rtt = _ping_gateway(
        args.incumbent_gw, args.count, args.deadline
    )
    cha_alive, cha_rtt = _ping_gateway(
        args.challenger_gw, args.count, args.deadline
    )

    result: dict[str, object] = {}

    if inc_alive:
        result["alive"] = 0
        result["active_gw"] = args.incumbent_gw
        result["active_dev"] = args.incumbent_dev
        result["active_rtt"] = inc_rtt
        result["backup_gw"] = args.challenger_gw
        result["backup_dev"] = args.challenger_dev
        result["backup_rtt"] = cha_rtt
    elif cha_alive:
        result["alive"] = 1
        result["active_gw"] = args.challenger_gw
        result["active_dev"] = args.challenger_dev
        result["active_rtt"] = cha_rtt
        result["backup_gw"] = args.incumbent_gw
        result["backup_dev"] = args.incumbent_dev
        result["backup_rtt"] = inc_rtt
    else:
        # Both down — caller keeps last-known-good from state.
        result["alive"] = 2
        result["active_gw"] = ""
        result["active_dev"] = ""
        result["active_rtt"] = ""
        result["backup_gw"] = ""
        result["backup_dev"] = ""
        result["backup_rtt"] = ""
        return result

    # Hysteresis: switch to challenger only if significantly faster AND
    # cooldown has elapsed.
    if inc_alive and cha_alive and inc_rtt and cha_rtt:
        try:
            rtt_inc = float(inc_rtt)
            rtt_cha = float(cha_rtt)
        except ValueError:
            return result

        if rtt_cha + args.hysteresis < rtt_inc:
            now = int(time.time())
            if (now - args.last_switch) >= args.cooldown:
                result["alive"] = 1
                result["active_gw"] = args.challenger_gw
                result["active_dev"] = args.challenger_dev
                result["active_rtt"] = cha_rtt
                result["backup_gw"] = args.incumbent_gw
                result["backup_dev"] = args.incumbent_dev
                result["backup_rtt"] = inc_rtt

    return result


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def cmd_state(args: argparse.Namespace) -> int:
    if args.state_action == "read":
        data = state_read(args.file)
        json.dump(data, sys.stdout)
        sys.stdout.write("\n")
        return 0

    if args.state_action == "write":
        data: dict[str, str] = {}
        if args.routing_mode is not None:
            data["routing_mode"] = args.routing_mode
        if args.active_gw is not None:
            data["active_gw"] = args.active_gw
        if args.active_dev is not None:
            data["active_dev"] = args.active_dev
        if args.active_rtt is not None:
            data["active_rtt"] = args.active_rtt
        if args.backup_gw is not None:
            data["backup_gw"] = args.backup_gw
        if args.backup_dev is not None:
            data["backup_dev"] = args.backup_dev
        if args.backup_rtt is not None:
            data["backup_rtt"] = args.backup_rtt
        if args.stamp_time is not None:
            data["stamp_time"] = args.stamp_time
        if args.check is not None:
            data["check"] = args.check
        state_write(args.file, data)
        return 0

    return 1


def cmd_probe(args: argparse.Namespace) -> int:
    result = probe(args)
    json.dump(result, sys.stdout)
    sys.stdout.write("\n")
    return 0


def cmd_validate(args: argparse.Namespace) -> int:
    vtype = args.validate_type
    value = args.value

    if vtype == "ip":
        return 0 if validate_ip(value) else 1
    if vtype == "iface":
        return 0 if validate_iface(value) else 1
    if vtype == "cidr":
        return 0 if validate_cidr(value) else 1

    print(f"Unknown validation type: {vtype}", file=sys.stderr)
    return 2


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Shared utility for link-mon.sh and set-routes.sh"
    )
    sub = parser.add_subparsers(dest="command")

    # -- state ---------------------------------------------------------------
    sp_state = sub.add_parser("state", help="Read/write link monitor state")
    state_sub = sp_state.add_subparsers(dest="state_action")

    sp_read = state_sub.add_parser("read", help="Read state file as JSON")
    sp_read.add_argument("file", help="Path to state file")

    sp_write = state_sub.add_parser("write", help="Write state file")
    sp_write.add_argument("file", help="Path to state file")
    sp_write.add_argument("--routing-mode", dest="routing_mode")
    sp_write.add_argument("--active-gw", dest="active_gw")
    sp_write.add_argument("--active-dev", dest="active_dev")
    sp_write.add_argument("--active-rtt", dest="active_rtt")
    sp_write.add_argument("--backup-gw", dest="backup_gw")
    sp_write.add_argument("--backup-dev", dest="backup_dev")
    sp_write.add_argument("--backup-rtt", dest="backup_rtt")
    sp_write.add_argument("--stamp-time", dest="stamp_time")
    sp_write.add_argument("--check", dest="check")

    # -- probe ---------------------------------------------------------------
    sp_probe = sub.add_parser("probe", help="Probe two gateways")
    sp_probe.add_argument("--incumbent-gw", required=True, dest="incumbent_gw")
    sp_probe.add_argument("--incumbent-dev", required=True, dest="incumbent_dev")
    sp_probe.add_argument("--challenger-gw", required=True, dest="challenger_gw")
    sp_probe.add_argument("--challenger-dev", required=True, dest="challenger_dev")
    sp_probe.add_argument(
        "--hysteresis", type=float, default=40, help="ms faster threshold"
    )
    sp_probe.add_argument(
        "--cooldown", type=int, default=600, help="seconds between switches"
    )
    sp_probe.add_argument(
        "--last-switch",
        type=int,
        default=0,
        dest="last_switch",
        help="epoch of last switch",
    )
    sp_probe.add_argument(
        "--count", type=int, default=3, help="ping packets per probe"
    )
    sp_probe.add_argument(
        "--deadline", type=int, default=5, help="ping deadline seconds"
    )

    # -- validate ------------------------------------------------------------
    sp_val = sub.add_parser("validate", help="Validate IP/iface/CIDR")
    sp_val.add_argument(
        "validate_type", choices=["ip", "iface", "cidr"], help="What to validate"
    )
    sp_val.add_argument("value", help="Value to validate")

    args = parser.parse_args()

    if args.command == "state":
        return cmd_state(args)
    if args.command == "probe":
        return cmd_probe(args)
    if args.command == "validate":
        return cmd_validate(args)

    parser.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
