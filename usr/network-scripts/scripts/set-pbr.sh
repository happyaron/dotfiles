#!/bin/sh
# set-pbr.sh — Policy-based routing for BGP neighbor isolation and US traffic steering.
#
# Called by set-routes.sh after main table routes are applied.
# Prerequisites: tables "bgpif" and "T101" must exist in /etc/iproute2/rt_tables.
#
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ERRORS=0

log() { printf '[set-pbr] %s\n' "$*"; }

run() {
	if ! "$@"; then
		log "FAILED: $*"
		ERRORS=$((ERRORS + 1))
	fi
}

# ---------------------------------------------------------------------------
# Blackhole table for BGP neighbor interfaces
#
# Only allow traffic destined to the BGP peer subnets to leave via these
# sub-interfaces; everything else hits the blackhole.
# ---------------------------------------------------------------------------

ip route flush table bgpif 2>/dev/null || true
ip rule  flush table bgpif 2>/dev/null || true

run ip route add 192.0.2.48/30  dev eth0.2 table bgpif
run ip route add 192.0.2.52/30  dev eth0.3 table bgpif
run ip route add 192.0.2.56/30  dev eth0.4 table bgpif
run ip route add 192.0.2.60/30 dev eth0.5 table bgpif
run ip route add 192.0.2.64/30 dev eth0.6 table bgpif
run ip route add blackhole default table bgpif

run ip rule add iif eth0.2 lookup bgpif
run ip rule add iif eth0.3 lookup bgpif
run ip rule add iif eth0.4 lookup bgpif
run ip rule add iif eth0.5 lookup bgpif
run ip rule add iif eth0.6 lookup bgpif

# ---------------------------------------------------------------------------
# PBR for google.vpn1.edu.cn
#
# Prefer to route traffic to US (via vpn1 tunnel), avoiding congesting the
# default uplink.  Metric 500 fallback goes via the secondary gateway.
# ---------------------------------------------------------------------------

ip route flush table T101 2>/dev/null || true
ip rule  flush table T101 2>/dev/null || true

run ip route add default via 192.0.2.3  dev vpn1 metric 100 table T101
run ip route add default via 192.0.2.6  dev vpn1 metric 200 table T101
run ip route add default via 192.0.2.37       metric 500 table T101

run ip rule add from 192.0.2.35 lookup T101
run ip rule add from 192.0.2.36 lookup T101
run ip rule add from 192.0.2.34 lookup T101

## PBR for office access to US (currently disabled)
#run ip rule add from 100.64.2.0/24  lookup T101
#run ip rule add from 100.64.64.0/24 lookup T101

## Exception: force this PC through the main table
run ip rule add from 100.64.2.11 lookup main

# ---------------------------------------------------------------------------
# fwmark-based PBR
#
# fwmark 101 (0x65) — selected traffic steered to US via T101.
# (fwmark 100 is reserved for HTTP proxy mangling.)
# ---------------------------------------------------------------------------

run ip rule add fwmark 101 lookup T101

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------

if [ "$ERRORS" -gt 0 ]; then
	log "completed with $ERRORS error(s)"
	exit 1
fi
log "done"
