#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

## Blackhole for BGP neighbor interfaces
ip route flush table bgpif
ip route add 192.0.2.48/30 dev eth0.2 table bgpif
ip route add 192.0.2.52/30 dev eth0.3 table bgpif
ip route add 192.0.2.56/30 dev eth0.4 table bgpif
ip route add 192.0.2.60/30 dev eth0.5 table bgpif
ip route add 192.0.2.64/30 dev eth0.6 table bgpif
ip route add blackhole 0/0 table bgpif

if ! $(ip rule | grep "eth0.2" >/dev/null 2>&1); then
	ip rule add iif eth0.2 lookup bgpif
fi
if ! $(ip rule | grep "eth0.3" >/dev/null 2>&1); then
	ip rule add iif eth0.3 lookup bgpif
fi
if ! $(ip rule | grep "eth0.4" >/dev/null 2>&1); then
	ip rule add iif eth0.4 lookup bgpif
fi
if ! $(ip rule | grep "eth0.5" >/dev/null 2>&1); then
	ip rule add iif eth0.5 lookup bgpif
fi
if ! $(ip rule | grep "eth0.6" >/dev/null 2>&1); then
	ip rule add iif eth0.6 lookup bgpif
fi

## PBR for google.vpn1.edu.cn
# Prefer to route traffic to US, avoiding congesting the default
ip route flush table T101
#ip route add default via 192.0.2.3 dev vpn1 metric 100 table T101
ip route add default via 192.0.2.6 dev vpn1 metric 200 table T101
ip route add default via 192.0.2.37 metric 500 table T101
if ! $(ip rule | grep 192.0.2.35 >/dev/null 2>&1); then
	ip rule add from 192.0.2.35 lookup T101
	#true
fi
if ! $(ip rule | grep 192.0.2.34 >/dev/null 2>&1); then
	ip rule add from 192.0.2.34 lookup T101
	#true
fi
