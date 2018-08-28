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

SCRIPTNAME="unpack_repack_qcow2"

# FUNCTIONS

log()
{
    echo -n "[${SCRIPTNAME}] "
    echo "$@"
}


dbglog()
{
    if [ ! -z ${DEBUG} ]; then
        log DEBUG: $@
    fi
}

usage()
{
    echo "Usage:"
    echo "unpack_repack_qcow2.sh -i <qcow2_file> -o <out_dir> [-f -g -G -a -A -m -b -r -u -l <linabin_dir> -d -e -k]"
    echo "      -h, --help                          This help menu"
    echo "      -i, --input <qcow2_file>            What QCOW2 file to operate on.  This option is always required"
    echo "      -t <template_qcow2_file>            XXX"
    echo "      -o, --output  <out_qcow2_file>      Where to write new QCOW2"
    echo "      -g, --enable-gdb                    Set gdb to start on boot"
    echo "      -G, --disable-gdb                   Stop gdb from starting on boot"
    echo "      -a, --enable-aslr                   Turn on ASLR"
    echo "      -A, --disable-aslr                  Turn off ASLR"
    echo "      -r, --enable-root                   Enable root firmware"
    echo "      -R, --disable-root                  Disable root firmware"
    echo "      -m, --inject-gdb                    Inject gdbserver to run"
    echo "      -b, --debug-shell                   Inject ssh-triggered debug shell"
    echo "      -B, --serial-shell                  Configure a serial shell on ASA 2nd serial port"
    echo "      -H, --lina-hook <hooks to install>  Inject lina hooks (requires -b)"
    echo "      -c, --custom                        Custom functionality you can add yourself"
    echo "      -u, --unpack-only                   Unpack the asa*.bin firmware inside the QCOW2 and nothing else"
    echo "      --grub-timeout <timeout>            Change grub timeout to speed up boot process"
    echo "      --inject-grub-conf <grub.conf>      XXXX"
    echo "      --inject-bin <multi-bin qcow2>      XXXX"
    echo "      --mount-qcow2                       Mount qcow2 (debug)"
    echo "      --unmount-qcow2                     Unmount qcow2 (debug)"
    echo "      --partition <num>                   Partition to mount (debug)"
    echo "      -M, --multi-bin                     Indicates if the input qcow2 file is a multi-bin, so we inject the modified asa*.bin in the right partition"
    echo "      -v, --verbose                       Display debug messages"
    echo "Examples:"
    echo " unpack_repack_qcow2.sh -i asav962-7.qcow2 -A -g -b -H hat"
    echo " unpack_repack_qcow2.sh -i asav962-7.qcow2 -u"
    echo " unpack_repack_qcow2.sh -i asav962-7-multiple-bins.qcow2 --inject-grub-conf grub-multi-bin.conf --inject-bin asa962-7-smp-k8-noaslr-backdoor.bin"
    echo "# Inject asa962-7-smp-k8-noaslr-debugshell.bin into multiple-bin QCOW2:"
    echo " unpack_repack_qcow2.sh -i asav962-7.qcow2 -M -A -b"
    echo "# Inject asa962-7-smp-k8-noaslr-debugshell-gdbserver.bin into multiple-bin QCOW2:"
    echo " unpack_repack_qcow2.sh -i asav962-7.qcow2 -M -A -b -g -m"
    echo "# Inject asa962-7-smp-k8-noaslr-debugshell-hooked.bin into multiple-bin QCOW2:"
    echo " unpack_repack_qcow2.sh -i asav962-7.qcow2 -M -A -b -H hat"
    echo "# Inject asa962-7-smp-k8-noaslr-debugshell-hooked-gdbserver.bin into multiple-bin QCOW2:"
    echo " unpack_repack_qcow2.sh -i asav962-7.qcow2 -M -A -b -H hat -g -m"
    exit
}

# Parameters:
# 1 : String : path where to mount the qcow2 (e.g. /home/user/mnt/qcow2)
# 2 : Integer: partition ID (e.g. 1 or 2)
mount_qcow()
{
    dbglog "mount_qcow(${1}, ${2})"

    # Just avoid errors in case it's already connected
    mount /dev/nbd0p${2} ${1}
    if [ $? != 0 ]; then
        log "[!] Could not mount ${1}"
        umount ${1}
        exit
    fi
    log "Mounted /dev/nbd0p${2} to ${1}"
}

# Parameters:
# 1 : String : path where to mount the qcow2 (e.g. /home/user/mnt/qcow2)
# 2 : String: path for the input grub.conf (e.g. /path/to/grub.conf)
inject_grub_config()
{
    dbglog "inject_grub_config(${1}, ${2})"

    # In a mult-bin qcow partition 1 holds the grub config
    mount_qcow ${1} 1
    cp ${2} ${1}/boot/grub.conf
    log "Overwrote ${1}/boot/grub/conf with ${2}"
    umount ${1}
}

