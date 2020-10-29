#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

LIST=/etc/bind/named.conf.gfwlist
LIST_COMM=/etc/bind/named.conf.gfwlist.tmp
LIST_TMP=/tmp/gfwlist-domains.tmp

DOMAINS_LOCAL=/root/scripts/domains.localadd

cat $DOMAINS_LOCAL | grep -v '#' | while read line; do
	printf "zone \"${line}\" { type forward; forward only; forwarders {127.0.0.1 port 5353;};};\n" >> $LIST_COMM
done

wget -4qO- https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt | base64 -d | sed '/^!/d;/\*/d;/@/d;/%/d;/^$/d;/^\[/d;s/^|//;s/^|//;s/^\.//;s/^http\:\/\///;s/^https\:\/\///' | cut -d'/' -f1 | grep '\.' | grep -v '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' | sort | uniq > $LIST_TMP
cat $LIST_TMP | sed "s/^/zone \"/;s/$/\" { type forward; forward only; forwarders {127.0.0.1 port 5353;};};/" >> $LIST_COMM

sort $LIST_COMM | uniq > $LIST

rm -f $LIST_COMM $LIST_TMP

#service smartdns restart
rndc reload
