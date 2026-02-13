#!/bin/sh

#ROUTEGW=192.168.98.65
#ROUTEDEV=lgre0
#ROUTEGW_0=192.168.7.10
#ROUTEDEV_0=manifold
ROUTEGW_0=192.168.7.12
ROUTEDEV_0=manifold
ROUTEGW_1=192.168.7.12
ROUTEDEV_1=manifold

DEFAULTGW=192.168.253.1
DEFAULTDEV=eth0
DIR_WORK=/root/scripts
DIR_TXT=/root/routes

restore_default_route()
{
    ip ro flush scope global
    ip ro add default via $DEFAULTGW dev $DEFAULTDEV
}

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
    printf "ro flush scope global\nro add default via $ROUTEGW_0 dev $ROUTEDEV_0\n" > $DIR_TXT/iproute.tmp

    # Use default gw for following routes
    cat $DIR_TXT/internal.txt $DIR_TXT/gateway.txt $DIR_TXT/chn.txt | \
      sed "s/^/ro add /;s/$/ via $DEFAULTGW dev $DEFAULTDEV/" >> $DIR_TXT/iproute.tmp

    # Always use ROUTEGW_1 for following routes
    sed "s/^/ro add /;s/$/ via $ROUTEGW_1 dev $ROUTEDEV_1/" $DIR_TXT/aws.txt >> $DIR_TXT/iproute.tmp

    # Always use default gw for following routes
    sed "s/^/ro del /" $DIR_TXT/google.txt >> $DIR_TXT/iproute.tmp
}

## Execution starts here

case $1 in
    restore)
      restore_default_route
      exit
      ;;
    *)
      ;;
esac

# Detect whether default network device is UP
if ! ip a | grep $DEFAULTDEV | grep UP > /dev/null; then
    sleep 5
    if ! ip a | grep $DEFAULTDEV | grep UP > /dev/null; then
    	echo "Routing device $DEFAULTDEV is not up, network inaccessable, exit."
        exit 1;
    fi
fi

# Restore to default route anyway to make sure IP lists can be generated correctly.
# This may lead to interruption of established connections.
restore_default_route

# If routing device is DOWN, stop here
if ! ip a | grep $ROUTEDEV_0 | grep UP > /dev/null; then
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

generate_ip_rules

# Execute IP rules for real
ip -force -batch $DIR_TXT/iproute.tmp || true
