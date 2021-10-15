#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

V6ETH='eno2.830'
V6ADDR='2001:da8:20f:4430:250::116/64'

detect_v6addr(){
    if $(ip -6 addr show dev $1 | grep $2 2>&1 >/dev/null); then
        return 0;
    fi
    ip -6 addr add $2 dev $1
}

detect_v6addr $V6ETH $V6ADDR

#ipsec up artery-osk001
#ip -6 tunnel add artery-osk001 mode ipip6 local 2001:da8:20f:4430:250::116 remote 2400:ddc0:2333:6666::68df:c704 dev eno2
#ip addr add dev artery-osk001 192.168.6.129/25
#ip link set artery-osk001 up

ip -6 tunnel add youngcow mode ipip6 local 2001:da8:20f:4430:250::116 remote 2402:f000:1:405:166:111:5:136 dev $V6ETH
ip addr add dev youngcow 192.168.130.1/30
ip link set youngcow up