# Parameters:
# 1 : String : path where to mount the qcow2 (e.g. /home/user/mnt/qcow2)
# 3 : String : relative filename for asa*.bin to copy to partition 2 (e.g. asa962-7-smp-k8-noaslr-debugshell.bin)
inject_multibin()
{
    dbglog "inject_multibin(${1}, ${2})"

    # In a mult-bin qcow partition 2 holds the extra bin files
    mount_qcow ${1} 2
    cp ${2} ${1}/
    log "Wrote ${2} into partition 2 of multi-bin qcow"
    umount ${1}
}


# We inherit the name of the qcow2 and apply it to the bin, in case we have
# duplicates and don't want to overwrite or binwalk the same file name.
# Parameters:
# 1 : String : path where to mount the qcow2 (e.g. /home/user/mnt/qcow2)
# 2 : String : path where to copy the extracted .bin (e.g. /current/folder/bin/asav962-7.qcow2.
#              Note we copy asa962-7-smp-k8.bin to a asav962-7.qcow2
#              so it is known by our asadb.json, for instance to patch lina, but it is a .bin!)
extract_bin()
{
    dbglog "extract_bin(${1}, ${2})"

    # A default qcow2 has its asa* in its partition 1
    # Even if we store additional ones in partition 2 for multiple-bin qcow2, we
    # always extract the one from partition 1 as it is untouched
    mount_qcow ${1} 1
    COUNTBIN=$(ls ${1}/asa*.bin|wc -l)
    if [[ "$COUNTBIN" != "1" ]]; then
        log "[!] ERROR: Found ${COUNTBIN} asa*.bin in partition 1"
        umount ${1}
        exit
    fi
    BINPATH=$(ls ${1}/asa*.bin)
    if [ $? != 0 ]; then
        log "[!] ERROR: Couldn't not find ${1}/asa*.bin in partition 1"
        umount ${1}
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

    # XXX we do it here because after we unmount it. We should fix
    # the architecture of this script so we only mount at the beginning
    # and unmount at the end so we can do all modifications in between
    # in one function
    if [[ ! -z ${GRUB_TIMEOUT} ]]
    then
        # default timeout is 10 seconds but we speed the process of booting by setting it to 1 :)
        log "GRUB TIMEOUT set to ${GRUB_TIMEOUT}"
        # XXX - running the cmd via the variable fails
        SEDCMD="sed -i 's/timeout \(.*\)/timeout ${GRUB_TIMEOUT}/' ${QCOW2MNT}/boot/grub.conf"
        sed -i "s/timeout \(.*\)/timeout ${GRUB_TIMEOUT}/" ${QCOW2MNT}/boot/grub.conf
        if [ $? != 0 ];
        then
            log "${SEDCMD} failed"
            umount ${1}
            exit
        fi
    fi

    umount ${1}
    log "Unmounted ${1}"
}

fini_nbd()
{
    dbglog "fini_nbd()"

    log "Disconnecting /dev/nbd0"
    qemu-nbd --disconnect /dev/nbd0  > /dev/null
}

# Parameters:
# 1 : String : path to input qcow2 file (e.g. /current/folder/asav962-7.qcow2)
init_nbd()
{
    dbglog "init_nbd(${1})"

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
    log "Mounting ${1} to /dev/nbd0"
    qemu-nbd --connect=/dev/nbd0 "${1}"

    # At some point this changed, and we have to probe?
    # solution found here:
    # https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=824553
    partprobe /dev/nbd0
    PARTCOUNT=$(fdisk /dev/nbd0 -l | grep nbd0p | wc -l)
    if [ "${PARTCOUNT}" == 0 ]; then
        log "[!] Something wrong with qcow? No partitions detected"
        qemu-nbd --disconnect /dev/nbd0 > /dev/null
        exit
    fi
#    log "QCOW2 has ${PARTNUM} partitions"
}

### nbd-based Functions ###

