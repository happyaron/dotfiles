#!/bin/sh
# set-pbr.sh — Policy-based routing for BGP neighbor isolation and US traffic steering.
#
# Called by set-routes.sh after main table routes are applied.
# Prerequisites: tables "bgpif", "T101", "T102" must exist in /etc/iproute2/rt_tables.
#
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

CONF_FILE="$(dirname "$0")/network.conf"
if [ ! -f "$CONF_FILE" ]; then
    echo "ERROR: $CONF_FILE not found. Copy network.conf.template and fill in values." >&2
    exit 1
fi
. "$CONF_FILE"

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

while IFS='|' read -r _subnet _dev; do
    [ -z "$_subnet" ] && continue
    run ip route add "$_subnet" dev "$_dev" table bgpif
    run ip rule add iif "$_dev" lookup bgpif
done <<EOF
$BGP_SUBNETS
EOF

run ip route add blackhole default table bgpif

# ---------------------------------------------------------------------------
# PBR for US-bound traffic
#
# Prefer to route traffic to US (via VPN tunnel), avoiding congesting the
# default uplink.  Metric 500 fallback goes via the secondary gateway.
# ---------------------------------------------------------------------------

ip route flush table T101 2>/dev/null || true
ip rule  flush table T101 2>/dev/null || true

while IFS='|' read -r _subnet _dev; do
    [ -z "$_subnet" ] && continue
    run ip route add "$_subnet" dev "$_dev" scope link table T101
done <<EOF
$PBR_T101_CONNECTED
EOF

while IFS='|' read -r _gw _dev _metric; do
    [ -z "$_gw" ] && continue
    if [ -n "$_dev" ]; then
        run ip route add default via "$_gw" dev "$_dev" metric "$_metric" table T101
    else
        run ip route add default via "$_gw" metric "$_metric" table T101
    fi
done <<EOF
$PBR_T101_DEFAULTS
EOF

for _src in $PBR_T101_SOURCES; do
    run ip rule add from "$_src" lookup T101
done

# ---------------------------------------------------------------------------
# PBR for T102 source/dest steering via VPN
#
# Only this source+destination pair is steered to VPN.  No fallback gateway:
# if VPN is down the traffic is blocked rather than leaking elsewhere.
# Other traffic from 100.68.0.0/24 and other sources to 1.1.1.0/24 are
# unaffected (handled by the main table).
# Prerequisite: table "T102" must exist in /etc/iproute2/rt_tables.
# ---------------------------------------------------------------------------

ip route flush table T102 2>/dev/null || true
ip rule  flush table T102 2>/dev/null || true

run ip route add "$PBR_T102_CONNECTED_SUBNET" dev "$PBR_T102_CONNECTED_DEV" scope link table T102
run ip route add "$PBR_T102_DEST" via "$PBR_T102_ROUTE_GW" dev "$PBR_T102_ROUTE_DEV" table T102

run ip rule add from "$PBR_T102_SOURCE" to "$PBR_T102_DEST" lookup T102

## Exception: force this IP through the main table
run ip rule add from "$PBR_EXCEPTION_IP" lookup main

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
