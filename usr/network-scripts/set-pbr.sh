#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

## Blackhole for BGP neighbor interfaces
ip route flush table bgpif
ip route add 192.168.XXX.0/30 dev "$ENO".2 table bgpif
ip route add 192.168.XXX.4/30 dev "$ENO".3 table bgpif
ip route add 192.168.XXX.8/30 dev "$ENO".4 table bgpif
ip route add 192.168.XXX.12/30 dev "$ENO".5 table bgpif
ip route add 192.168.XXX.16/30 dev "$ENO".6 table bgpif
ip route add blackhole 0/0 table bgpif

if ! $(ip rule | grep ""$ENO".2" >/dev/null 2>&1); then
	ip rule add iif "$ENO".2 lookup bgpif
fi
if ! $(ip rule | grep ""$ENO".3" >/dev/null 2>&1); then
	ip rule add iif "$ENO".3 lookup bgpif
fi
if ! $(ip rule | grep ""$ENO".4" >/dev/null 2>&1); then
	ip rule add iif "$ENO".4 lookup bgpif
fi
if ! $(ip rule | grep ""$ENO".5" >/dev/null 2>&1); then
	ip rule add iif "$ENO".5 lookup bgpif
fi
if ! $(ip rule | grep ""$ENO".6" >/dev/null 2>&1); then
	ip rule add iif "$ENO".6 lookup bgpif
fi

# Prefer to route traffic to GW1, avoiding congesting the default
ip route flush table T101
ip route add default via $GW1 dev $DEST_DEV metric 100 table T101
ip route add default via $GW2 dev $DEST_DEV metric 200 table T101
ip route add default via $GW0 metric 500 table T101
if ! $(ip rule | grep $ROUTER2 >/dev/null 2>&1); then
	ip rule add from $ROUTER2 lookup T101
fi
if ! $(ip rule | grep $ROUTER3 >/dev/null 2>&1); then
	ip rule add from $ROUTER3 lookup T101
fi
