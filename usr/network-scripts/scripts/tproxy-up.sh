#!/bin/sh

ipset restore < /etc/iptables/rules.ipset

iptables -t mangle --flush PREROUTING
iptables -t mangle -A PREROUTING -s 192.168.100.160/27 -p tcp -m tcp --dport 80 -j TPROXY --on-ip 0.0.0.0 --on-port 3129 --tproxy-mark 1/1
iptables -t mangle -A PREROUTING -m set --match-set int-net src -p tcp -m tcp --dport 80 -j TPROXY --on-ip 0.0.0.0 --on-port 3128 --tproxy-mark 1/1
iptables -t mangle -A PREROUTING -i ppp+ -p tcp -m tcp --dport 80 -j TPROXY --on-ip 0.0.0.0 --on-port 3128 --tproxy-mark 1/1
iptables -t mangle -A PREROUTING -i eth+ -p tcp -m tcp --sport 80 -j MARK --set-mark 1/1

ip rule delete fwmark 1/1 > /dev/null 2>&1
ip rule add fwmark 1/1 table 1
ip route add local 0/0 dev lo table 1
