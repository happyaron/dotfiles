#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

LIST_COMM=/etc/bind/named.conf.domains.tmp
LIST_TMP=/tmp/bind9-domains.tmp

# To provide accurate resolution results
#
LIST_GFW=/etc/bind/named.conf.gfwlist
DOMAINS_LOCAL=/root/scripts/domains.localadd
DOMAINS_LOCAL_US=/root/scripts/domains.localadd_us

rm -f $LIST_COMM $LIST_TMP
cat $DOMAINS_LOCAL | grep -v '#' | while read line; do
	printf "zone \"${line}\" { type forward; forward only; forwarders {1.1.1.1; 8.8.8.8; 8.8.4.4; 1.0.0.1;};};\n" >> $LIST_COMM
done

cat $DOMAINS_LOCAL_US | grep -v '#' | while read line; do
	printf "zone \"${line}\" { type forward; forward only; forwarders {192.0.2.3;};};\n" >> $LIST_COMM
done

wget -4qO- https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt | base64 -d | sed '/^!/d;/\*/d;/@/d;/%/d;/^$/d;/^\[/d;s/^|//;s/^|//;s/^\.//;s/^http\:\/\///;s/^https\:\/\///' | cut -d'/' -f1 | grep '\.' | grep -v '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' | sort | uniq > $LIST_TMP
cat $LIST_TMP | grep -v github | sed "s/^/zone \"/;s/$/\" { type forward; forward only; forwarders {1.1.1.1; 8.8.8.8; 8.8.4.4; 1.0.0.1;};};/" >> $LIST_COMM
# See DOMAINS_LOCAL_US before changes
#cat $LIST_TMP | grep github | sed "s/^/zone \"/;s/$/\" { type forward; forward only; forwarders {192.0.2.3;};};/" >> $LIST_COMM

sort $LIST_COMM | sed '/openai.com/d;/chatgpt.com/d;/oaistatic.com/d;/oaiusercontent.com/d;/gemini.google.com/d;/x.ai/d;/grok.com/d;/linkedin.com/d;/docker.com/d;/gitlab.com/d;/docker.io/d;' | uniq > $LIST_GFW
rm -f $LIST_COMM $LIST_TMP

# To provide correct preference to China servers
LIST_GGCN=/etc/bind/named.conf.ggcn

rm -f $LIST_COMM $LIST_TMP
wget -4qO- https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/google.china.conf | cut -d'/' -f2 | sed '/^$/d;/^#/d' > $LIST_TMP
#wget -4qO- https://gitee.com/felixonmars/dnsmasq-china-list/raw/master/google.china.conf | cut -d'/' -f2 > $LIST_TMP

cat $LIST_TMP | sed "s/^/zone \"/;s/$/\" { type forward; forward only; forwarders {119.29.29.29; 182.254.118.118; 223.5.5.5; 223.6.6.6; };};/" >> $LIST_COMM

sort $LIST_COMM | uniq > $LIST_GGCN
rm -f $LIST_COMM $LIST_TMP

#service smartdns restart
rndc reload
