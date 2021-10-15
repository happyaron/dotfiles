#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

V6ETH='eth1.100'
V6ADDR='2001:db8::116/64'

detect_v6addr(){
    if $(ip -6 addr show dev $1 | grep $2 2>&1 >/dev/null); then
        return 0;
    fi
    ip -6 addr add $2 dev $1
}

detect_v6addr $V6ETH $V6ADDR

#ipsec up vpn2-osk001
#ip -6 tunnel add vpn2-osk001 mode ipip6 local 2001:db8::116 remote 2001:db8::704 dev eth1
#ip addr add dev vpn2-osk001 192.0.2.7/25
#ip link set vpn2-osk001 up

ip -6 tunnel add mytunnel mode ipip6 local 2001:db8::116 remote 2001:db8::136 dev $V6ETH
ip addr add dev mytunnel 192.0.2.65/30
ip link set mytunnel up
