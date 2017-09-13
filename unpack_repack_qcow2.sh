#!/bin/bash
#
# This file is part of asafw.
# Copyright (c) 2017, Aaron Adams <aaron.adams(at)nccgroup(dot)trust>
# Copyright (c) 2017, Cedric Halbronn <cedric.halbronn(at)nccgroup(dot)trust>
#
# This script is used to unpack all Cisco ASA routers .qcow2 packed files,
# extract the .bin and modify some files in the rootfs.img in order to start 
# gdb after booting the OS. Everything is then repackaged back into the .qcow2
#
# TODO
# - actually use the template (TEMPLATEQCOW2FILE)
# - Probably can use with a ton of cleanup in general

log()
{
    echo "[unpack_repack_qcow2] ${1}"
}

usage()
{
    log "Usage:"
    log "./unpack_repack_qcow2.sh -i <qcow2_file> [-o <out_qcow2_file> -t <template_qcow2_file> --inject-gdb --enable-gdb --disable-gdb --enable-aslr --disable-aslr --enable-root --disable-root --debug-shell --mount-qcow2 --unmount-qcow2 --unpack-only"
    log "E.g.: ./unpack_repack_qcow2.sh -i /home/user/cisco/firmware/asav961-gns3.qcow2 -t /home/user/cisco/firmware/asav961.qcow2 -m -g -G -a -A -r -R -b"
    log "E.g.: ./unpack_repack_qcow2.sh -i /home/user/cisco/firmware/asav961-gns3.qcow2 -u"
    exit
}

# We inherit the name of the qcow2 and apply it to the bin, in case we have
# duplicates and don't want to overwrite or binwalk the same file name.
extract_bin()
{
    # Just avoid errors in case it's already connected
    mount /dev/nbd0p1 ${1}
    if [ $? != 0 ]; then
        log "[!] Could not mount ${1}"
        umount ${1}
        exit
    fi
    log "Mounted /dev/nbd01 to ${1}"
    BINPATH=$(ls ${1}/asa*.bin)
    if [ $? != 0 ]; then
        log "[!] Couldn't not find ${1}"
        exit
    fi
    BIN=$(basename "${BINPATH}")
    if [ ! -z "${2}" ]; then
       DEST="${2}"
    fi

    cp "${BINPATH}" "${DEST}"
    if [ $? != 0 ]; then
        log "[!] Couldn't not copy .bin"
        exit
    fi
    log "Copied ${BIN} to ${DEST}"
    umount ${1}
    log "Unmounted ${1}"
}

fini_nbd()
{
    qemu-nbd --disconnect /dev/nbd0  > /dev/null
}

init_nbd()
{
    qemu-nbd --disconnect /dev/nbd0 > /dev/null
    if [ -z "${1}}" ]; then
        log "[!] init_nbd() expects one argument"
        exit
    fi
#    log "Loading nbd driver"
    modprobe nbd
    lsmod | grep nbd > /dev/null
    if [ $? != 0 ]; then
        log "[!] Couldn't load nbd driver"
        exit
    fi
#    log "Mounting ${1} to /dev/nbd0"
    qemu-nbd --connect=/dev/nbd0 "${1}"

    PARTCOUNT=$(fdisk /dev/nbd0 -l | grep nbd0p | wc -l)
    if [ "${PARTCOUNT}" == 0 ]; then
        log "[!] Something wrong with qcow? No partitions detected"
        qemu-nbd --disconnect /dev/nbd0 > /dev/null
        exit
    fi
#    log "QCOW2 has ${PARTNUM} partitions"
}

