#!/bin/sh
# set -x
# do not set -e
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ROUTEGW_0=192.0.2.1
ROUTEDEV_0=tun0
ROUTEGW_1=192.0.2.3
ROUTEDEV_1=vpn1
ROUTEGW_2=192.0.2.6
ROUTEDEV_2=vpn1

DEFAULTGW=192.0.2.17
DEFAULTNET=192.0.2.16/24
DEFAULTDEV=eth0
DEFAULTSRC=198.51.100.1

SECONDGW=192.0.2.33
SECONDNET=192.0.2.32/25
SECONDDEV="eth1.100"
SECONDSRC=192.0.2.37

WGDEV=tun0
WGGW=192.0.2.2
WGADDR=192.0.2.1

DIR_WORK=/root/scripts
DIR_TXT=/root/routes

ROUTE_BACKUP=""
cleanup() { [ -n "$ROUTE_BACKUP" ] && rm -f "$ROUTE_BACKUP"; true; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

is_iface_up() {
    ip link show dev "$1" up >/dev/null 2>&1
}

restore_default_route()
{
    ip ro flush scope global
    ip ro add default via "$DEFAULTGW" dev "$DEFAULTDEV" src "$DEFAULTSRC" metric 1000
    ip ro add default via "$SECONDGW" dev "$SECONDDEV" src "$SECONDSRC" metric 2000
    ip ro add "$SECONDNET" via "$SECONDGW" dev "$SECONDDEV"
}

save_backup()
{
    ROUTE_BACKUP=$(mktemp /tmp/route-backup.XXXXXX)
    ip route save table main > "$ROUTE_BACKUP"
}

rollback_from_backup()
{
    if [ -n "$ROUTE_BACKUP" ] && [ -f "$ROUTE_BACKUP" ]; then
        echo "Restoring routes from backup."
        ip route restore < "$ROUTE_BACKUP"
    else
        echo "No backup available, restoring default routes."
        restore_default_route
    fi
}

generate_ip_rules()
{
    printf "ro flush scope global \nro add default via %s dev %s metric 100\n" \
        "$ROUTEGW_0" "$ROUTEDEV_0" > "$DIR_TXT/iproute.tmp"
    printf "ro add default via %s dev %s src %s metric 1000\n" \
        "$DEFAULTGW" "$DEFAULTDEV" "$DEFAULTSRC" >> "$DIR_TXT/iproute.tmp"
    printf "ro add default via %s dev %s src %s metric 2000\n" \
        "$SECONDGW" "$SECONDDEV" "$SECONDSRC" >> "$DIR_TXT/iproute.tmp"

    grep -v '#' "$DIR_TXT/internal.txt" | \
      sed "s/^/ro add /;s/$/ via $SECONDGW dev $SECONDDEV /" >> "$DIR_TXT/iproute.tmp"

    grep -v '#' "$DIR_TXT/subscriber.txt" | \
      sed "s/^/ro add /;s/$/ via $DEFAULTGW dev $DEFAULTDEV /" >> "$DIR_TXT/iproute.tmp"

    #cat "$DIR_TXT/gateway.txt" "$DIR_TXT/chn.txt" "$DIR_TXT/dns-int.txt" | grep -v '#' | \
    cat "$DIR_TXT/gateway.txt" "$DIR_TXT/chn.txt" | grep -v '#' | \
      sed "s/^/ro add /;s/$/ via $DEFAULTGW dev $DEFAULTDEV src $DEFAULTSRC/" >> "$DIR_TXT/iproute.tmp"

    #sed "s/^/ro add /;s/$/ via $ROUTEGW_1 dev $ROUTEDEV_1 /" "$DIR_TXT/aws.txt" >> "$DIR_TXT/iproute.tmp"
    grep -v '#' "$DIR_TXT/us.txt" | \
      sed "s/^/ro add /;s/$/ via $ROUTEGW_1 dev $ROUTEDEV_1 /" >> "$DIR_TXT/iproute.tmp"

    grep -v '#' "$DIR_TXT/google.txt" | \
      sed "s/^/ro del /" >> "$DIR_TXT/iproute.tmp"

    if is_iface_up "$WGDEV"; then
        printf "ro add %s/32 via %s dev %s onlink\n" \
            "$WGADDR" "$WGGW" "$WGDEV" >> "$DIR_TXT/iproute.tmp"
    fi
}

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

do_restore()
{
    restore_default_route
}

do_apply()
{
    if [ "$1" != "" ] && [ "$2" != "" ]; then
        ROUTEGW_0=$1
        ROUTEDEV_0=$2
    fi

    if [ "${3:-}" != "" ] && [ "${4:-}" != "" ]; then
        ROUTEGW_1=$3
        ROUTEDEV_1=$4
    fi

    LOCAL_ONLY=no
    if [ "${5:-}" = "LOCAL" ]; then
        LOCAL_ONLY=yes
    fi

    if ! is_iface_up "$DEFAULTDEV"; then
        sleep 5
        if ! is_iface_up "$DEFAULTDEV"; then
            echo "Routing device $DEFAULTDEV is not up, network inaccessible, exit."
            exit 1
        fi
    fi

    save_backup

    restore_default_route

    if [ "$LOCAL_ONLY" = "yes" ]; then
        echo "Local routing requested, accept."
        exit
    elif ! is_iface_up "$ROUTEDEV_0"; then
        echo "Routing device $ROUTEDEV_0 is not up, local routing only."
        exit
    fi

    if [ ! -d "$DIR_TXT" ]; then
        echo "$DIR_TXT is not a directory, give up."
        exit 1
    fi

    python3 "$DIR_WORK/generate-ip-list.py" -o "$DIR_TXT"

    generate_ip_rules

    if [ ! -s "$DIR_TXT/iproute.tmp" ]; then
        echo "ERROR: $DIR_TXT/iproute.tmp is missing or empty after generate_ip_rules."
        exit 1
    fi

    if ! ip -force -batch "$DIR_TXT/iproute.tmp"; then
        echo "ERROR: ip batch apply failed."
        rollback_from_backup
        exit 1
    fi

    if [ -x "$DIR_WORK/set-pbr.sh" ]; then
        sh "$DIR_WORK/set-pbr.sh" || echo "WARNING: set-pbr.sh failed (exit $?), continuing."
    fi

    rndc flush
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

case "${1:-}" in
    restore)
        do_restore
        ;;
    *)
        do_apply "$@"
        ;;
esac
