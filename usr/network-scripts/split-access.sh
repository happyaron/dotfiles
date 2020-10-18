#!/bin/sh
# Add the following entries to /etc/iproute2/rt_tables before proceeding:
# 252     T1
# 251     T2

IF1="eth0"
IP1="192.168.253.116"
P1="192.168.253.1"
P1_NET="192.168.253.0/25"

IF2="lgre0"
IP2="192.168.98.66"
P2="192.168.98.65"
P2_NET="192.168.98.64/26"

IF3="lgre1"
IP3="192.168.98.129"
P3="192.168.98.130"
P3_NET="192.168.98.128/26"

ip route add $P1_NET dev $IF1 src $IP1 table T1
ip route add default via $P1 dev $IF1 src $IP1 table T1
ip rule add from $IP1 table T1

ip route add $P2_NET dev $IF2 src $IP2 table T2
ip route add default via $P2 dev $IF2 src $IP2 table T2
ip rule add from $IP2 table T2

ip route add $P2_NET dev $IF3 src $IP3 table T3
ip route add default via $P3 dev $IF3 src $IP3 table T3
ip rule add from $IP3 table T3
