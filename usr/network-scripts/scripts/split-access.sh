#!/bin/sh
# No set -e: partial failures should not abort the loop; errors are tracked
# individually via ERRFILE and reported at the end.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
#
# split-access.sh — Symmetric routing for multi-homed hosts
#
# Ensures packets leave via the same interface they arrived on.
# Handles: primary IPs, secondary /32 IPs on shared interfaces, VLANs, IPv6.
#
# Prerequisites — add to /etc/iproute2/rt_tables:
#   1  T1
#   2  T2
#   3  T3
#   4  T4
#   5  T5
#   6  T6
#   7  T7
#
# Usage:
#   split-access.sh          — apply all rules (idempotent)
#   split-access.sh teardown — remove all rules added by this script
#

ERRFILE=$(mktemp /tmp/split-access.XXXXXX)
cleanup() { rm -f "$ERRFILE"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Configuration
#
# Each entry is a single line with fields separated by '|':
#
#   TABLE | IFACE | LOCAL_IP | GATEWAY | SUBNET | TYPE | [IPV6_NET | IPV6_GW]
#
# TYPE is one of:
#   primary   — IP already assigned to the interface (by system/networkd/etc.)
#   secondary — IP must be added as /32 (multiple public IPs on one interface)
#
# For secondary IPs on a shared physical interface (including VLANs), the
# SUBNET route uses the interface's primary address as src, not the /32.
# The GATEWAY field is the next-hop for that interface's L2 segment.
# ---------------------------------------------------------------------------

ENTRIES="
T1|eth0|192.0.2.18|192.0.2.17|192.0.2.16/24|primary
T2|eth1.100|192.0.2.37|192.0.2.33|192.0.2.32/25|primary
T3|vpn1|192.0.2.4|192.0.2.5|192.0.2.0/24|primary|2001:db8:11::/48|fe80::1
T4|eth0|198.51.100.1|192.0.2.17|192.0.2.16/24|secondary
T5|eth0|198.51.100.3|192.0.2.17|192.0.2.16/24|secondary
T6|eth0|198.51.100.2|192.0.2.17|192.0.2.16/24|secondary
T7|eth0|198.51.100.4|192.0.2.17|192.0.2.16/24|secondary
"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() { printf '[split-access] %s\n' "$*"; }

# Flush a routing table (both address families). Silently ignore if empty.
flush_table() {
    ip route flush table "$1" 2>/dev/null || true
    ip -6 route flush table "$1" 2>/dev/null || true
}

flush_rules() {
    ip rule flush table "$1" 2>/dev/null || true
    ip -6 rule flush table "$1" 2>/dev/null || true
}

# Remove a /32 address from an interface if present.
remove_addr() {
    ip addr del "$1/32" dev "$2" 2>/dev/null || true
}

# For secondary IPs, find the primary address on the interface to use as
# route src for the local subnet. Falls back to the secondary IP itself.
get_primary_src() {
    _dev="$1"
    _self="$2"
    _primary=$(ip -4 -o addr show dev "$_dev" scope global \
        | awk '!/\/32/{sub(/\/.*/, "", $4); print $4; exit}')
    printf '%s' "${_primary:-$_self}"
}

# ---------------------------------------------------------------------------
# Apply — idempotent: flush-then-add per table
# ---------------------------------------------------------------------------

apply() {
    : > "$ERRFILE"
    while IFS='|' read -r TABLE IFACE IP GW SUBNET TYPE V6NET V6GW REST; do
        [ -z "$TABLE" ] && continue

        log "configuring $TABLE: $IP on $IFACE"

        if ! ip link show dev "$IFACE" >/dev/null 2>&1; then
            log "SKIPPED $TABLE: interface $IFACE does not exist"
            echo x >> "$ERRFILE"
            continue
        fi

        flush_table "$TABLE"
        flush_rules "$TABLE"

        if [ "$TYPE" = "secondary" ]; then
            if ! ip addr show dev "$IFACE" | grep -q "inet ${IP}/32"; then
                ip addr add "$IP/32" dev "$IFACE" || { log "FAILED to add $IP/32 on $IFACE"; echo x >> "$ERRFILE"; continue; }
            fi
            SRC=$(get_primary_src "$IFACE" "$IP")
        else
            SRC="$IP"
        fi

        if  ip route add "$SUBNET" dev "$IFACE" src "$SRC" table "$TABLE" &&
            ip route add default via "$GW" dev "$IFACE" src "$IP" table "$TABLE" &&
            ip rule add from "$IP" table "$TABLE"; then
            :
        else
            log "FAILED $TABLE: route/rule setup for $IP"
            echo x >> "$ERRFILE"
            continue
        fi

        if [ -n "$V6NET" ] && [ -n "$V6GW" ]; then
            ip -6 route add default via "$V6GW" dev "$IFACE" table "$TABLE" &&
            ip -6 rule add from "$V6NET" table "$TABLE" ||
                log "WARNING $TABLE: IPv6 setup failed for $V6NET"
        fi
    done <<EOF
$ENTRIES
EOF

    if [ -s "$ERRFILE" ]; then
        _nerr=$(wc -l < "$ERRFILE")
        log "completed with $_nerr error(s)"
        return 1
    fi
    log "done"
}

# ---------------------------------------------------------------------------
# Teardown — remove everything this script added
# ---------------------------------------------------------------------------

teardown() {
    while IFS='|' read -r TABLE IFACE IP GW SUBNET TYPE V6NET V6GW REST; do
        [ -z "$TABLE" ] && continue

        log "removing $TABLE: $IP on $IFACE"

        flush_rules "$TABLE"
        flush_table "$TABLE"

        if [ "$TYPE" = "secondary" ]; then
            remove_addr "$IP" "$IFACE"
        fi
    done <<EOF
$ENTRIES
EOF

    log "teardown complete"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

case "${1:-apply}" in
    teardown|down|clean)
        teardown
        ;;
    apply|up|"")
        apply
        ;;
    *)
        echo "Usage: $0 [apply|teardown]" >&2
        exit 1
        ;;
esac
