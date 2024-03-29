#!/usr/bin/env python3
# Forked from https://github.com/fivesheep/chnroutes/blob/master/chnroutes.py

import re
import urllib.request, urllib.error, urllib.parse
import sys
import argparse
import math
import textwrap

def generate_iplist(source,metric):
    results = fetch_ip_data(source)
    rfile=open('iplist.txt','w')
    print("Writing iplist.txt")
    for ip,mask,mask2 in results:
        route_item="%s/%s\n"%(ip,mask2)
        rfile.write(route_item)
    rfile.close()


def generate_ovpn(source,metric):
    results = fetch_ip_data(source)  
    rfile=open('routes.txt','w')
    print("Writing routes.txt")
    for ip,mask,_ in results:
        route_item="route %s %s net_gateway %d\n"%(ip,mask,metric)
        rfile.write(route_item)
    rfile.close()
    print("Usage: Append the content of the newly created routes.txt to your openvpn config file," \
          " and also add 'max-routes %d', which takes a line, to the head of the file." % (len(results)+20))


def generate_linux(source,metric):
    results = fetch_ip_data(source)
    upscript_header=textwrap.dedent("""\
    #!/bin/bash
    export PATH="/bin:/sbin:/usr/sbin:/usr/bin"
    
    OLDGW=`ip route show | grep '^default' | sed -e 's/default via \\([^ ]*\\).*/\\1/'`
    
    if [ $OLDGW == '' ]; then
        exit 0
    fi
    
    if [ ! -e /tmp/vpn_oldgw ]; then
        echo $OLDGW > /tmp/vpn_oldgw
    fi
    
    """)
    
    downscript_header=textwrap.dedent("""\
    #!/bin/bash
    export PATH="/bin:/sbin:/usr/sbin:/usr/bin"
    
    OLDGW=`cat /tmp/vpn_oldgw`
    
    """)
    
    upfile=open('ip-pre-up','w')
    downfile=open('ip-down','w')
    
    upfile.write(upscript_header)
    upfile.write('\n')
    downfile.write(downscript_header)
    downfile.write('\n')
    
    for ip,mask,_ in results:
        upfile.write('route add -net %s netmask %s gw $OLDGW\n'%(ip,mask))
        downfile.write('route del -net %s netmask %s\n'%(ip,mask))

    downfile.write('rm /tmp/vpn_oldgw\n')


    print("For pptp only, please copy the file ip-pre-up to the folder/etc/ppp," \
          "and copy the file ip-down to the folder /etc/ppp/ip-down.d.")

def generate_mac(source,metric):
    results=fetch_ip_data(source)
    
    upscript_header=textwrap.dedent("""\
    #!/bin/sh
    export PATH="/bin:/sbin:/usr/sbin:/usr/bin"
    
    OLDGW=`netstat -nr | grep '^default' | grep -v 'ppp' | sed 's/default *\\([0-9\.]*\\) .*/\\1/' | awk '{if($1){print $1}}'`

    if [ ! -e /tmp/pptp_oldgw ]; then
        echo "${OLDGW}" > /tmp/pptp_oldgw
    fi
    
    dscacheutil -flushcache

    route add 10.0.0.0/8 "${OLDGW}"
    route add 172.16.0.0/12 "${OLDGW}"
    route add 192.168.0.0/16 "${OLDGW}"
    """)
    
    downscript_header=textwrap.dedent("""\
    #!/bin/sh
    export PATH="/bin:/sbin:/usr/sbin:/usr/bin"
    
    if [ ! -e /tmp/pptp_oldgw ]; then
            exit 0
    fi
    
    ODLGW=`cat /tmp/pptp_oldgw`

    route delete 10.0.0.0/8 "${OLDGW}"
    route delete 172.16.0.0/12 "${OLDGW}"
    route delete 192.168.0.0/16 "${OLDGW}"
    """)
    
    upfile=open('ip-up','w')
    downfile=open('ip-down','w')
    
    upfile.write(upscript_header)
    upfile.write('\n')
    downfile.write(downscript_header)
    downfile.write('\n')
    
    for ip,_,mask in results:
        upfile.write('route add %s/%s "${OLDGW}"\n'%(ip,mask))
        downfile.write('route delete %s/%s ${OLDGW}\n'%(ip,mask))
    
    downfile.write('\n\nrm /tmp/pptp_oldgw\n')
    upfile.close()
    downfile.close()
    
    print("For pptp on mac only, please copy ip-up and ip-down to the /etc/ppp folder," \
          "don't forget to make them executable with the chmod command.")

def generate_win(source,metric):
    results = fetch_ip_data(source)  

    upscript_header=textwrap.dedent("""@echo off
    for /F "tokens=3" %%* in ('route print ^| findstr "\\<0.0.0.0\\>"') do set "gw=%%*"
    
    """)
    
    upfile=open('vpnup.bat','w')
    downfile=open('vpndown.bat','w')
    
    upfile.write(upscript_header)
    upfile.write('\n')
    upfile.write('ipconfig /flushdns\n\n')
    
    downfile.write("@echo off")
    downfile.write('\n')
    
    for ip,mask,_ in results:
        upfile.write('route add %s mask %s %s metric %d\n'%(ip,mask,"%gw%",metric))
        downfile.write('route delete %s\n'%(ip))
    
    upfile.close()
    downfile.close()
    
