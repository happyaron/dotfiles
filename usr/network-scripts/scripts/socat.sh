#!/bin/sh
socat TCP4-LISTEN:8022,reuseaddr,fork,su=nobody TCP4:192.168.252.60:22 &
socat TCP4-LISTEN:8080,reuseaddr,fork,su=nobody TCP4:192.168.252.60:80 &
socat TCP4-LISTEN:8443,reuseaddr,fork,su=nobody TCP4:192.168.252.60:443 &