# Parameters:
# 1 : XXX
# 2 : XXX
add_serial()
{
    dbglog "add_serial(${1}, ${2})"

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
    log "Mounted /dev/nbd0p2 to ${MNTDIR}"
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

### Actual workhorse logic ###

# Parameters:
# 1 : String : path to input qcow2 file (e.g. /current/folder/asav962-7.qcow2)
# 2 : String : path where to mount the qcow2 (e.g. "/home/user/mnt/qcow2")
# 3 : String : path where to copy the extracted .bin (e.g. /current/folder/bin/asav962-7.qcow2.
#              Note we copy asa962-7-smp-k8.bin to a asav962-7.qcow2
#              so it is known by our asadb.json, for instance to patch lina, but it is a .bin!)
extract_qcow2()
{
    dbglog "extract_qcow2(${1}, ${2}, ${3})"

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

# Parameters:
# 1 : String : path to repacked asa*.bin file to inject (e.g. /current/folder/bin/asav962-7.qcow2)
#              Note asav962-7.qcow2 is actually a .bin! We used this name
#              so it is known by our asadb.json, for instance to patch lina.)
# 2 : String : path to temporary repacked asav*.qcow2 file (e.g. /current/folder/bin/asav962-7-repacked.qcow2)
# 3 : String : path to final repacked asav*.qcow2 file (e.g. /current/folder/asav962-7-repacked.qcow2)
# 4 : String : path where to mount the qcow2 (e.g. "/home/user/mnt/qcow2")
# 5 : String : empty by default, set to 1 if a multi-bins qcow2 (so asa*.bin is injected in partition 2)
repackage_qcow2()
{
    dbglog "repackage_qcow2(${1}, ${2}, ${3}, ${4}, multi-bins=${5})"

    init_nbd ${3}
    mount /dev/nbd0p1 ${4}
    log "Mounted /dev/nbd0p1 to ${4}"
    ORIG=$(ls ${4}/asa*.bin)
    if [ $? != 0 ]; then
        log "[!] Couldn't not find ${4}"
        exit
    fi

    if [[ -z ${5} ]]; then
        DEST=${ORIG}
    else
        sleep 1
        umount ${4}

        # get filename without extension and extension
        OUTFILE=$(basename "$ORIG")
        EXTFILE=${ORIG##*.}

        OUTFILE_SUFFIX=
        # the more complex filename we could get is something like
        # "asaXXX-smp-k8-noaslr-debugshell-hooked-gdbserver.bin"
        if [[ ! -z "${DISABLE_ASLR}" ]]
        then
            OUTFILE_SUFFIX=$OUTFILE_SUFFIX-noaslr
        fi
        if [[ ! -z "${DEBUGSHELL}" ]]
        then
            OUTFILE_SUFFIX=$OUTFILE_SUFFIX-debugshell
        fi
        if [[ ! -z "${LINAHOOK}" ]]
        then
            OUTFILE_SUFFIX=$OUTFILE_SUFFIX-hooked
        fi
        if [[ ! -z "${ENABLE_GDB}" ]]
        then
            OUTFILE_SUFFIX=$OUTFILE_SUFFIX-gdbserver
        fi
        OUTFILE_SUFFIX=$OUTFILE_SUFFIX.${EXTFILE}
        DEST=${4}/${OUTFILE%.*}${OUTFILE_SUFFIX}
        log "Destination file: ${DEST}"

        mount /dev/nbd0p2 ${4}
        log "Mounted /dev/nbd0p2 to ${4}"
    fi

    cp ${2} ${DEST}
    if [ $? != 0 ]; then
        log "[!] Couldn't not find repacked name: ${2}"
        exit
    fi
    log "Injected ${3} with new .bin file ${DEST}"
    umount ${4}
    fini_nbd
    log "Unmounted ${4}"
}

# Parameters:
# 1 : XXX
# 2 : XXX
# 3 : XXX
extract_one()
{
    dbglog "extract_one(${1}, ${2}, ${3})"

    log "extract_one: $QCOW2FILE"

    extract_qcow2 ${QCOW2FILE} ${QCOW2MNT} ${BINFILE}

    # XXX - we generally want to avoid using -k as we want to keep the kernel to get the kernel version
    # but we may want to support it in case we want to only keep the rootfs for debugging
    #${UNPACK_REPACK_BIN} -i ${BINFILE} -u -k ${DEBUG}
    ${UNPACK_REPACK_BIN} -i ${BINFILE} -u ${DEBUG}
    FWFOLDER=${QCOWDIR}/bin/_${BASEQCOW2FILE_NOEXT}.qcow2.extracted
    if [ ! -d "${FWFOLDER}" ]; then
        log "Error: binwalk extraction failed. Didn't find ${FWFOLDER}"
        exit
    fi
    mv ${FWFOLDER} ${QCOWDIR}/
    if [ -z ${DEBUG} ]
    then
    #rm ${BINFILE} ${BINFILE_REPACKED} ${BINFILE_REPACKED2}
        rm ${BINFILE}
    fi
}

# Parameters:
# 1 : XXX
# 2 : XXX
# 3 : XXX
extract_repack_one()
{
    dbglog "extract_repack_one(${1}, ${2}, ${3})"

    log "extract_repack_one: $QCOW2FILE"

    extract_qcow2 ${QCOW2FILE} ${QCOW2MNT} ${BINFILE}

    ${UNPACK_REPACK_BIN} -i ${BINFILE} ${BIN_CMDLINE} -s ${DEBUG}
    if [ $? != 0 ];
    then
        log ${UNPACK_REPACK_BIN} -i ${BINFILE} ${BIN_CMDLINE} -s ${DEBUG} failed
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
    if [[ "${MULTI_BIN}" == "YES" ]]
    then
        repackage_qcow2 ${BINFILE} ${BINFILE_REPACKED2} ${OUTQCOW2FILE} ${QCOW2MNT} 1
    else
        repackage_qcow2 ${BINFILE} ${BINFILE_REPACKED2} ${OUTQCOW2FILE} ${QCOW2MNT}
    fi

    if [ -z ${DEBUG} ]
    then
        if [[ "${BINFILE_REPACKED}" == "${BINFILE_REPACKED2}" ]]
        then
            rm ${BINFILE} ${BINFILE_REPACKED2}
        else
            rm ${BINFILE} ${BINFILE_REPACKED} ${BINFILE_REPACKED2}
        fi
    fi
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
SERIALSHELL=
LINAHOOK=
# do we keep temporary files? Use if need to debug
DEBUG=
UNPACK_ONLY="NO"
GRUB_TIMEOUT=
INJECT_GRUBCONFIG="NO"
INJECT_MULTIBIN="NO"
MULTI_BIN="NO"
while [[ $# -gt 0 ]]
do
    key="$1"

    case $key in
        -i|--input)
        QCOW2FILE="$2"
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
        -B|--serial-shell)
        SERIALSHELL=" -B"
        ;;
        -H|--lina-hook)
        LINAHOOK=" -H $2"
        shift
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
        --grub-timeout)
        GRUB_TIMEOUT="${2}"
        shift # past argument
        ;;
        --inject-grub-conf)
        INJECT_GRUB_CONF="${2}"
        shift # past argument
        ;;
        --inject-bin)
        INJECT_BIN="${2}"
        shift # past argument
        ;;
        -M|--multi-bin)
        MULTI_BIN="YES"
        ;;
        -v|--verbose)
        DEBUG="-v"
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

