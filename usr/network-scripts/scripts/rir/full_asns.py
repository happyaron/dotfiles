#!/usr/bin/python3
# Used to generate bird ASN array from filtered RIR delegation format.

from datetime import datetime
from os.path import isdir, isfile, join
from os import walk
import sys

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)

def walkfile(pathname):
    lines = []
    if isfile(pathname):
        with open(pathname, "r") as f:
            lines = f.readlines()
    elif isdir(pathname):
        for root, dirs, files in walk(pathname, followlinks=True):
            eprint("walking " + pathname)
            for name in files:
                if name.endswith(".conf"):
                    eprint("concating "+join(root,name))
                    with open(join(root,name), "r") as f:
                        lines += f.readlines()
    else:
        raise ValueError
    return lines

if len(sys.argv) < 3:
    raise SyntaxError("Usage: $ full_asns.py [array_name] [file_input] [file_append] [file_exclude]")

array_name = sys.argv[1]
lines = walkfile(sys.argv[2])

lines = [x.strip("\n").split("|") for x in lines]

members = set()

if len(sys.argv) > 3:
    lines_append = walkfile(sys.argv[3])
    for x in lines_append:
        if not x.startswith('#'):
            members.add(int(x.strip("\n")))

for x in lines:
    # Protect against empty string or malformed text
    if len(x) > 1:
        for y in range(0, int(x[1])):
            members.add(int(x[0])+y)

if len(sys.argv) > 4:
    lines_exclude = walkfile(sys.argv[4])
    for x in lines_exclude:
        if not x.startswith('#'):
            #sys.stderr.write("DEBUG: discarding " + x)
            members.discard(int(x.strip("\n")))

print("# Automatically generated at " + str(datetime.now()) + " CST")
print("define " + array_name + " = [")
mem = sorted(members)
for x in mem:
    if x == mem[-1]:
        print("\t" + str(x))
    else:
        print("\t" + str(x) + ",")
print("];")