### nbd-based Functions ###
add_serial()
{
    init_nbd "${1}"
    MNTDIR="${2}"
    if [ -z "${MNTDIR}" ]; then
        log "[!] Extraction requires -m <dir>"
        exit
    fi

    # init_nbd sets PARTCOUNT
    if [[ "${PARTCOUNT}" < 2 ]]; then
        log "[!] There is no partition 2 to mount. Maybe wrong qcow2 file"
        exit
    fi

    mount /dev/nbd0p2 "${MNTDIR}"
    if [ $? != 0 ]; then
        log "[!] Possibly the wrong qcow as there is no second partition?"
        exit
    fi
    log "Mounted /dev/nbd02 to ${MNTDIR}"
    if [ ! -e "${MNTDIR}/coredumpinfo" ]; then
        log "[!] Missing expected coredumpinfo folder"
        log "[!] Are you sure this is the flash qcow?"
    fi
    touch "${MNTDIR}/use_ttyS0"
    log "Wrote use_ttyS0 file"

    umount ${MNTDIR}
    log "Unmounted ${MNTDIR}"
    fini_nbd
}

### INIT ###

if [ -z "${ASATOOLS}" ]; then
    log "[!] This tool relies on env.sh which has not been sourced"
    exit
fi

BINWALK=$(which binwalk)
if [ -z "${BINWALK}" ]; then
    log "[!] binwalk not found. Required for extract_bin.sh usage"
    log "[!] NOTE: binwalk must be > v2.0"
    exit
fi

### ARG Parsing ###

# http://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash
QCOW2FILE=
OUTQCOW2FILE=
TEMPLATEQCOW2FILE=
ENABLE_GDB=
DISABLE_GDB=
ENABLE_ASLR=
DISABLE_ASLR=
ENABLE_ROOT="NO"
DISABLE_ROOT="NO"
ENABLE_SERIAL=
QCOW_MOUNT=
QCOW_UMOUNT=
# An original asav*.qcow2 has only 1 partition
# An asav*.qcow2 loaded in GNS3 will have 2nd partition for hda_disk.
QCOW_PARTNUM=1
INJECT_GDB=
CUSTOM=
DEBUGSHELL=
# do we keep temporary files? Use if need to debug
DEBUG="NO"
UNPACK_ONLY="NO"
while [[ $# -gt 0 ]]
do
    key="$1"

    case $key in
        -i|--input)
        QCOW2FILE="$2"
        shift # past argument
        ;;
        --debug)
        DEBUG="YES"
        shift # past argument
        ;;
        -o|--output)
        OUTQCOW2FILE="$2"
        shift # past argument
        ;;
        -t|--template)
        TEMPLATEQCOW2FILE="$2"
        shift # past argument
        ;;
        -g|--enable-gdb)
        ENABLE_GDB=" -g"
        ;;
        -G|--disable-gdb)
        DISABLE_GDB=" -G"
        ;;
        -a|--enable-aslr)
        ENABLE_ASLR=" -a"
        ;;
        # this is used for debugging purpose, see unpack_repack_bin.sh
        -c|--custom)
        CUSTOM=" -c"
        ;;
        -A|--disable-aslr)
        DISABLE_ASLR=" -A"
        ;;
        -m|--inject-gdb)
        INJECT_GDB=" -m"
        ;;
        -r|--enable-root)
        ENABLE_ROOT="YES"
        ;;
        -R|--disable-root)
        DISABLE_ROOT="YES"
        ;;
        -b|--debug-shell)
        DEBUGSHELL=" -b"
        ;;
        -s|--enable-serial)
        ENABLE_SERIAL="YES"
        ;;
        # QCOW Helper 
        --mount-qcow2)
        QCOW_MOUNT="YES"
        ;;
        # QCOW Helper 
        --unmount-qcow2)
        QCOW_UMOUNT="YES"
        ;;
        # QCOW Helper 
        --partition)
        QCOW_PARTNUM="$2"
        shift
        ;;
        -u|--unpack-only)
        UNPACK_ONLY="YES"
        ;;
        -h|*)
        # unknown option
        log "[!] Unknown option provided: $key"
        usage
        ;;
    esac
    shift # past argument or value
done

# root is needed so we can mount/unmount the qcow2
# and alternatively so the repacked version has the right uid/gid (when applicable)
# do this hear so you can at least see -h without sudo
if [ "$(whoami)" != "root" ]; then
    log "You need to be root to mount/unmount the qcow2"
    exit
fi