# Will always force to free space in the .bin with -f
BIN_CMDLINE="-f ${ENABLE_GDB}${DISABLE_GDB}${ENABLE_ASLR}${DISABLE_ASLR}${INJECT_GDB}${CUSTOM}${DEBUGSHELL}${SERIALSHELL}${LINAHOOK}"
if [ ! -z ${DEBUG} ]
then
    BIN_CMDLINE="${BIN_CMDLINE} -n"
fi

if [[ -z ${QCOW2FILE} || ! -f ${QCOW2FILE} ]]
then
    log "ERROR: You must specify at least a valid -i file: ${QCOW2FILE}"
    log "ERROR: Double check your working directory as ${QCOW2FILE} doesn't appear to exist"
    exit
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

if [ ! -z "${ENABLE_SERIAL}" ]; then
    # We exit immediately because this is used for patching a flash qcow2 and
    # not the same qcow2 for enabling gdb, etc.
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

if [[ ! -z "${INJECT_GRUB_CONF}" ]]; then
    init_nbd ${QCOW2FILE}
    echo "Injecting grub config"
    inject_grub_config ${QCOW2MNT} ${INJECT_GRUB_CONF}
    fini_nbd
fi

if [[ ! -z "$INJECT_BIN" ]]; then
    init_nbd ${QCOW2FILE}
    log "Injecting ${INJECT_BIN} into ${QCOW2FILE}"
    inject_multibin ${QCOW2MNT} ${INJECT_BIN}
    fini_nbd
else
    log "Using input qcow2 file: ${QCOW2FILE}"
    log "Using template qcow2 file: ${TEMPLATEQCOW2FILE}"
    log "Using output qcow2 file: ${OUTQCOW2FILE}"
    log "Command line: ${BIN_CMDLINE}"

    # Work is done in a "bin" directory because we use the same name for both
    # the .bin and the .qcow2 file. This is for several reasons:
    # 1. our target database contains a .qcow2 name so we need this when
    #    patching "lina" to the right target offsets
    # 2. binwalk will create a folder with the .bin name so we need it to also
    #    match the actual .qcow2 so it is correct when debugging
    mkdir ${QCOWDIR}/bin &> /dev/null
    BINFILE=${QCOWDIR}/bin/${BASEQCOW2FILE_NOEXT}.qcow2

    if [[ "$UNPACK_ONLY" == "YES" ]]
    then
        extract_one
    else
        extract_repack_one
    fi
fi
