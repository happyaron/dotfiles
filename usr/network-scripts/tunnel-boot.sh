#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

CONF_FILE="$(dirname "$0")/network.conf"
if [ ! -f "$CONF_FILE" ]; then
    echo "ERROR: $CONF_FILE not found. Copy network.conf.template and fill in values." >&2
    exit 1
fi
. "$CONF_FILE"

V6ETH="$TUNNEL_V6_DEV"
V6ADDR="$TUNNEL_V6_ADDR"
V6LOCAL="$TUNNEL_V6_LOCAL"
V6REMOTE="$TUNNEL_V6_REMOTE"
TUNNEL="$TUNNEL_NAME"
TUNNEL_ADDR="$TUNNEL_V4_ADDR"

apply() {
    if ! ip -6 addr show dev "$V6ETH" | grep -q "$V6ADDR"; then
        ip -6 addr add "$V6ADDR" dev "$V6ETH"
    fi

    if ! ip link show "$TUNNEL" >/dev/null 2>&1; then
        ip -6 tunnel add "$TUNNEL" mode ipip6 local "$V6LOCAL" remote "$V6REMOTE" dev "$V6ETH"
        ip addr add dev "$TUNNEL" "$TUNNEL_ADDR"
        ip link set "$TUNNEL" up
    fi
}

teardown() {
    if ip link show "$TUNNEL" >/dev/null 2>&1; then
        ip link set "$TUNNEL" down
        ip -6 tunnel del "$TUNNEL"
    fi
    ip -6 addr del "$V6ADDR" dev "$V6ETH" 2>/dev/null || true
}

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
