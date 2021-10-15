#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

## Blackhole for BGP neighbor interfaces
ip route flush table bgpif
ip route add 192.168.136.0/30 dev eno4.2 table bgpif
ip route add 192.168.136.4/30 dev eno4.3 table bgpif
ip route add 192.168.136.8/30 dev eno4.4 table bgpif
ip route add 192.168.136.12/30 dev eno4.5 table bgpif
ip route add 192.168.136.16/30 dev eno4.6 table bgpif
ip route add blackhole 0/0 table bgpif

if ! $(ip rule | grep "eno4.2" >/dev/null 2>&1); then
	ip rule add iif eno4.2 lookup bgpif
fi
if ! $(ip rule | grep "eno4.3" >/dev/null 2>&1); then
	ip rule add iif eno4.3 lookup bgpif
fi
if ! $(ip rule | grep "eno4.4" >/dev/null 2>&1); then
	ip rule add iif eno4.4 lookup bgpif
fi
if ! $(ip rule | grep "eno4.5" >/dev/null 2>&1); then
	ip rule add iif eno4.5 lookup bgpif
fi
if ! $(ip rule | grep "eno4.6" >/dev/null 2>&1); then
	ip rule add iif eno4.6 lookup bgpif
fi

## PBR for google.bfsu.edu.cn
# Prefer to route traffic to US, avoiding congesting the default
ip route flush table T101
#ip route add default via 192.168.6.17 dev bfsu metric 100 table T101
ip route add default via 192.168.6.78 dev bfsu metric 200 table T101
ip route add default via 192.168.253.116 metric 500 table T101
if ! $(ip rule | grep 192.168.253.114 >/dev/null 2>&1); then
	ip rule add from 192.168.253.114 lookup T101
	#true
fi
if ! $(ip rule | grep 192.168.253.110 >/dev/null 2>&1); then
	ip rule add from 192.168.253.110 lookup T101
	#true
fi
