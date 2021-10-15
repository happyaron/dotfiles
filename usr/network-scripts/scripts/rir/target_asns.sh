#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# CN2: Exclude everything from APNIC, exclude US routes from ARIN
CODE_OVERSEAS_APNIC_EXCLUDE="."
CODE_OVERSEAS_ARIN_EXCLUDE="(US)"
#CODE_OVERSEAS_ARIN_EXCLUDE="."
CODE_OVERSEAS_RIPENCC_EXCLUDE="."
# CERNET: Include these regions from APNIC, NEVER add "CN" here
CODE_CERNET="(JP|AU|NZ)"
# China Telecom: Exclude these regions from APNIC, ALWAYS add "CN" here
# Include US routes from ARIN for CT network
CODE_TEL_APNIC="(CN)"
CODE_TEL_ARIN="(US)"

RIR_STATS="http://ftp.apnic.net/stats/afrinic/delegated-afrinic-extended-latest
http://ftp.apnic.net/stats/apnic/delegated-apnic-extended-latest
http://ftp.apnic.net/stats/arin/delegated-arin-extended-latest
http://ftp.apnic.net/stats/lacnic/delegated-lacnic-extended-latest
http://ftp.apnic.net/stats/ripe-ncc/delegated-ripencc-extended-latest"

RIR_STATS="http://ftp.apnic.net/stats/apnic/delegated-apnic-extended-latest
http://ftp.apnic.net/stats/arin/delegated-arin-extended-latest
http://ftp.apnic.net/stats/ripe-ncc/delegated-ripencc-extended-latest"

WORKDIR=$(pwd)
CMD_BASE=$(dirname $0)

cd $CMD_BASE

DOWN=1
if [ -f db/delegated-apnic-extended-latest ]; then
	STAMP=$(stat -c %Y db/delegated-apnic-extended-latest)
	DATE=$(date +%s)
	EXPECT=$(echo "$STAMP + 86400"|bc)
	if [ $EXPECT -lt $DATE ]; then
		DOWN=1
	else
		echo "Using cached stats information"
		DOWN=0
	fi
fi

if [ $DOWN -eq 1 ]; then
	echo "Downloading..."
	rm -rf db && mkdir -p db && cd db
	#wget -4q $RIR_STATS
	wget -q $RIR_STATS
	echo "Downloaded stats information"
else
	cd db || exit 1
fi


#cat delegated-*-extended-latest > delegated-combined

TEMP_OVERSEAS=$(mktemp)
grep -h asn delegated-apnic-extended-latest | egrep "(assigned|allocated)" | \
	cut -d"|" -f2,4,5 | egrep $CODE_OVERSEAS_APNIC_EXCLUDE|cut -d"|" -f2,3 > $TEMP_OVERSEAS
grep -h asn delegated-arin-extended-latest | egrep "(assigned|allocated)" | \
	cut -d"|" -f2,4,5 | egrep $CODE_OVERSEAS_ARIN_EXCLUDE|cut -d"|" -f2,3 >> $TEMP_OVERSEAS
#grep -h asn delegated-ripencc-extended-latest | egrep "(assigned|allocated)" | \
#	cut -d"|" -f2,4,5 | egrep $CODE_OVERSEAS_RIPENCC_EXCLUDE|cut -d"|" -f2,3 >> $TEMP_OVERSEAS

TEMP_CERNET=$(mktemp)
grep -h asn delegated-apnic-extended-latest | egrep "(assigned|allocated)" | \
	cut -d"|" -f2,4,5 | egrep $CODE_CERNET|cut -d"|" -f2,3 > $TEMP_CERNET

TEMP_TEL=$(mktemp)
grep -h asn delegated-apnic-extended-latest | egrep "(assigned|allocated)" | \
	cut -d"|" -f2,4,5 | egrep -v CN | egrep -v $CODE_TEL_APNIC |cut -d"|" -f2,3 > $TEMP_TEL
grep -h asn delegated-arin-extended-latest | egrep "(assigned|allocated)" | \
	cut -d"|" -f2,4,5 | egrep $CODE_TEL_ARIN |cut -d"|" -f2,3 >> $TEMP_TEL

TEMP_TEL_OVERSEAS=$(mktemp)
echo > $TEMP_TEL_OVERSEAS

TEMP_CMCC=$(mktemp)
echo > $TEMP_CMCC

cd $WORKDIR && cd $CMD_BASE
mkdir -p /etc/bird

python3 full_asns.py overseas_asns_inverted $TEMP_OVERSEAS conf.d/overseas_exclude conf.d/overseas > /etc/bird/bird.d/filters/overseas_asns_inverted.conf && echo "Generated overseas_asns_inverted" &
python3 full_asns.py cernet_asns $TEMP_CERNET conf.d/cernet conf.d/cernet_exclude > /etc/bird/bird.d/filters/cernet_asns.conf && echo "Generated cernet_asns" &
python3 full_asns.py tel_asns $TEMP_TEL conf.d/tel conf.d/tel_exclude > /etc/bird/bird.d/filters/tel_asns.conf && echo "Generated tel_asns" &
python3 full_asns.py tel_overseas_asns $TEMP_TEL_OVERSEAS conf.d/tel_overseas conf.d/tel_exclude> /etc/bird/bird.d/filters/tel_overseas_asns.conf && echo "Generated tel_overseas_asns" &
python3 full_asns.py cmcc_asns $TEMP_CMCC conf.d/cmcc conf.d/cmcc_exclude > /etc/bird/bird.d/filters/cmcc_asns.conf && echo "Generated cmcc_asns" &

wait

rm -f $TEMP_OVERSEAS $TEMP_CERNET $TEMP_TEL $TEMP_TEL_OVERSEAS $TEMP_CMCC
#echo $TEMP_OVERSEAS $TEMP_CERNET $TEMP_TEL $TEMP_TEL_OVERSEAS $TEMP_CMCC
birdc configure
