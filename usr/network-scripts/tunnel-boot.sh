#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

IFNAME=""
V6ETH='eno2'
V6ADDR=''
V6REMOTE=''

detect_v6addr(){
    if $(ip -6 addr show dev $1 | grep $2 2>&1 >/dev/null); then
        return 0;
    fi
    ip -6 addr add $2 dev $1
}

detect_v6addr $V6ETH $V6ADDR

ip -6 tunnel add $IFNAME mode ipip6 local $V6ADDR remote $V6REMOTE dev $V6ETH
ip addr add dev $IFNAME 192.168.130.1/30
ip link set $IFNAME up
