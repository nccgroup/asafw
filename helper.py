#!/usr/bin/python3
#
# This file is part of asafw.
# Copyright (c) 2017, Aaron Adams <aaron.adams(at)nccgroup(dot)trust>
# Copyright (c) 2017, Cedric Halbronn <cedric.halbronn(at)nccgroup(dot)trust>
#
# NOTE: This file should be kept in sync with helper.py from asadbg
#
# This contains helpers for other parts. Note that some of them are common
# to several projects: asadbg, asafw, libdlmalloc, libptmalloc, libmempool, etc.

import os, re, json, pickle, sys

# An example of what this function is doing: 
#
# If you had two IDBs associated with asa924-smp-k8.bin, but one was from
# hardware and one was from a qcow (and thus asav), then you could have folders
# like this:
#
# ~/asa924-smp-k8.bin/asa924-smp-k8.idb
# ~/asav924-smp-k8.bin/asa924-smp-k8.idb
#
# This way the direct parent folder name itself is used as the identifier. This
# identifier is path is also used to look up target info inside of the
# mapping_config dictionary in ext_gdb/sync.py. The general problem with this
# is if the filesystem hosting the idb is not the same as the one hosting the
# files, as the directory layout might be totally different.
def build_bin_name(s):
    if "asav" in s:
        match = re.search(r'asav([^\\/.]+)\.qcow2', s)
        if not match:
            print_error("Could not find the asavXXX.qcow2 in string: %s" % s)
            return ''
        return "asav%s.qcow2" % match.group(1)
    elif "SPA" in s:
        match = re.search(r'asa([^\\/.]+)\.SPA', s)
        if not match:
            print_error("Could not find the asaXXX.SPA in string: %s" % s)
            return ''
        return "asa%s.SPA" % match.group(1)
    else:
        match = re.search(r'asa([^\\/.]+)\.bin', s)
        if not match:
            print_error("Could not find the asaXXX.bin in string: %s" % s)
            return ''
        return "asa%s.bin" % match.group(1)

# parse the version from the firmware name
# examples: asa811-smp-k8.bin, asa825-k8.bin, asa805-31-k8.bin
def build_version(dirname):

    version = ''
    if "asav" in dirname:
        match = re.search(r'asav([^\\/.]+)\.qcow2', dirname)
        if not match:
            print_error("Could not find the asavXXX.qcow2 in string: %s" % dirname)
            return ''
    elif "SPA" in dirname:
        match = re.search(r'asa([^\\/.]+)\.SPA', dirname)
        if not match:
            print_error("Could not find the asaXXX.SPA in string: %s" % dirname)
            return ''
    else:
        match = re.search(r'asa([^\\/.]+)\.bin', dirname)
        if not match:
            print_error("Could not find the asaXXX.bin in string: %s" % dirname)
            return ''

    verName = match.group(1)
    elts = verName.split("-")
    first = True
    try:
        for e in elts:
            if first:
                for c in e:
                    if not first:
                        version += '.'
                    version += '%c' % c
                    first = False
            else:
                version += '.%d' % int(e)
    # assume we get one at some point (eg: "k8") - it means we are done for now
    except ValueError:
        pass

    return version

# check if a firmware is new based on the firmware name
def is_new(targets, new):
    for t in targets:
        if t["fw"] == new["fw"]:
            return False
    return True

def load_targets(targetdb):
    # XXX log.logmsg() does not work 
    # as it prints <helper.logger instance at 0x06B77EB8>
    # so we use print() instead :|
    print("[helper] Reading from %s" % targetdb)
    if targetdb.endswith(".pickle"):
        usePickle = True
    elif targetdb.endswith(".json"):
        usePickle = False
    else:
        print("[helper] Can't decide if pickle to use based on extension")
        sys.exit()
    if os.path.isfile(targetdb):
        if usePickle:
            # old format
            try:
                targets = pickle.load(open(targetdb, "rb"))
            # ValueError: insecure string pickle
            # long story short, while using git on both Linux/Windows, do NOT ask git to replace
            # CRLF with its own between the local version and the remote server. Indeed, the pickle will
            # be modified and it will be treated in a text file instead of binary :/
            except ValueError:
                # hax so we can use it if it fails to open the db
                targets = pickle.load(open(targetdb, "r"))
        else:
            # even when using filelock, it looks like sometimes we read bad JSON
            # so we try several times :|
            max_attempts = 5
            attempts = 0
            while attempts < max_attempts:
                try:
                    # don't use 'rb' because json expects a str
                    with open(targetdb, "r") as tmp:
                        targets = json.loads(tmp.read())
                except ValueError:
                    print("[helper] Failed to read valid JSON, trying again in 1 sec")
                    time.sleep(1)
                    attempts += 1
                else:
                    break
            if attempts == max_attempts:
                print('[helper] [!] failed to read %s' % targetdb)
                sys.exit() 
    else:
        print('[helper] [!] %s file not found' % targetdb)
        sys.exit() 
    return targets 

def get_target_index(targets, bin_name):
    for i in range(len(targets)):
        if targets[i]["fw"] == bin_name:
            return i
    return None
