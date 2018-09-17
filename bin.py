#!/usr/bin/env python3
#
# This file is part of asafw.
# Copyright (c) 2017, Aaron Adams <aaron.adams(at)nccgroup(dot)trust>
# Copyright (c) 2017, Cedric Halbronn <cedric.halbronn(at)nccgroup(dot)trust>
#
# Main script to root a given asa*.bin firmware or unpack/repack it.
# It is used by "unpack_repack_bin.sh".
#
# Execute this script as root so the repacked version has the right uid/gid.
#
# Some useful related links
# http://7200emu.hacki.at/viewtopic.php?t=9074
# https://gns3.com/discussions/uncompressing-asa-bin-file
# https://gist.githubusercontent.com/anonymous/c3225054e6681a39be16/raw/3377f4c2283f1983bb1642c9debdbf8f68d3f67d/repack.v4.1.sh

import sys
import struct
import binascii
import argparse
import re, os

def logmsg(s, end=None):
    if type(s) == str:
        if end != None:
            print("[bin] " + s, end=end)
        else:
            print("[bin] " + s)
    else:
        print(s)

# Reinject a filesystem into a asa*.bin
def repack(firmwarefile, gzipfile, out_bin_name=None):
    logmsg("Repacking...")
    bin_data = open(firmwarefile, 'rb').read()
    gz_data = open(gzipfile, 'rb').read()
    if out_bin_name == None:
        fileinfo = os.path.splitext(firmwarefile)
        out_bin_name = fileinfo[0] + '-repacked' + fileinfo[1]

    # extract previous gz size from firmware
    # string is not far from the end so quicker to look for it from the end
    idx = bin_data.rfind(b"quiet loglevel=0 auto")
    if idx == -1:
        logmsg("Warning: Could not find kernel command line, trying alternative method")
        # e.g. for 8.0.3
        idx = bin_data.rfind(b"auto quiet loglevel=0")
        if idx == -1:
            logmsg("Error: Could not find kernel command line")
            sys.exit(1)
    # XXX - there must be a proper way for finding the gz size
    idx_gz_size = idx-4
    old_gz_size = struct.unpack("<I", bin_data[idx_gz_size:idx_gz_size+4])[0]
    if old_gz_size < len(gz_data):
        logmsg("Error: Cannot patch the firmware because replacement .gz is bigger than the one in .bin (%s > %s)" % (len(gz_data), old_gz_size))
        sys.exit(1)
    logmsg("Old gzip size: 0x%x bytes" % (old_gz_size))
    logmsg("New gzip size: 0x%x bytes" % (len(gz_data)))

    # find gz data in firmware
    # XXX - there must be a proper way for finding the gz beginning
    idx = bin_data.find(b"rootfs.img")
    if idx == -1:
        logmsg("Warning: Could not find rootfs.img string, trying alternative method")
        i = 0
        while True:
            idx = bin_data.find(b"\x1f\x8b\x08", i)
            if idx == -1:
                logmsg("Error: Could not find rootfs.img string or gzip start")
                sys.exit(1)
            logmsg("Found gzip magic at: 0x%x" % idx)
            if idx & 0xfffffff0 == idx:
                logmsg("Assuming good magic")
                break
            i = idx + 3

    idx_gz = idx & 0xfffffff0
    #logmsg("idx_gz=0x%x" % idx_gz)

    out_bin_data = bin_data[:idx_gz] + gz_data + bin_data[idx_gz+len(gz_data):idx_gz_size] + \
                   struct.pack("<I", len(gz_data)) + bin_data[idx_gz_size+4:]
    if len(out_bin_data) != len(bin_data):
        logmsg("Error: Size are different. It should not happen")
        sys.exit(1)
    logmsg("repack: Writing %s (%d bytes)..." % (out_bin_name, len(out_bin_data)))
    open(out_bin_name, 'wb').write(out_bin_data)

