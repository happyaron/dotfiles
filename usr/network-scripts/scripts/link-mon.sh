#!/bin/sh
set -e
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

#LINKGW_0=192.168.6.78
#LINKDEV_0=bfsu
LINKGW_0=192.168.6.194
LINKDEV_0=wg0

LINKGW_1=192.168.6.17
LINKDEV_1=bfsu

LINKGW_2=192.168.6.78
LINKDEV_2=bfsu
#LINKGW_2=192.168.6.130
#LINKDEV_2=backbone

TEST_TARGET=8.8.4.4

EXEC_SWITCH_CMD=/root/scripts/set-routes.sh
EXEC_STATE_DATA=/root/scripts/link-mon.state
EXEC_STATE_STAMP=/root/scripts/link-mon.stamp

probe_cmd(){
	PROBE_OUTPUT=$(ping -q -w5 $1| grep "transmitted")
	PROBE_INDIC_1=$(echo $PROBE_OUTPUT | awk '{print $4}')
	PROBE_INDIC_2=$(echo $PROBE_OUTPUT | awk '{print $6}')

	ping -q -w5 $1|grep 'rtt'|awk '{print $4}'|cut -f2 -d'/'

	if [ $PROBE_INDIC_1 -eq 0 ] && [ "$PROBE_INDIC_2" = "100%" ]; then
		return 1;
	else
		return 0;
	fi
}

probe_net(){
	if RTT_1=`probe_cmd $1`; then
		LINK1=1
	else
		LINK1=0
	fi
	if RTT_2=`probe_cmd $3`; then
		LINK2=1
	else
		LINK2=0
	fi

	if [ $LINK1 -eq 1 ]; then
		LINKGW_ACTIVE=$1
		LINKDEV_ACTIVE=$2
		LINKRTT_ACTIVE=$RTT_1
		LINKGW_BAKUP=$3
		LINKDEV_BAKUP=$4
		LINKRTT_BAKUP=$RTT_2
		PROBE_ALIVE=0
	elif [ $LINK2 -eq 1 ]; then
		LINKGW_ACTIVE=$3
		LINKDEV_ACTIVE=$4
		LINKRTT_ACTIVE=$RTT_2
		LINKGW_BAKUP=$1
		LINKDEV_BAKUP=$2
		LINKRTT_BAKUP=$RTT_1
		PROBE_ALIVE=1
	else
		PROBE_ALIVE=2
	fi

	if [ $LINK1 -eq 1 ] && [ $LINK2 -eq 1 ]; then
	    if [ `echo "$RTT_2 + 20 < $RTT_1" | bc` -eq 1 ]; then
		LINKGW_ACTIVE=$3
		LINKDEV_ACTIVE=$4
		LINKRTT_ACTIVE=$RTT_2
		LINKGW_BAKUP=$1
		LINKDEV_BAKUP=$2
		LINKRTT_BAKUP=$RTT_1
		PROBE_ALIVE=1
	    fi
	fi

	#return $PROBE_ALIVE
}

restart_ipsec(){
	ipsec down $LINKDEV_0
	ipsec up $LINKDEV_0
	ip link set $LINKDEV_0 up
}

write_data(){
	TIME_NOW=$(date +%s)
	cat << EOF > $EXEC_STATE_DATA
# TIMESTAMP: $TIME_NOW
# CHECK: $8
ROUTING_MODE=$7
LINKGW_ACTIVE=$1
LINKDEV_ACTIVE=$2
LINKRTT_ACTIVE=$3
LINKGW_BACKUP=$4
LINKDEV_BACKUP=$5
LINKRTT_BACKUP=$6
EOF
}

if ! [ -x $EXEC_SWITCH_CMD ]; then
	echo "EXEC_SWITCH_CMD not found, exit" >&2
	exit 1;
fi

if [ -f $EXEC_STATE_DATA ]; then
	. $EXEC_STATE_DATA
fi

if [ "$LINKGW_ACTIVE" = "$LINKGW_1" ] && [ "$LINKDEV_ACTIVE" = "$LINKDEV_1" ]; then
	#restart_ipsec
	PROBEGW_NOW=$LINKGW_1
	PROBEDEV_NOW=$LINKDEV_1
	PROBEGW_BAK=$LINKGW_0
	PROBEDEV_BAK=$LINKDEV_0
else
	PROBEGW_NOW=$LINKGW_0
	PROBEDEV_NOW=$LINKDEV_0
	PROBEGW_BAK=$LINKGW_1
	PROBEDEV_BAK=$LINKDEV_1
fi

probe_net $PROBEGW_NOW $PROBEDEV_NOW $PROBEGW_BAK $PROBEDEV_BAK
if  [ ! -f $EXEC_STATE_STAMP ] || [ "$ROUTING_MODE" != "NORMAL" ] || [ $PROBE_ALIVE -eq 1 ]; then
		ROUTING_MODE=NORMAL
		$EXEC_SWITCH_CMD $LINKGW_ACTIVE $LINKDEV_ACTIVE $LINKGW_BAKUP $LINKDEV_BAKUP $ROUTING_MODE
		touch $EXEC_STATE_STAMP
elif [ $PROBE_ALIVE -eq 2 ]; then
		ROUTING_MODE=LOCAL
		$EXEC_SWITCH_CMD $LINKGW_ACTIVE $LINKDEV_ACTIVE $LINKGW_BAKUP $LINKDEV_BAKUP $ROUTING_MODE
else
	ROUTING_MODE=NORMAL
fi

if probe_cmd $TEST_TARGET 2>/dev/null; then
	write_data $LINKGW_ACTIVE $LINKDEV_ACTIVE $LINKRTT_ACTIVE $LINKGW_BAKUP $LINKDEV_BAKUP $LINKRTT_BAKUP $ROUTING_MODE PASS
else
	write_data $LINKGW_ACTIVE $LINKDEV_ACTIVE $LINKRTT_ACTIVE $LINKGW_BAKUP $LINKDEV_BAKUP $LINKRTT_BAKUP $ROUTING_MODE FAIL
fi

cat $EXEC_STATE_DATA
