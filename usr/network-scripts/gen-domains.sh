#!/bin/sh

#DNS_ISP=106.187.35.20
DNS_ISP=74.207.242.5
#DNS_GOOGLE=8.8.8.8
LIST_COMM=/etc/dnsmasq.d/domains.gfwlist
#LIST_GOOGLE=/etc/dnsmasq.d/domains.google
#KEYWORD=google

wget -4qO- http://autoproxy-gfwlist.googlecode.com/svn/trunk/gfwlist.txt | base64 -d | sed '/^!/d;/\*/d;/@/d;/%/d;/^$/d;/^\[/d;s/^|//;s/^|//;s/^\.//;s/^http\:\/\///;s/^https\:\/\///' | cut -d'/' -f1 | grep '\.' | grep -v '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' | sort | uniq | sed "s/^/server\=\//;s/$/\/${DNS_ISP}/" > $LIST_COMM

#grep $KEYWORD $LIST_COMM | sed "s/${DNS_ISP}/${DNS_GOOGLE}/g" > $LIST_GOOGLE
#printf "server=/google.com/${DNS_GOOGLE}" >> $LIST_GOOGLE
#sed -i "/${KEYWORD}/d" $LIST_COMM

printf "server=/google.com/${DNS_ISP}\n" >> $LIST_COMM
printf "server=/amazon.com/${DNS_ISP}\n" >> $LIST_COMM

service dnsmasq reload