#    up_vbs_wrapper=open('vpnup.vbs','w')
#    up_vbs_wrapper.write('Set objShell = CreateObject("Wscript.shell")\ncall objShell.Run("vpnup.bat",0,FALSE)')
#    up_vbs_wrapper.close()
#    down_vbs_wrapper=open('vpndown.vbs','w')
#    down_vbs_wrapper.write('Set objShell = CreateObject("Wscript.shell")\ncall objShell.Run("vpndown.bat",0,FALSE)')
#    down_vbs_wrapper.close()
    
    print("For pptp on windows only, run vpnup.bat before dialing to vpn," \
          "and run vpndown.bat after disconnected from the vpn.")

def generate_android(source,metric):
    results = fetch_ip_data(source)
    
    upscript_header=textwrap.dedent("""\
    #!/bin/sh
    alias nestat='/system/xbin/busybox netstat'
    alias grep='/system/xbin/busybox grep'
    alias awk='/system/xbin/busybox awk'
    alias route='/system/xbin/busybox route'
    
    OLDGW=`netstat -rn | grep ^0\.0\.0\.0 | awk '{print $2}'`
    
    """)
    
    downscript_header=textwrap.dedent("""\
    #!/bin/sh
    alias route='/system/xbin/busybox route'
    
    """)
    
    upfile=open('vpnup.sh','w')
    downfile=open('vpndown.sh','w')
    
    upfile.write(upscript_header)
    upfile.write('\n')
    downfile.write(downscript_header)
    downfile.write('\n')
    
    for ip,mask,_ in results:
        upfile.write('route add -net %s netmask %s gw $OLDGW\n'%(ip,mask))
        downfile.write('route del -net %s netmask %s\n'%(ip,mask))
    
    upfile.close()
    downfile.close()
    
    print("Old school way to call up/down script from openvpn client. " \
          "use the regular openvpn 2.1 method to add routes if it's possible")


def fetch_ip_data(source):
    #fetch data from apnic
    print("Fetching data, please wait...")
    url_list={ 'arin':r'http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest',
               'apnic':r'http://ftp.apnic.net/stats/apnic/delegated-apnic-latest',
               'lacnic':r'ftp://ftp.lacnic.net/pub/stats/lacnic/delegated-lacnic-extended-latest',
               'ripecc':r'ftp://ftp.ripe.net/pub/stats/ripencc/delegated-ripencc-extended-latest',
               'afrinic':r'http://ftp.afrinic.net/pub/stats/afrinic/delegated-afrinic-extended-latest'}

    #url=r'http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest'
    url=url_list[source]
    data=urllib.request.urlopen(url).read().decode()
    
    cnregex=re.compile(r'[a-zA-Z]{4,7}\|cn\|ipv4\|[0-9\.]+\|[0-9]+\|[0-9]+\|a.*',re.IGNORECASE)
    cndata=cnregex.findall(data)
    
    results=[]

    for item in cndata:
        unit_items=item.split('|')
        starting_ip=unit_items[3]
        num_ip=int(unit_items[4])
        
        imask=0xffffffff^(num_ip-1)
        #convert to string
        imask=hex(imask)[2:]
        mask=[0]*4
        mask[0]=imask[0:2]
        mask[1]=imask[2:4]
        mask[2]=imask[4:6]
        mask[3]=imask[6:8]
        
        #convert str to int
        mask=[ int(i,16 ) for i in mask]
        mask="%d.%d.%d.%d"%tuple(mask)
        
        #mask in *nix format
        mask2=32-int(math.log(num_ip,2))
        
        results.append((starting_ip,mask,mask2))
         
    return results


if __name__=='__main__':
    parser=argparse.ArgumentParser(description="Generate routing rules for vpn.")
    parser.add_argument('-s','--source',
                        dest='source',
                        default='apnic',
                        nargs='?',
                        help="Data source, it can be arin, apnic, lacnic, ripe,"
                        "afrinic. apnic by default.")
    parser.add_argument('-p','--platform',
                        dest='platform',
                        default='iplist',
                        nargs='?',
                        help="Target platforms, it can be iplist, openvpn, mac, linux," 
                        "win, android. iplist by default.")
    parser.add_argument('-m','--metric',
                        dest='metric',
                        default=5,
                        nargs='?',
                        type=int,
                        help="Metric setting for the route rules")
    
    args = parser.parse_args()
    
    if args.platform.lower() == 'iplist':
        generate_iplist(args.source, args.metric)
    elif args.platform.lower() == 'openvpn':
        generate_ovpn(args.source, args.metric)
    elif args.platform.lower() == 'linux':
        generate_linux(args.source, args.metric)
    elif args.platform.lower() == 'mac':
        generate_mac(args.source, args.metric)
    elif args.platform.lower() == 'win':
        generate_win(args.source, args.metric)
    elif args.platform.lower() == 'android':
        generate_android(args.source, args.metric)
    else:
        print("Platform %s is not supported."%args.platform, file=sys.stderr)
        exit(1)
