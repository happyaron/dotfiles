#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

LIST_COMM=/etc/bind/named.conf.domains.tmp
LIST_TMP=/tmp/bind9-domains.tmp

# To provide accurate resolution results
#
LIST_GFW=/etc/bind/named.conf.gfwlist
DOMAINS_LOCAL=/root/scripts/domains.localadd

rm -f $LIST_COMM $LIST_TMP
cat $DOMAINS_LOCAL | grep -v '#' | while read line; do
	printf "zone \"${line}\" { type forward; forward only; forwarders {127.0.0.1 port 5353;};};\n" >> $LIST_COMM
done

wget -4qO- https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt | base64 -d | sed '/^!/d;/\*/d;/@/d;/%/d;/^$/d;/^\[/d;s/^|//;s/^|//;s/^\.//;s/^http\:\/\///;s/^https\:\/\///' | cut -d'/' -f1 | grep '\.' | grep -v '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' | sort | uniq > $LIST_TMP
cat $LIST_TMP | grep -v github | sed "s/^/zone \"/;s/$/\" { type forward; forward only; forwarders {127.0.0.1 port 5353;};};/" >> $LIST_COMM
cat $LIST_TMP | grep github | sed "s/^/zone \"/;s/$/\" { type forward; forward only; forwarders {192.168.6.17;};};/" >> $LIST_COMM

sort $LIST_COMM | uniq > $LIST_GFW
rm -f $LIST_COMM $LIST_TMP

# To provide correct preference to China servers
LIST_GGCN=/etc/bind/named.conf.ggcn

rm -f $LIST_COMM $LIST_TMP
wget -4qO- https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/google.china.conf | cut -d'/' -f2 > $LIST_TMP
#wget -4qO- https://gitee.com/felixonmars/dnsmasq-china-list/raw/master/google.china.conf | cut -d'/' -f2 > $LIST_TMP

cat $LIST_TMP | sed "s/^/zone \"/;s/$/\" { type forward; forward only; forwarders {119.29.29.29; 182.254.118.118; 223.5.5.5; 223.6.6.6; };};/" >> $LIST_COMM

sort $LIST_COMM | uniq > $LIST_GGCN
rm -f $LIST_COMM $LIST_TMP

#service smartdns restart
rndc reload
