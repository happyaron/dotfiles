# Network Scripts

Policy-based routing, WAN failover, DNS forwarding, and tunnel management
for a multi-homed Linux gateway.

## Quick start

```sh
# 1. Create site-specific config
cp network.conf.template network.conf
vi network.conf          # fill in real IPs, interfaces, subnets

# 2. Render systemd units and ipsec-tools.conf from config
../deploy-templates.sh --apply

# 3. Deploy (as root)
cp *.sh /root/scripts/
cp linkmon_lib.py /root/scripts/
cp ../deploy-templates.sh /root/scripts/
# systemd units go to /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now link-mon.timer split-access.service tunnel-boot.service
```

## Configuration

All site-specific values (IPs, interfaces, subnets) live in a single file:

| File | Tracked | Purpose |
|------|---------|---------|
| `network.conf.template` | yes | Documented template with `<PLACEHOLDER>` values |
| `network.conf` | no (gitignored) | Real values, sourced by every script at startup |

Shell scripts source `network.conf` directly. Files that can't source shell
(systemd units, `ipsec-tools.conf`) use `<VARNAME>` placeholders that
`deploy-templates.sh` substitutes from the same config.

## Scripts

### Routing

| Script | Runs as | What it does |
|--------|---------|--------------|
| `set-routes.sh` | root | Generates CN/Google/cloud IP lists via `generate-ip-list.py`, applies routing table via `ip -batch`. Primary entry point. |
| `set-pbr.sh` | root | Policy-based routing: BGP peer isolation (bgpif table), US-bound traffic steering (T101/T102 tables), fwmark rules. Called by `set-routes.sh` after routes are applied. |
| `split-access.sh` | root | Symmetric routing for multi-homed hosts — ensures packets leave via the interface they arrived on. Handles primary IPs, secondary /32 IPs, VLANs, IPv6. |
| `set-default-vpn.sh` | root | Legacy routing script (older host). Restores default routes and optionally regenerates IP lists. |

### Monitoring

| Script | Runs as | What it does |
|--------|---------|--------------|
| `link-mon.sh` | root (timer) | Probes two WAN gateways every 5 min, picks the best based on availability and RTT, calls `set-routes.sh` to failover. Persists state in `/var/lib/link-mon/`. |
| `linkmon_lib.py` | (library) | Shared helper for `link-mon.sh` and `set-routes.sh` — state persistence, ping probes, input validation. |

### DNS

| Script | Runs as | What it does |
|--------|---------|--------------|
| `dns-domains.sh` | root (timer) | Fetches gfwlist + google-china-list, generates BIND9 zone forwarding or dnsmasq server rules. Run with `--format=bind9` or `--format=dnsmasq`. |
| `domains.localadd` | (data) | Extra domains to forward via global DNS (one per line). |
| `domains.localadd_us` | (data) | Extra domains to forward via the private US DNS forwarder. |

### Tunnels

| Script | Runs as | What it does |
|--------|---------|--------------|
| `tunnel-boot.sh` | root (service) | Creates an ipip6 tunnel over IPv6, assigns addresses. Supports `apply` / `teardown`. |

### IP list generation

| Script | Runs as | What it does |
|--------|---------|--------------|
| `generate-ip-list.py` | root | Fetches IP prefix lists (CN from APNIC, Google, AWS, OCI) and writes route batch files. Called by `set-routes.sh`. |

### Utilities (scripts/)

| Script | Purpose |
|--------|---------|
| `scripts/gemini-domains.py` | Extracts domains for Gemini API endpoints. |
| `scripts/parse_he_asn_country.py` | Parses Hurricane Electric ASN data by country. |
| `scripts/parse_he_asn_search.py` | Searches Hurricane Electric ASN database. |

## Systemd units

All timers and services are in `systemd/system/`. Units that reference
site-specific service names (WireGuard, tinc) use `<VARNAME>` placeholders
— run `deploy-templates.sh --apply` after filling in `network.conf`.

| Unit | Type | Schedule | Description |
|------|------|----------|-------------|
| `link-mon.timer` | timer | every 5 min | Triggers `link-mon.sh` |
| `link-mon.service` | oneshot | — | WAN failover probe + route switch |
| `split-access.service` | oneshot (RemainAfterExit) | boot | Symmetric routing rules |
| `tunnel-boot.service` | oneshot (RemainAfterExit) | boot | IPv6 tunnel setup |
| `dns-domains.timer` | timer | every 12 h | Triggers `dns-domains.sh` |
| `dns-domains.service` | oneshot | — | DNS forwarding list update |
| `null-routes.timer` | timer | every 5 min | Triggers null route updates |
| `null-routes.service` | oneshot | — | Blackhole routes from blocklists |

### Boot order

```
network-online.target
  └─ tunnel-boot.service
       └─ split-access.service
            └─ link-mon.timer  (starts link-mon.service every 5 min)
                 └─ dns-domains.timer  (after first link-mon run)
```

## Prerequisites

- iproute2, ipset, iptables
- python3 (for `generate-ip-list.py`, `linkmon_lib.py`)
- jq >= 1.6 (for `link-mon.sh` state parsing)
- wget (for `dns-domains.sh` list fetches)
- BIND9 or dnsmasq (depending on `--format`)
- Routing tables in `/etc/iproute2/rt_tables`: `bgpif`, `T1`–`T7`, `T101`, `T102`

## deploy-templates.sh

Located at `usr/deploy-templates.sh`. Reads `network.conf` and substitutes
`<VARNAME>` placeholders in files that can't source shell directly:

```sh
deploy-templates.sh              # dry-run: show diffs
deploy-templates.sh --apply      # write substituted files in place
deploy-templates.sh --install /  # write to system paths under a prefix
```

Currently processes:
- `systemd/system/link-mon.service`
- `systemd/system/split-access.service`
- `systemd/system/tunnel-boot.service`
- `usr/ipsec-tools.conf`

To add more template files, edit the `TEMPLATE_FILES` list in the script.
