#!/bin/sh
set -e
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ROUTE_BACKUP=""
cleanup() { [ -n "$ROUTE_BACKUP" ] && rm -f "$ROUTE_BACKUP"; true; }
trap cleanup EXIT

ROUTEGW_0=192.168.6.194
ROUTEDEV_0=wg0
ROUTEGW_1=192.168.6.17
ROUTEDEV_1=bfsu
ROUTEGW_2=192.168.6.78
ROUTEDEV_2=bfsu

DEFAULTGW=192.168.137.1
DEFAULTNET=192.168.137.0/24
DEFAULTDEV=eno4
DEFAULTSRC=60.247.127.219

SECONDGW=192.168.253.1
SECONDNET=192.168.253.0/25
SECONDDEV="eno2.830"
SECONDSRC=192.168.253.116

DIR_WORK=/root/scripts
DIR_TXT=/root/routes

restore_default_route()
{
    ip ro flush scope global
    ip ro add default via $DEFAULTGW dev $DEFAULTDEV src $DEFAULTSRC metric 1000
    ip ro add default via $SECONDGW dev $SECONDDEV src $SECONDSRC metric 2000
    ip ro add $SECONDNET via $SECONDGW dev $SECONDDEV
}

restore_ip_ruleset()
{
	ipset restore < /etc/ipset.conf 
	iptables -t mangle -A OUTPUT -m set --match-set cnset dst -j MARK --set-mark 201
	ip rule del from 10.11.89.0/24 lookup 200
	ip rule del fwmark 201 lookup 201
	ip rule add from 10.11.89.0/24 lookup 200
	ip rule add fwmark 201 lookup 201
}

case "$1" in
    restore)
      restore_default_route
      exit
      ;;
esac

if [ "$1" != "" ] && [ "$2" != "" ]; then
	ROUTEGW_0=$1
	ROUTEDEV_0=$2
fi

if [ "$5" = "LOCAL" ]; then
	LOCAL_ONLY=yes;
fi

generate_ip_list ()
{
    cd $DIR_WORK

    if [ -s cnroutes.py ]; then
        python cnroutes.py >/dev/null
        mv iplist.txt $DIR_TXT/chn.txt
    else
        echo "cnroutes.py does not exist, stop."
        exit 1
    fi

    if [ -s special-blocks.py ]; then
        python special-blocks.py >/dev/null
        mv *.txt $DIR_TXT
    else
        echo "special-blocks.py does not exist, stop."
        exit 1
    fi
}

generate_ip_rules ()
{
    # flush routing table and set default route to ROUTEDEV_0
    printf "ro flush scope global \nro add default via $ROUTEGW_0 dev $ROUTEDEV_0 metric 100\n" > $DIR_TXT/iproute.tmp
    printf "ro add default via $DEFAULTGW dev $DEFAULTDEV src $DEFAULTSRC metric 1000\n" >> $DIR_TXT/iproute.tmp
    printf "ro add default via $SECONDGW dev $SECONDDEV src $SECONDSRC metric 2000\n" >> $DIR_TXT/iproute.tmp

    # Use secondary interface gw for internal routes
    cat $DIR_TXT/internal.txt | grep -v '#' | \
      sed "s/^/ro add /;s/$/ via $SECONDGW dev $SECONDDEV /" >> $DIR_TXT/iproute.tmp

    # Use default interface gw for subscriber routes
    cat $DIR_TXT/subscriber.txt | grep -v '#' | \
      sed "s/^/ro add /;s/$/ via $DEFAULTGW dev $DEFAULTDEV /" >> $DIR_TXT/iproute.tmp

    # Use default interface gw for chn routes
    cat $DIR_TXT/gateway.txt $DIR_TXT/chn.txt $DIR_TXT/dns-int.txt | grep -v '#' | \
      sed "s/^/ro add /;s/$/ via $DEFAULTGW dev $DEFAULTDEV src $DEFAULTSRC/" >> $DIR_TXT/iproute.tmp

    # Always use ROUTEGW_1 for following routes
    #sed "s/^/ro add /;s/$/ via $ROUTEGW_1 dev $ROUTEDEV_1 /" $DIR_TXT/aws.txt >> $DIR_TXT/iproute.tmp
    cat $DIR_TXT/us.txt | grep -v '#' | \
      sed "s/^/ro add /;s/$/ via $ROUTEGW_1 dev $ROUTEDEV_1 /" >> $DIR_TXT/iproute.tmp

    # Always use default gw for following routes
    cat $DIR_TXT/google.txt | grep -v '#' | \
      sed "s/^/ro del /" >> $DIR_TXT/iproute.tmp
}

## Execution starts here

# Detect whether default network device is UP
if ! ip a | grep $DEFAULTDEV | grep UP > /dev/null; then
    sleep 5
    if ! ip a | grep $DEFAULTDEV | grep UP > /dev/null; then
    	echo "Routing device $DEFAULTDEV is not up, network inaccessable, exit."
        exit 1;
    fi
fi

#generate_ip_list

# Restore to default route anyway to make sure IP lists can be generated correctly.
# This may lead to interruption of established connections.
restore_default_route

# If routing device is DOWN, stop here
if [ "$LOCAL_ONLY" = "yes" ]; then
    echo "Local routing requested, accept."
    exit;
elif ! ip a | grep $ROUTEDEV_0 | grep UP > /dev/null; then
    echo "Routing device $ROUTEDEV_0 is not up, local routing only."
    exit;
fi

# Regenerate IP list if cached ones are not available
if [ -d $DIR_TXT ]; then
    [ -f $DIR_TXT/chn.txt ] || generate_ip_list
    [ -f $DIR_TXT/google.txt ] || generate_ip_list
    [ -f $DIR_TXT/aws.txt ] || generate_ip_list
else
    echo "$DIR_TXT is not a directory, give up."
    exit 1;
fi

#generate_ip_list
generate_ip_rules

# Backup current routing table before flush
ROUTE_BACKUP=$(mktemp /tmp/route-backup.XXXXXX)
ip route save table main > "$ROUTE_BACKUP"

# Execute IP rules for real; restore from backup on failure
if ! ip -force -batch $DIR_TXT/iproute.tmp; then
	echo "ERROR: ip batch apply failed, restoring routes from backup."
	ip route restore < "$ROUTE_BACKUP"
	exit 1
fi

ip route add 192.168.6.194/32 via 192.168.6.193 dev wg0 onlink
#restore_default_route
#restore_ip_ruleset

if [ -x "$DIR_WORK/set-pbr.sh" ]; then
	sh "$DIR_WORK/set-pbr.sh";
fi

#service dnsmasq restart
service smartdns restart
rndc flush
