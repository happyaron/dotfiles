#!/bin/sh
# Add the following entries to /etc/iproute2/rt_tables before proceeding:
# 252     T1
# 251     T2

IF1="eth0"
IP1="192.0.2.37"
P1="192.0.2.33"
P1_NET="192.0.2.32/25"

IF2="gre0"
IP2="192.0.2.83"
P2="192.0.2.82"
P2_NET="192.0.2.82/26"

IF3="lgre1"
IP3="192.0.2.85"
P3="192.0.2.86"
P3_NET="192.0.2.84/26"

ip route add $P1_NET dev $IF1 src $IP1 table T1
ip route add default via $P1 dev $IF1 src $IP1 table T1
ip rule add from $IP1 table T1

ip route add $P2_NET dev $IF2 src $IP2 table T2
ip route add default via $P2 dev $IF2 src $IP2 table T2
ip rule add from $IP2 table T2

ip route add $P2_NET dev $IF3 src $IP3 table T3
ip route add default via $P3 dev $IF3 src $IP3 table T3
ip rule add from $IP3 table T3
