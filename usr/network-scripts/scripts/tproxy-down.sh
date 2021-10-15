#!/bin/sh

iptables -t mangle --flush PREROUTING

ip rule delete fwmark 1/1 > /dev/null 2>&1
