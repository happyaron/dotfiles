#!/bin/sh

#DNS_ISP=210.188.224.11
#DNS_ISP=210.188.224.12
#DNS_ISP=210.188.224.13
#DNS_ISP=192.168.6.76
#DNS_ISP=203.95.24.197
DNS_ISP=8.8.4.4
DNS_GOOGLE=8.8.8.8
LIST_COMM=/etc/dnsmasq.d/domains.gfwlist
LIST_LOCAL=/root/scripts/domains.localadd
LIST_TMP=/tmp/dnsmasq.tmp
#LIST_GOOGLE=/etc/dnsmasq.d/domains.google
#KEYWORD=google

#wget -4qO- http://autoproxy-gfwlist.googlecode.com/svn/trunk/gfwlist.txt | base64 -d | sed '/^!/d;/\*/d;/@/d;/%/d;/^$/d;/^\[/d;s/^|//;s/^|//;s/^\.//;s/^http\:\/\///;s/^https\:\/\///' | cut -d'/' -f1 | grep '\.' | grep -v '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' | sort | uniq > $LIST_TMP
wget -4qO- https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt | base64 -d | sed '/^!/d;/\*/d;/@/d;/%/d;/^$/d;/^\[/d;s/^|//;s/^|//;s/^\.//;s/^http\:\/\///;s/^https\:\/\///' | cut -d'/' -f1 | grep '\.' | grep -v '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' | sort | uniq > $LIST_TMP

cat $LIST_TMP | sed "s/^/server\=\//;s/$/\/${DNS_ISP}/" > $LIST_COMM
cat $LIST_TMP | sed "s/^/server\=\//;s/$/\/${DNS_GOOGLE}/" >> $LIST_COMM

#grep $KEYWORD $LIST_COMM | sed "s/${DNS_ISP}/${DNS_GOOGLE}/g" > $LIST_GOOGLE
#printf "server=/google.com/${DNS_GOOGLE}" >> $LIST_GOOGLE
#sed -i "/${KEYWORD}/d" $LIST_COMM

cat $LIST_LOCAL | grep -v '#' | while read line; do
	printf "server=/${line}/${DNS_ISP}\n" >> $LIST_COMM
	printf "server=/${line}/${DNS_GOOGLE}\n" >> $LIST_COMM
done

#wget -4qO- http://code.taobao.org/svn/dd-wrt/hosts | sed '1,12d' > /etc/dnsmasq.hosts
#wget -4qO- http://hosts.mwsl.org.cn/hosts | sed '1,9d;s/181.215.102.78/127.0.0.1/g' > /etc/dnsmasq.hosts

service dnsmasq restart