# Extract a kernel and filesystem from an asa*.bin
def unpack(firmwarefile):
    logmsg("Unpacking...")
    bin_data = open(firmwarefile, 'rb').read()
    out_gz_name = os.path.splitext(firmwarefile)[0] + '-initrd-original.gz'
    out_vmlinuz_name = os.path.splitext(firmwarefile)[0] + '-vmlinuz'

    # extract previous gz size from firmware
    # string is not far from the end so quicker to look for it from the end
    idx = bin_data.rfind(b"quiet loglevel=0 auto")
    if idx == -1:
        logmsg("Warning: Could not find kernel command line, trying alternative method")
        # e.g. for 8.0.3
        idx = bin_data.rfind(b"auto quiet loglevel=0")
        if idx == -1:
            logmsg("Error: Could not find kernel command line")
            sys.exit(1)
    # XXX - there must be a proper way for finding the gz size
    idx_gz_size = idx-4
    old_gz_size = struct.unpack("<I", bin_data[idx_gz_size:idx_gz_size+4])[0]
    logmsg("Old gzip size: 0x%x bytes" % (old_gz_size))

    # XXX - there must be a proper way for finding the vmlinuz size
    idx_vmlinuz_size = idx_gz_size-4
    old_vmlinuz_size = struct.unpack("<I", bin_data[idx_vmlinuz_size:idx_vmlinuz_size+4])[0]
    #logmsg("Old vmlinuz size: 0x%x bytes" % (old_vmlinuz_size))

    # find gz data in firmware
    # XXX - there must be a proper way for finding the gz beginning
    idx = bin_data.find(b"rootfs.img")
    if idx == -1:
        logmsg("Warning: Could not find rootfs.img string, trying alternative method")
        i = 0
        while True:
            idx = bin_data.find(b"\x1f\x8b\x08", i)
            if idx == -1:
                logmsg("Error: Could not find rootfs.img string or gzip start")
                sys.exit(1)
            logmsg("Found gzip magic at: 0x%x" % idx)
            if idx & 0xfffffff0 == idx:
                logmsg("Assuming good magic")
                break
            i = idx + 3
    
    idx_gz = idx & 0xfffffff0
    #logmsg("idx_gz=0x%x" % idx_gz)
    logmsg("Writing %s (%d bytes)..." % (out_gz_name, old_gz_size))
    open(out_gz_name, 'wb').write(bin_data[idx_gz:idx_gz+old_gz_size])

    # find vmlinuz data in firmware
    idx = bin_data.find(b"Direct booting from")
    if idx == -1:
        logmsg("Could not find Direct booting from string")
        idx = bin_data.find(b"Use a boot loader")
        if idx == -1:
            logmsg("Error: Could not find Use a boot loader string")
            sys.exit(1)
        logmsg("Probably handling a 64-bit firmware...")
    idx_vmlinuz = idx & 0xffffff00
    #logmsg("idx_vmlinuz=0x%x" % idx_vmlinuz)
    logmsg("unpack: Writing %s (%d bytes)..." % (out_vmlinuz_name, old_vmlinuz_size))
    open(out_vmlinuz_name, 'wb').write(bin_data[idx_vmlinuz:idx_vmlinuz+old_vmlinuz_size])

# Root an asa*.bin firmware by modifying the kernel command line
# It will start "/bin/sh" at boot instead of starting "init"
# In other word, the next time you boot it, it will present a root shell
def root(firmwarefile, out_bin_name=None):

    if out_bin_name == None:
        fileinfo = os.path.splitext(firmwarefile)
        out_bin_name = fileinfo[0] + '-rooted' + fileinfo[1]
    original_cmdline = b"quiet loglevel=0 auto"
    replace_cmdline = b"rdinit=/bin/sh"

    bin_data = open(firmwarefile, 'rb').read()
    idx = bin_data.rfind(original_cmdline)
    if idx == -1:
        logmsg("Warning: Could not find kernel command line, trying alternative method")
        # e.g. for 8.0.3
        original_cmdline = b"auto quiet loglevel=0"
        idx = bin_data.rfind(original_cmdline)
        if idx == -1:
            logmsg("Error: Could not find kernel command line")
            sys.exit(1)
    while len(replace_cmdline) < len(original_cmdline):
        replace_cmdline += b' '
    bin_data = bin_data.replace(original_cmdline, replace_cmdline)
    logmsg("root: Writing %s (%d bytes)..." % (out_bin_name, len(bin_data)))
    open(out_bin_name, 'wb').write(bin_data)

# Disable the root shell at boot for a device
def unroot(firmwarefile, out_bin_name=None):

    if out_bin_name == None:
        fileinfo = os.path.splitext(firmwarefile)
        out_bin_name = fileinfo[0] + '-unrooted' + fileinfo[1]
    original_cmdline = b"rdinit=/bin/sh       "
    replace_cmdline  = b"quiet loglevel=0 auto"

    data = open(firmwarefile, 'rb').read()
    idx = data.find(original_cmdline)
    if idx == -1:
        logmsg("Error: Could not find 'rdinit=/bin/sh' in %s" % firmwarefile)
        sys.exit(1)
    data = data.replace(original_cmdline, replace_cmdline)
    logmsg("unroot: Writing %s (%d bytes)..." % (out_bin_name, len(data)))
    open(out_bin_name, 'wb').write(data)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('-f', '--firmware-file', dest='firmware_file', default=None)
    parser.add_argument('-g', '--gzip-file', dest='gzip_file', default=None)
    parser.add_argument('-u', '--unpack', dest='unpack', default=False, action="store_true")
    parser.add_argument('-r', '--repack', dest='repack', default=False, action="store_true")
    parser.add_argument('-t', '--root', dest='root', default=False, action="store_true")
    parser.add_argument('-T', '--unroot', dest='unroot', default=False, action="store_true")
    parser.add_argument('-o', '--output-file', dest='outputfile', default=None)
    args = parser.parse_args()

    if args.unpack == False and args.repack == False and args.root == False and args.unroot == False:
        parser.error("[bin] Error: You need to provide at one of the following options: -u or -r or -t or -T")

    if args.repack:
        if not args.firmware_file or not args.gzip_file:
            parser.error("[bin] Error: Provide a firmware and a gzip file for repacking")
        repack(args.firmware_file, args.gzip_file, args.outputfile)
        if args.root:
            root(args.outputfile, args.outputfile)
        sys.exit()

    if args.unpack:
        if not args.firmware_file:
            parser.error("[bin] Error: Provide a firmware file for unpacking")
        unpack(args.firmware_file)
        sys.exit()

    if args.root:
        if not args.firmware_file:
            parser.error("[bin] Error: Provide a firmware file for rooting")
        root(args.firmware_file, args.outputfile)
        sys.exit()

    if args.unroot:
        if not args.firmware_file:
            parser.error("[bin] Error: Provide a firmware file for unrooting")
        unroot(args.firmware_file, args.outputfile)
        sys.exit()