BIN_CMDLINE="-f ${ENABLE_GDB}${DISABLE_GDB}${ENABLE_ASLR}${DISABLE_ASLR}${INJECT_GDB}${CUSTOM}${DEBUGSHELL}"
if [[ "$DEBUG" == "YES" ]]
then
    BIN_CMDLINE="${BIN_CMDLINE} -n"
fi

if [[ -z $QCOW2FILE || ! -f $QCOW2FILE ]]
then
    log "[!] You must specify at least a valid -i file: ${QCOW2FILE}"
    usage
fi

if [[ -z $TEMPLATEQCOW2FILE ]]
then
    TEMPLATEQCOW2FILE="$QCOW2FILE"
fi

QCOWDIR=$(dirname "$QCOW2FILE")
# Checking for . allows us to specify relative paths...
if [[ ${QCOWDIR} == '.' ]]; then
    QCOWDIR=$(pwd)
fi
BASEQCOW2FILE=$(basename "$QCOW2FILE")
BASEQCOW2FILE_NOEXT=${BASEQCOW2FILE%.*}

if [[ -z $OUTQCOW2FILE ]];
then
    OUTQCOW2FILE=${QCOWDIR}/${BASEQCOW2FILE_NOEXT}-repacked.qcow2
fi

### Actual workhorse logic ###

# extract_qcow2(qcow2, mnt_dir, outfile)
extract_qcow2()
{
    QNBD=$(which qemu-nbd)
    if [ -z "${QNBD}" ]; then
        log "[!] qemu-nbd tool not found. Please install or use -o"
        exit
    fi

    init_nbd ${1}
    if [ -z "${2}" -o -z "${3}" ]; then
        log "[!] Extraction requires 3 arguments"
        exit
    else
        extract_bin ${2} ${3}
    fi
    fini_nbd
}

# repackage_qcow2(binfile, repacked_name, new_qcow2, mntdir)
repackage_qcow2()
{
    init_nbd ${3}
    mount /dev/nbd0p1 ${4}
    log "Mounted /dev/nbd01 to ${4}"
    ORIG=$(ls ${4}/asa*.bin)
    if [ $? != 0 ]; then
        log "[!] Couldn't not find ${4}"
        exit
    fi
    cp ${2} ${ORIG}
    if [ $? != 0 ]; then
        log "[!] Couldn't not find repacked name: ${2}"
        exit
    fi
    log "Moved modified .bin inside of ${3}"
    umount ${4}
    fini_nbd
    log "Unmounted ${4}"
}

extract_one()
{
    log "extract_one: $QCOW2FILE"
    
    extract_qcow2 ${QCOW2FILE} ${QCOW2MNT} ${BINFILE}
    
    # XXX - we generally want to avoid using -k as we want to keep the kernel to get the kernel version
    # but we may want to support it in case we want to only keep the rootfs for debugging
    #${UNPACK_REPACK_BIN} -i ${BINFILE} -u -k
    ${UNPACK_REPACK_BIN} -i ${BINFILE} -u
    FWFOLDER=${QCOWDIR}/bin/_${BASEQCOW2FILE_NOEXT}.qcow2.extracted
    if [ ! -d "${FWFOLDER}" ]; then
        log "Error: binwalk extraction failed. Didn't find ${FWFOLDER}"
        exit
    fi
    mv ${FWFOLDER} ${QCOWDIR}/
    if [[ "$DEBUG" == "NO" ]];
    then
    #rm ${BINFILE} ${BINFILE_REPACKED} ${BINFILE_REPACKED2}
        rm ${BINFILE}
    fi
}

