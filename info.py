#!/usr/bin/env python3
#
# This file is part of asafw.
# Copyright (c) 2017, Aaron Adams <aaron.adams(at)nccgroup(dot)trust>
# Copyright (c) 2017, Cedric Halbronn <cedric.halbronn(at)nccgroup(dot)trust>
#
# Add firmware mitigations info to json database
# or display mitigations info on a given firmware
#
# Note that the output is valid markdown so it can be updated
# in the asafw/README.md

import argparse
import json
import os
import sys
import pprint
import re

from helper import *

def logmsg(s, end=None):
    if type(s) == str:
        if end != None:
            print("[info] " + s, end=end)
        else:
            print("[info] " + s)
    else:
        print(s)

def mitigations_table_header():
    print("| ID  | Version   |Arch|ASLR| NX |PIE|Can|RELRO|Sym|Strip|    Linux | Glibc | Heap allocator | Firmware                  |")
    print("|-----|-----------|----|----|----|---|---|-----|---|-----|----------|-------|----------------|---------------------------")

def migitations_table_footer():
    print("| ID  | Version   |Arch|ASLR| NX |PIE|Can|RELRO|Sym|Strip|    Linux | Glibc | Heap allocator | Firmware                  |")
    print("| Can = Canary              |||||||||||||                                                                                |")
    print("| Sym = Exported symbols    |||||||||||||                                                                                |")

# print info/mitigations for ASA firewalls in a markdown-formated table
def print_mitigations(results):
    if results == None:
        logmsg("[!] Need actual results to print. Got none")
        return
    mitigations_table_header()
    idx = 0

    for t in results:
        # assume an entry we want to print has at least "stripped" otherwise we skip it
        # XXX - print it so we remember to add its mitigations in the db
        #if "stripped" not in t:
        #    continue
        line = "|"
        line += " %.03d" % (idx) + ' |'
        line += "% 10s" % t['version'] + ' |'
        try:
            arch = t["arch"]
        except KeyError:
            arch = "?"
        try:
            aslr = "Y" if t["ASLR"] else "N"
        except KeyError:
            aslr = "?"
        try:
            nx = "Y" if t["NX"] else "N"
        except KeyError:
            nx = "?"
        try:
            pie = "Y" if t["PIE"] else "N"
        except KeyError:
            pie = "?"
        try:
            canary = "Y" if t["Canary"] else "N"
        except KeyError:
            canary = "?"
        try:
            relro = "Y" if t["RELRO"] else "N"
        except KeyError:
            relro = "?"
        try:
            symb = "Y" if t["exported_symbols"] else "N"
        except KeyError:
            symb = "?"
        try:
            stripped = "Y" if t["stripped"] else "N"
        except KeyError:
            stripped = "?"
        try:
            glibc_version = t["glibc_version"]
        except KeyError:
            glibc_version = "?"
        try:
            match = re.search(r'Linux version ([0-9.]*)', t["uname"])
            uname = match.group(1)
        except KeyError:
            uname = "?"
        try:
            heap_alloc = t["heap_alloc"]
        except KeyError:
            heap_alloc = "?"
        line += " % 2s" % arch + ' |'
        line += " % 2s" % aslr + ' |'
        line += " % 2s" % nx + ' |'
        line += " % 1s" % pie + ' |'
        line += " % 1s" % canary + ' |'
        line += " % 3s" % relro + ' |'
        line += " % 1s" % symb + ' |'
        line += " % 2s" % stripped + '  |'
        line += " % 8s" % uname + ' |'
        line += " % 5s" % glibc_version + ' |'
        line += " % 14s" % heap_alloc + ' |'
        line += "% 26s" % t['fw'] + ' |'
        print(line)
        idx += 1
    migitations_table_footer()

# List info/mitigations in a table or directly the JSON (verbose=True)
def list_mitigations(dbname, bin_name, verbose=True):
    results = None
    logmsg("Using dbname %s" % dbname)
    if os.path.isfile(dbname):
        with open(dbname, "r") as tmp:
            results = json.loads(tmp.read())
    if verbose:
        if bin_name == None:
            print(json.dumps(results, indent=4))
        else:
            for r in results:
                if r["fw"] == bin_name:
                    print(json.dumps(r, indent=4))
                    break
    else:
        print_mitigations(results)

