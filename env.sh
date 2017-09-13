#!/bin/sh
#
# This file is part of asafw.
# Copyright (c) 2017, Aaron Adams <aaron.adams(at)nccgroup(dot)trust>
# Copyright (c) 2017, Cedric Halbronn <cedric.halbronn(at)nccgroup(dot)trust>
#
# Initialization script to use before using any other script.
# Usage: source env.sh
#
# NOTE: sudo will require sudo -E
# NOTE: If you want a rootshell that inherits the environment use "sudo bash"

## VARIABLES ##
export ASATOOLS=1    # indicates env.sh was sourced

# Working directories 
export REPO="/path/to/main/repo/"
export TOOLDIR="${REPO}/asafw/"
export DEBUGDIR="${REPO}/asadbg/" 
export FIRMWAREDIR="/tmp" # where clean firmware files live
export FWTOOL="${TOOLDIR}/bin.py"
export UNPACK_REPACK_BIN="${TOOLDIR}/unpack_repack_bin.sh"
export LINA_LINUXSHELL="${TOOLDIR}/lina.py"
export WORKDIR="/tmp" # a directory for temporary files
export OUTDIR="/tmp" # a directory for generated files
export QCOW2MNT="/mnt/qcow2" # where we mount qcow2 files using qemu-nbd
# Credentials
export ASA_USER="user"
export ASA_PASS="user"
# Networking
export ASA_IP="192.168.210.77" # ASA IP address
export ATTACKER_ASA="192.168.210.78" # IP address to connect back to for debug shell
export ATTACKER_GNS3="192.168.100.201" # IP address to connect back to for debug shell (for GNS3)

export ASADBG_DB="${DEBUGDIR}/asadb.json"
export ASADBG_CONFIG="${DEBUGDIR}/template/asadbg.cfg"

export GNS3_IP="192.168.5.1" # ASA IP address (for GNS3)
export RETSYNC_IP="192.168.5.1" # IP address for instance of running IDA to connect ret-sync
export GDB="gdb" # Use a path to a gdb compiled with Python 3

# Maybe add TOOLDIR or DEBUGDIR already to PATH
if [ ! -z "${PATH##*${TOOLDIR}*}" ]; then
    PATH=${PATH}:${TOOLDIR}
fi
if [ ! -z "${PATH##*${DEBUGDIR}*}" ]; then
    PATH=${PATH}:${DEBUGDIR}
fi