extract_repack_one()
{
    log "extract_repack_one: $QCOW2FILE"
    
    extract_qcow2 ${QCOW2FILE} ${QCOW2MNT} ${BINFILE}

    ${UNPACK_REPACK_BIN} -i ${BINFILE} ${BIN_CMDLINE} -s
    if [ $? != 0 ];
    then
        log ${UNPACK_REPACK_BIN} -i ${BINFILE} ${BIN_CMDLINE} -s failed
        exit
    fi

    BINFILE_REPACKED=${QCOWDIR}/bin/${BASEQCOW2FILE_NOEXT}-repacked.qcow2
    BINFILE_REPACKED2=${BINFILE_REPACKED}
    if [[ "${ENABLE_GDB}" == " -g" ]] 
    then
        BINFILE_REPACKED=${QCOWDIR}/bin/${BASEQCOW2FILE_NOEXT}-repacked-gdbserver.qcow2
        BINFILE_REPACKED2=${BINFILE_REPACKED}
    elif [[ "$ENABLE_ROOT" == "YES" ]]
    then
        log "ENABLE ROOT"
        BINFILE_REPACKED2=${QCOWDIR}/bin/${BASEQCOW2FILE_NOEXT}-repacked-rooted.qcow2
        ${FWTOOL} -t -f ${BINFILE_REPACKED} -o ${BINFILE_REPACKED2}
        if [ $? != 0 ];
        then
            log ${FWTOOL} -t -f ${BINFILE_REPACKED} -o ${BINFILE_REPACKED2} failed
            exit
        fi
    elif [[ "$DISABLE_ROOT" == "YES" ]]
    then
        log "DISABLE ROOT"
        BINFILE_REPACKED2=${QCOWDIR}/${BASEQCOW2FILE_NOEXT}-repacked-rooted.bin
        ${FWTOOL} -T -f ${BINFILE_REPACKED} -o ${BINFILE_REPACKED2}
        if [ $? != 0 ];
        then
            log ${FWTOOL} -T -f ${BINFILE_REPACKED} -o ${BINFILE_REPACKED_ROOTED} failed
            exit
        fi
    fi

    cp ${QCOW2FILE} ${OUTQCOW2FILE}
    repackage_qcow2 ${BINFILE} ${BINFILE_REPACKED2} ${OUTQCOW2FILE} ${QCOW2MNT}

    if [[ "$DEBUG" == "NO" ]];
    then
        if [[ "${BINFILE_REPACKED}" == "${BINFILE_REPACKED2}" ]]
        then
            rm ${BINFILE} ${BINFILE_REPACKED2}
        else
            rm ${BINFILE} ${BINFILE_REPACKED} ${BINFILE_REPACKED2}
        fi
    fi
}


# We exit immediately because this is used for patching a flash qcow2 and not
# the same qcow2 for enabling gdb, etc.
if [ ! -z "${ENABLE_SERIAL}" ]; then
    add_serial "${QCOW2FILE}" "${QCOW2MNT}"
    exit
fi

if [ ! -z "${QCOW_MOUNT}" ]; then
    init_nbd ${QCOW2FILE}
    if [[ ${QCOW_PARTNUM} > ${PARTCOUNT} ]]; then
        log "qcow2 has ${PARTCOUNT} partitions. You asked for ${QCOW_PARTNUM}"
        exit
    fi
    mount /dev/nbd0p${QCOW_PARTNUM} ${QCOW2MNT}
    exit
fi

if [ ! -z "${QCOW_UMOUNT}" ]; then
    umount ${QCOW2MNT}
    fini_nbd
    exit
fi

log "Using input qcow2 file: ${QCOW2FILE}"
log "Using template qcow2 file: ${TEMPLATEQCOW2FILE}"
log "Using output qcow2 file: ${OUTQCOW2FILE}"
log "Command line: ${BIN_CMDLINE}"

# Work is done in a "bin" directory because we use the same name for the .bin
# that for the .qcow2. This is for several reasons:
# 1. our database contains actual .qcow2 name so we need this when patching "lina" to the right offsets
# 2. binwalk will create a folder with the .bin name so we need it to also match the actual .qcow2 so
#    it is correct when debugging
mkdir ${QCOWDIR}/bin
BINFILE=${QCOWDIR}/bin/${BASEQCOW2FILE_NOEXT}.qcow2

if [[ "$UNPACK_ONLY" == "YES" ]]
then
    extract_one
else
    extract_repack_one
fi