# Parse some info passed from info.sh so we can save them in a database
def parse_info2(new_r, info):
    if "32-bit" in info:
        new_r["arch"] = 32
    elif "64-bit" in info:
        new_r["arch"] = 64
    else:
        logmsg("ERROR: arch not found")
    if "No RELRO" in info:
        new_r["RELRO"] = False
    # full relro requires you to use non-lazy binding so at load time 
    # you resolve every symbol in the GOT, then relocate the GOT to 
    # read-only so that you can never overwrite it
    # partial relro means that you are still using lazy binding for 
    # a bunch of GOT entries, but there is a subset that will be 
    # non-lazy bound (i forget how it determines) which will be made ro
    # but the rest of the GOT will be rw for the remainder of execution
    # so in general you could think of it as GOT still not being detected in general
    # unless you happen to _need_ one of the GOT entries that was actually relro
    elif "Partial RELRO" in info:
        # XXX - could be improved but we don't care for now
        new_r["RELRO"] = False
    else:
        logmsg("ERROR: RELRO not found")
    if "No canary found" in info:
        new_r["Canary"] = False
    else:
        logmsg("ERROR: Canary not found")
    if "NX disabled" in info:
        new_r["NX"] = False
    elif "NX enabled" in info:
        new_r["NX"] = True
    else:
        logmsg("ERROR: NX not found")
    if "No PIE" in info:
        new_r["PIE"] = False
    elif "PIE enabled" in info:
        new_r["PIE"] = True
    else:
        logmsg("ERROR: PIE not found")
    if "Not Stripped" in info:
        new_r["stripped"] = False
    elif "Stripped" in info:
        new_r["stripped"] = True
    else:
        logmsg("ERROR: Stripped not found")
    if "ASLR Disabled" in info:
        new_r["ASLR"] = False
    elif "ASLR Enabled" in info:
        new_r["ASLR"] = True
    else:
        logmsg("ERROR: ASLR not found")
    if "No symbol table" in info:
        new_r["exported_symbols"] = False
    elif "Contains symbol table" in info:
        new_r["exported_symbols"] = True
    else:
        logmsg("ERROR: symbols not found")
    match = re.search(r'libc-(.*)\.so', info)
    if not match:
        match = re.search(r'GNU C Library stable release version ([\w.]*)', info)
    if match:
        new_r["glibc_version"] = match.group(1)
    else:
        logmsg("ERROR: glibc not found")
    # We test the glibc version first because we know that dlmalloc 2.8.3 in lina is used for all versions using glibc 2.9
    # and we know dlmalloc 2.8.3 in lina is NOT the default heap allocator when glibc 2.18 is used
    if "glibc_version" in new_r.keys() and new_r["glibc_version"] == "2.9":
        new_r["heap_alloc"] = "dlmalloc 2.8.3"
    elif "glibc_version" in new_r.keys() and new_r["glibc_version"] == "2.18":
        new_r["heap_alloc"] = "ptmalloc 2.x"
    else:
        match = re.search(r'dlmalloc ([\w.]*)', info)
        if match:
            new_r["heap_alloc"] = "dlmalloc %s" % (match.group(1))
        else:
            logmsg("ERROR: heap allocator not found")

    # try to guess the imagebase based on experience
    if "arch" in new_r.keys() and "ASLR" in new_r.keys():
        if new_r["arch"] == 32:
            new_r["imagebase"] = 0x8048000
        elif new_r["arch"] == 64:
            if new_r["ASLR"] == True:
                # when ASLR is enabled, we assume it has been disabled by us manually
                # and this is the address we get until now
                new_r["imagebase"] = 0x555555554000
            else:
                new_r["imagebase"] = 0x400000

    return new_r

# Add some info we got for an asa*.bin into a database
def update_db(dbname, bin_name, info):
    results = []
    if os.path.isfile(dbname):
        with open(dbname, "rb") as tmp:
            results = json.loads(tmp.read().decode('UTF-8'))
    version = build_version(bin_name)
    new_r = {}
    new_r["fw"] = bin_name
    new_r["version"] = version
    if "RELRO" in info:
        new_r = parse_info2(new_r, info)
    elif "Linux version" in info:
        new_r["uname"] = info
    isNew = True
    for r in results:
        if r["fw"] == new_r["fw"]:
            logmsg("Updating old element")
            print(r)
            for k,v in new_r.items():
                r[k] = v
            print(r)
            isNew = False
            break
    if isNew:
        logmsg("Adding new element:")
        print(new_r)
        results.append(new_r)
    results = sorted(results, key=lambda k: k["fw"])
    open(dbname, "wb").write(bytes(json.dumps(results, indent=4), encoding="UTF-8"))

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('-l', dest='list_mitigations', action='store_true', help='List migitations in all firmware versions')
    parser.add_argument('-u', dest='update_info', default=None, help="Output from info.sh to update db")
    parser.add_argument('-i', dest='bin_name', help='firmware bin name to update or display')
    parser.add_argument('-v', dest='verbose', help='display more info')
    parser.add_argument('-d', dest='dbname', default=None, help='json database name to read/list info from')
    args = parser.parse_args()

    if args.dbname == None:
        logmsg("You need to specify a JSON database filename with -d")
        sys.exit(1)

    if args.list_mitigations:
        list_mitigations(args.dbname, args.bin_name, args.verbose)
        sys.exit()

    if args.update_info:
        update_db(args.dbname, args.bin_name, args.update_info)
        sys.exit()