#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# Add the following entries to /etc/iproute2/rt_tables before proceeding:
# 252     T1
# 251     T2

IF1="eth0"
IP1="192.0.2.18"
P1="192.0.2.17"
P1_NET="192.0.2.16/24"

IF4="eth0"
IP4="198.51.100.1"
P4="192.0.2.17"
P4_SRC="192.0.2.18"
P4_NET="192.0.2.16/24"

IF5="eth0"
IP5="198.51.100.3"
P5="192.0.2.17"
P5_SRC="192.0.2.18"
P5_NET="192.0.2.16/24"

IF6="eth0"
IP6="198.51.100.2"
P6="192.0.2.17"
P6_SRC="192.0.2.18"
P6_NET="192.0.2.16/24"

IF2="eth1.100"
IP2="192.0.2.37"
P2="192.0.2.33"
P2_NET="192.0.2.32/25"

IF3="vpn1"
IP3="192.0.2.4"
P3="192.0.2.5"
P3_NET="192.0.2.0/24"
P3_NET6="2001:db8:11::/48"
P3_GW6="fe80::1"

ip route add $P1_NET dev $IF1 src $IP1 table T1
ip route add default via $P1 dev $IF1 src $IP1 table T1
ip rule add from $IP1 table T1

ip route add $P2_NET dev $IF2 src $IP2 table T2
ip route add default via $P2 dev $IF2 src $IP2 table T2
ip rule add from $IP2 table T2

ip route add $P3_NET dev $IF3 src $IP3 table T3
ip route add default via $P3 dev $IF3 src $IP3 table T3
ip rule add from $IP3 table T3
ip -6 route add default via $P3_GW6 dev $IF3 table T3
ip -6 rule add from $P3_NET6 table T3

ip addr add $IP4/32 dev $IF4
ip route add default via $P4 dev $IF4 src $IP4 table T4
ip route add $P4_NET via $P4 dev $IF4 src $P4_SRC table T4
ip rule add from $IP4 table T4

ip addr add $IP5/32 dev $IF5
ip route add default via $P5 dev $IF5 src $IP5 table T5
ip route add $P5_NET via $P5 dev $IF5 src $P5_SRC table T5
ip rule add from $IP5 table T5

ip addr add $IP6/32 dev $IF6
ip route add default via $P6 dev $IF6 src $IP6 table T6
ip route add $P6_NET via $P6 dev $IF6 src $P6_SRC table T6
ip rule add from $IP6 table T6

# Rule for honeypot project
ip rule fwmark 0x64 lookup 102
