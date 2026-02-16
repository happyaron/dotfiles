#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

V6ETH='eth1.100'
V6ADDR='2001:db8::116/64'
V6LOCAL='2001:db8::116'
V6REMOTE='2001:db8::136'
TUNNEL='mytunnel'
TUNNEL_ADDR='192.0.2.65/30'

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
