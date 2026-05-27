#!/usr/bin/python3
'''
Processing the downloaded html of HE bgp contry page, for example:
    https://bgp.he.net/country/US
Usage:
    script.py input.htm searchstring
'''

from bs4 import BeautifulSoup, SoupStrainer
from bs4.element import Tag
import re
import sys

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)

def help():
    eprint("Usage: "+ sys.argv[0] + " example.htm re_searchstr")
    eprint("  re_searchstr is case insensitive, e.g. \"university|institute\"\n")

if len(sys.argv) < 3:
    help()
    sys.exit(0)
else:
    fname = sys.argv[1]
    searchstr = sys.argv[2]

with open(fname, 'r') as f:
    html = f.read()
    eprint("Read " + fname + " for " + str(len(html)) + " bytes")

#soup = BeautifulSoup(html, 'html.parser')
only_tr_tags = SoupStrainer('tr')
soup = BeautifulSoup(html, 'lxml', parse_only=only_tr_tags)

tags = soup.find_all('tr')[1:-1]
p = re.compile(searchstr, re.IGNORECASE)
cnt = 0

for tr in tags:
    for child in tr.descendants:
        if isinstance(child, Tag) and child.a is not None:
            title = child.a.get('title').split(' - ')[1]
            if p.search(title):
                cnt+=1
                asn = child.a.get('href').lstrip('/AS')
                print('# '+title+'\n'+asn)

eprint('Total '+str(cnt)+' matches')
