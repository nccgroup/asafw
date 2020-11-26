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

SCRIPTNAME="unpack_repack_bin"

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
    echo "./unpack_repack_bin.sh -i <firmware_file> -o <out_dir> [-f -g -G -a -A -m -b -r -u -l <linabin_dir> -d -e -k]"
    echo "      -h, --help                   This help menu"
    echo "      -i, --input <firmware_file>  What firmware bin to operate on.  This option is always required"
    echo "      -o, --output  <out_dir>      Where to write new firmware"
    echo "      -f, --free-space             Remove space from .bin to ensure injections fit"
    echo "      -g, --enable-gdb             Set gdb to start on boot"
    echo "      -G, --disable-gdb            Stop gdb from starting on boot"
    echo "      -a, --enable-aslr            Turn on ASLR"
    echo "      -A, --disable-aslr           Turn off ASLR"
    echo "      -m, --inject-gdb             Inject gdbserver for firmware lacking this file"
    echo "      -b, --debug-shell            Inject ssh-triggered debug shell"
    echo "      -B, --serial-shell           Configure a serial shell on ASA 2nd serial port"
    echo "      -H, --lina-hook              Inject hooks for monitor lina heap (requires -b)"
    echo "      -r, --root                   Root the bin to get a rootshell on boot"
    echo "      -c, --custom                 Custom functionality you can add yourself"
# XXX - Unused. Likely delete
#    echo "      -q, --gns3-fixup             Gns?"
    echo "      -u, --unpack-only            Unpack the firmware and nothing else"
    echo "      -l, --linabins <linabin_dir> Destination folder to save lina binaries"
    echo "      -d, --delete-extracted       Delete files extracted during modification"
    echo "      -e, --delete-original-bin    Delete the original firmware being modified"
    echo "      -k, --keep-rootfs            Keep the extracted rootfs on disk"
    echo "      -s, --simple-name            Use a simple name for the output .bin with just appended '-repacked'"
    echo "      -R, --repack-only            Repack an existing unpacked dir.  Requires --original-firmware"
    echo "      --replace-linamonitor <path> Use a simple name for the output .bin with just appended '-repacked'"
    echo "      --original-firmware <name>   Name of original firmware file. for use with --repack-only"
    echo "      --bin-with-asa-to-inject <firmware_file>    Additional firmware bin file to take /asa folder from and inject into the one specified with -i"
    echo "      -v, --verbose                Display debug messages"
    echo "Examples:"
    echo " # Unpack and repack a firmware file, freeing space, enabling gdb, and injecting gdbserver bin. Output modifications to firmware_repacked dir"
    echo " ./unpack_repack_bin.sh -i /home/user/firmware -o /home/user/firmware_repacked --free-space --enable-gdb --inject-gdb"
    echo " # Unpack and repack a firmware file, freeing space, enabling gdb, and injecting gdbserver bin"
    echo " ./unpack_repack_bin.sh -i /home/user/firmware/asa961-smp-k8.bin -f -g -m"
    echo " # Unpack a firmware file and copy the lina and lina_monitor file in to linabins dir"
    echo " ./unpack_repack_bin.sh -u -i /home/user/firmware -l /home/user/linabins"
    echo " # Unpack a firmware file and keep the rootfs on disk for analysis"
    echo " ./unpack_repack_bin.sh -u -i /home/user/firmware/asa924-k8.bin -k"
    echo " # Repack an already unpacked firmware dir, freeing space and patching lina_monitor to bypass checksum validation"
    echo " ./unpack_repack_bin.sh --repack-only -i _asa924-smp-k8.bin.extracted --output-bin asa924-smp-k8-repacked.bin --original-firmware /home/user/firmware/asa924-smp-k8.bin --free-space --replace-linamonitor /home/user/firmware/lina_monitor_patched"
    echo " # Unpack and repack a firmware file, freeing space, enabling gdb, debug shell and linahook"
    echo " ./unpack_repack_bin.sh -i asa924-smp-k8.bin -f -g -b -H hat"
    exit 1
}

# determine_rootfs_name()
#
# Arguments:
#  None
#
# Description:
#  versions < 8.2.3 don't have the rootfs in rootfs.img but in a filename
#  containing digits only ASAv961 has a a .gz additional extension in rootfs
#  image name
##
determine_rootfs_name()
{
    ROOTFS=rootfs.img
    if [ -f ${ROOTFS} ]; then
        log "Firmware uses regular rootfs/ dir"
    elif [ -f "rootfs.img.gz" ]; then
        ROOTFS=rootfs.img.gz
        log "Firmware uses regular rootfs.img.gz file"
    else
        for EXTRACTFILE in $(find * -maxdepth 0 -type f);
        do
            TMP=`file ${EXTRACTFILE}`
            if [[ $TMP == *"ASCII cpio archive"* ]];
            then
                ROOTFS=${EXTRACTFILE}
                log "Firmware uses ${ROOTFS} rootfs file"
                break
            fi
        done
    fi
}

# extract_bin()
#
# Arguments:
#  None
#
# Required Globals:
#  FWFILE
#
# Notes:
#  Expects current folder being the dirname of $FWFILE
#
# Description:
#  Extracts the contents of a firmware .bin file using binwalk. The files are
#  written to a directory called _<bin name>.extracted
#
#  Can be called independent of other bin functions.
##
extract_bin()
{
    log "extract_bin: $FWFILE"
    if [ -z ${DEBUG} ]; then
        ${BINWALK} -e ${FWFILE} > /dev/null
    else
        ${BINWALK} -e ${FWFILE}
    fi
    if [ $? != 0 ];
    then
        log "ERROR: Binwalk failed. Exiting"
        exit 1
    fi
    FWFOLDER=$(pwd)/_${FWFILE}.extracted
    if [ ! -d "${FWFOLDER}" ]; then
        log "ERROR: binwalk extraction failed. Didn't find ${FWFOLDER}"
        return
    fi
    cd ${FWFOLDER}
    # better safe than sorry. If we can't go in, when we go out later
    # we will go back in the arborescence and do bad stuff, such as delete
    # files, etc...
    if [ $? != 0 ];
    then
        log "ERROR: Couldn't enter ${FWFOLDER} for some reason. Exiting"
        exit 1
    fi
    log "Extracted firmware to ${FWFOLDER}"

    determine_rootfs_name
    # we create a directory to avoid extracting everything
    # in the middle of other files
    if [ ! -d "rootfs" ]; then
        mkdir rootfs
    fi
    cd rootfs
    log "Extracting ${FWFOLDER}/rootfs/${ROOTFS} into $(pwd)"
    # We really need --no-absolute-filenames as otherwise we may corrupt
    # our own filesystem...
    ${CPIO} -id --no-absolute-filenames > /dev/null 2>&1 < ../${ROOTFS}
    LINA=${FWFOLDER}/rootfs/asa/bin/lina
    LINA_MONITOR=${FWFOLDER}/rootfs/asa/bin/lina_monitor
    if [[ ! -z $LINABINDIR && -d $LINABINDIR ]]
    then
        mkdir ${LINABINDIR}/${FWFILE}
        cp ${LINA} ${LINABINDIR}/${FWFILE}/
        cp ${LINA_MONITOR} ${LINABINDIR}/${FWFILE}/
    fi
    cd .. # leave rootfs
    cd .. # leave ${FWFOLDER}

    # we need space here...
    if [[ "$KEEP_ROOTFS" == "YES" ]]
    then
        log "Keeping rootfs"
        # we only keep the rootfs directory which is not a regular file
        for F in $(find ${FWFOLDER} -maxdepth 1 -type f);
        do
            log "Deleting \"${F}\""
            rm -f "${F}"
        done
    fi
    if [[ "$DELETE_EXTRACTED" == "YES" ]]
    then
        log "Deleting extracted files"
        # We only delete folders of the following format _*.extracted
        # The reason we do that is we don't want to rm -Rf arbitrary
        # folders
        log "Deleting \"${FWFOLDER}\""
        rm -Rf ${FWFOLDER}
    fi
    if [[ "$DELETE_BIN" == "YES" ]]
    then
        log "Deleting original firmware bin"
        log "Deleting \"${FWFILE}\""
        rm ${FWFILE}
    fi
}

# unpack_repack_bin()
#
# Arguments:
#  None
#
# Required Globals:
#  FWFILE
#
# Notes:
#  Expects current folder being the dirname of $FWFILE
#
# Description:
#  Primary workhorse function. Will attempt to unpack, modify, and repack as
#  necessary.
##
unpack_repack_bin()
{
    if [[ "${UNPACK_ONLY}" == "YES" ]]
    then
        extract_bin
    else
        # root is needed so the repacked version has the right uid/gid
        if [ "$(whoami)" != "root" ]; then
            log "You need to be root so repacked version has the right uid/gid"
            log "NOTE: Use sudo -E if you sourced env.sh"
            exit 1
        fi
        unpack_bin

        # unpack_bin creates "work/" directory and extracts files into it
        modify_bin "work/"
        repack_bin "work/"
    fi
}

# unpack_bin()
#
# Arguments:
#  None
#
# Required Globals:
#  FWFILE
#
# Notes:
#  Expects current folder being the dirname of $FWFILE
#
# Description:
#  Extracts a .bin using our asafw bin.py script. Creates a 'work/' directory
#  which contains the extracted contenst of the rootfs.img
unpack_bin()
{
    log "unpack_bin: $FWFILE"
    INFILE=$(pwd)/${FWFILE}
    # get filename without extension and extension
    OUTFILE=$(basename "$FWFILE")
    EXTFILE=${FWFILE##*.}

    if [ ! -z ${FWFILE_WITH_ASA_TO_INJECT} ]
    then
        OUTFILE_PREFIX=${FWFILE_WITH_ASA_TO_INJECT}-in-${OUTFILE%.*}
    else
        OUTFILE_PREFIX=${OUTFILE%.*}
    fi
    OUTFILE_SUFFIX=
    if [[ "${SIMPLE_NAME}" != "YES" ]]; then
        # the more complex filename we could get is something like
        # "asaXXX-smp-k8-in-asa921-smp-k8-noaslr-debugshell-hooked-gdbserver.bin"
        if [[ "${DISABLE_ASLR}" == "YES" ]]
        then
            OUTFILE_SUFFIX=$OUTFILE_SUFFIX-noaslr
        fi
        if [[ "${DEBUGSHELL}" == "YES" ]]
        then
            OUTFILE_SUFFIX=$OUTFILE_SUFFIX-debugshell
        fi
        if [[ ! -z "${LINAHOOK}" ]]
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
    OUTFILE=${OUTDIR}/${OUTFILE_PREFIX}${OUTFILE_SUFFIX}

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
        log "ERROR: ${FWTOOL} -u -f "$INFILE" failed"
        exit 1
    fi
    ${GUNZIP} -c "$GZIP_ORIGINAL" > "$CPIO_ORIGINAL"
    if [ $? != 0 ];
    then
        log "ERROR: ${GUNZIP} -c $GZIP_ORIGINAL > $CPIO_ORIGINAL failed"
        exit 1
    fi
    rm -Rf work
    mkdir work
    cd work
    # We really need --no-absolute-filenames as otherwise we may corrupt
    # our own filesystem...
    ${CPIO} -id --no-absolute-filenames > /dev/null 2>&1 < "$CPIO_ORIGINAL"
    cd .. # leave work
}

# free_space()
#
# Arguments:
#  None
#
# Notes:
#  Expects $PWD to be an extracted rootfs directory
#
# Description:
#  Attempts to free room in the firmware by rm'ing unused large files. This is
#  done to accomodate patches or new files that might otherwise make the
#  rootfs.img.gz file larger than the original, which would prevent injection.
##
free_space()
{
    # free some space
    if [[ "$FREE_SPACE" == "YES" ]]
    then
        log "Freeing space in extracted .bin"
        rm -Rf usr/test/*
        if [[ -e 'usr/bin/qemu-system-x86_64' ]]; then
            rm usr/bin/qemu-system-x86_64 # 5.2 MB
        fi
        if [[ -e 'asa/html/dd/fdd.swf' ]]; then
            rm asa/html/dd/fdd.swf # 1.3 MB
        fi
    fi
}

# disable_aslr()
#
# Arguments:
#  None
#
# Notes:
#  Expects $PWD to be an extracted rootfs directory
#
# Description:
#  Configures the ASA kernel to disable ASLR. Useful for debugging 64-bit
#  systems.
##
disable_aslr()
{
    # disable ASLR
    # /etc/sysctl.conf -> /etc/sysctl.conf.props so we follow symlink otherwise it will modify our host one :/
    if [[ "$DISABLE_ASLR" == "YES" ]]
    then
        log "DISABLE ASLR"
        # we can't just add the following line
        #echo "kernel.randomize_va_space = 0" >> etc/sysctl.conf.procps
        # because it looks like rcS.common overrides our value later in the boot process
        # so we just make the modification in rcS.common :)

        # deal with case when no randomize_va_space in asa/scripts/rcS.common, such as asav9101.qcow2
        VASPACE=$(grep randomize_va_space "asa/scripts/rcS.common")
        DISABLE_ASLR_ARGS=
        if [ -n "$VASPACE" ]
        then
            sed -i 's/echo 2 > \/proc\/sys\/kernel\/randomize_va_space/echo 0 > \/proc\/sys\/kernel\/randomize_va_space/' asa/scripts/rcS.common
        else
            # use kernel parameter 'norandmaps' instead
            DISABLE_ASLR_ARGS=--disable-aslr
        fi
    fi
}

# enable_gdb()
#
# Arguments:
#  None
#
# Required Globals:
#   FWFILE - name of firmware bieng modified
#   FIRMWAREDIR - directory holding firmware images
#
# Notes:
#  Expects $PWD to be an extracted rootfs directory
#
# Description:
#  Enables gdb support in the current rootfs
##
enable_gdb()
{
    # enable gdb at boot
    if [[ "$ENABLE_GDB" == "YES" ]]
    then
        log "ENABLE GDB"
        if [[ "$FWFILE" == *"asa803"* ]]
        then
            log "Using asa803 ASA gdb patching method and patching serial port in lina_monitor"
            sed -i 's/\(\/asa\/bin\/lina_monitor\)/\1 -g -s \/dev\/ttyS0 -d/' etc/init.d/rcS
            # XXX - This assumption about the ${FIRMWAREDIR} contents is
            # error prone. If we require it, we should document it. We could
            # consider include thihs _asa803/lina_monitor_patched file in asafw
            cp ${FIRMWAREDIR}/_asa803/lina_monitor_patched $(pwd)/asa/bin/lina_monitor
        elif [[ "$FWFILE" == *"asa804"* ]]
        then
            # XXX - untested - do we need to patch lina_monitor too?
            log "Using asa804 ASA gdb patching method"
            sed -i 's/\(\/asa\/bin\/lina_monitor\)/\1 -g -s \/dev\/ttyS0 -d/' asa/scripts/rcS
        else
            log "Using recent ASA gdb patching method"
            sed -i 's/#\(.*\)ttyUSB0\(.*\)/\1ttyS0\2/' asa/scripts/rcS
            # Don't output anything on the tty, as this breaks gdb with some Linux kernel setups
            sed -i 's/ttyS0::once:\/tmp\/run_cmd/tty0::once:\/tmp\/run_cmd/' etc/inittab
        fi
    fi
}

# disable_gdb()
#
# Arguments:
#  None
#
# Required Globals:
#
# Notes:
#  Expects $PWD to be an extracted rootfs directory
#
# Description:
#  Disables GDB in the current rootfs.
##
disable_gdb()
{
    # disable gdb at boot
    if [[ "$DISABLE_GDB" == "YES" ]]
    then
        log "DISABLE GDB"
        sed -i 's/echo\(.*\)ttyUSB0\(.*\)/#echo\1ttyS0\2/' asa/scripts/rcS
    fi
}

# fix_gns3_interface()
#
# Arguments:
#  None
#
# Required Globals:
#  None
#
# Notes:
#  Expects $PWD to be an extracted rootfs directory
#
# Description:
#  XXX - Think this was going to be for fixing interfaces for emulated 32-bit
#  firmwares. We can probably remove it
##
fix_gns3_interface()
{
    # fix GNS3 network interface
    if [[ "$FIX_GNS3_INTERFACE" == "YES" ]]
    then
        log "FIXING GNS3 INTERFACE"
        log "ERROR: Not implemented yet"
        #sed -i 's/echo\(.*\)ttyUSB0\(.*\)/#echo\1ttyS0\2/' asa/scripts/rcS
    fi
}

# inject_gdb()
#
# Arguments:
#  None
#
# Required Globals:
#  FWFILE      - name of current firmware being worked on
#  FIRMWAREDIR - directory holding collection of firmware
#
# Notes:
#  Expects $PWD to be an extracted rootfs directory
#  XXX - Makes undocumented assumptions about FIRMWAREDIR layout that will
#        sometimes break. We should include those gdb files in asafw repo and
#        copy them from somewhere static
#
# Description:
#  Injects a gdbserver binary from a separate firmware in FIRMWAREDIR into the
#  firmware being worked on. This is relative only to 64-bit ASA images or old
#  32-bit ASA devices.
##
inject_gdb()
{
    # inject gdbserver from other firmware
    if [[ "$INJECT_GDB" == "YES" ]]
    then
        if [[ -e 'usr/bin/gdbserver' ]]; then
            log "WARNING: This firmware already has a gdbserver."
            log "WARNING: Injecting another gdbserver might cause issues."
            log "WARNING: Injecting is only relevant to 64-bit ASA or really old 32-bit ASA devices"
            log "WARNING: Are you sure?  (ctrl-c if not. enter if yes)"
            read CMD
        fi
        log "INJECT OTHER GDB"
        if [[ "$FWFILE" == *"asa803"* ]]; then
            FIRMWARE_WITH_GDB="asa924-k8.bin"
        else
            FIRMWARE_WITH_GDB="asa931-smp-k8.bin"
        fi
        log "Using gdbserver from ${FIRMWARE_WITH_GDB}"
        if [ ! -d "${FIRMWAREDIR}/_${FIRMWARE_WITH_GDB}.extracted" ]; then
            log "Didn't find ${FIRMWAREDIR}/_${FIRMWARE_WITH_GDB}.extracted"
            log "Need to binwalk ${FIRMWARE_WITH_GDB} to allow file stealing"
            if [ ! -e "${FIRMWAREDIR}/${FIRMWARE_WITH_GDB}" ]; then
                log "ERROR: Can't find ${FIRMWAREDIR}/${FIRMWARE_WITH_GDB} so can't binwalk it"
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
}

# inject_asa_folder()
#
# Arguments:
#  None
#
# Required Globals:
#  FWFILE_WITH_ASA_TO_INJECT - custom firmware to take /asa from
#  FWFILE      - name of current firmware being worked on to inject new /asa (needs to be asa921-*.bin)
#  FIRMWAREDIR - directory holding collection of firmware
#
# Notes:
#  Expects $PWD to be an extracted rootfs directory
#
# Description:
#  Injects an /asa/ folder from a separate firmware in FIRMWAREDIR into the
#  firmware being worked on.
#
#  Firmware older than 921 have their gdb broken so we could not debug them :(
#  Workaround is to use the asa921-k8.bin or asa921-smp-k8.bin as a container and inject the asa/
#  folder from the older firmware in order to be able to debug it
##
inject_asa_folder()
{
    if [ ! -z ${FWFILE_WITH_ASA_TO_INJECT} ]
    then
        log "INJECT OTHER ASA FOLDER"
        if [[ "$FWFILE" == *"asa921"* ]]; then
            log "Using ${FWFILE} as container to inject /asa from ${FWFILE_WITH_ASA_TO_INJECT}"
        else
            log "ERROR: ${FWFILE} is not supported as container to inject /asa from ${FWFILE_WITH_ASA_TO_INJECT}. You need either asa921-k8.bin or asa921-smp-k8.bin"
            exit 1
        fi
        log "Checking ${FWFILE_WITH_ASA_TO_INJECT}"
        if [ ! -d "${FIRMWAREDIR}/_${FWFILE_WITH_ASA_TO_INJECT}.extracted" ]; then
            log "Didn't find ${FIRMWAREDIR}/_${FWFILE_WITH_ASA_TO_INJECT}.extracted"
            log "Need to binwalk ${FWFILE_WITH_ASA_TO_INJECT} to allow file stealing"
            if [ ! -e "${FIRMWAREDIR}/${FWFILE_WITH_ASA_TO_INJECT}" ]; then
                log "ERROR: Can't find ${FIRMWAREDIR}/${FWFILE_WITH_ASA_TO_INJECT} so can't binwalk it"
                exit 1
            fi
            LASTDIR=$(pwd)
            cd ${FIRMWAREDIR}
            ${BINWALK} -e ${FWFILE_WITH_ASA_TO_INJECT}
            cd ${LASTDIR}
        fi
        log "Using /asa from ${FWFILE_WITH_ASA_TO_INJECT}"
        rm -Rf ./asa
        CMD="cp -Rf ${FIRMWAREDIR}/_${FWFILE_WITH_ASA_TO_INJECT}.extracted/rootfs/asa ."
        ${CMD}
        if [ $? != 0 ];
        then
            log "ERROR: '${CMD}' failed"
            exit 1
        fi
    fi
}

# replace_lina_monitor()
#
# Arguments:
#  None
#
# Required Globals:
#
# Notes:
#  Expects $PWD to be an extracted rootfs directory
##
replace_lina_monitor()
{
    if [[ ! -z "${REPLACE_LINAMONITOR}" ]]
    then
        log "REPLACING LINA_MONITOR"
        cp ${REPLACE_LINAMONITOR} asa/bin/lina_monitor
    fi
}

# inject_debugshell()
#
# Arguments:
#  None
#
# Required Globals:
#
# Notes:
#  Expects $PWD to be an extracted rootfs directory
##
inject_debugshell()
{
    # On ASAv 64-bit, patching in a debugshell to lina has the implicit requirement
    # of patching lina_monitor to bypass boot verification of lina.
    if [[ "$DEBUGSHELL" == "YES" ]]
    then
        FWFILE_WITH_ASA=${FWFILE}
        if [ ! -z ${FWFILE_WITH_ASA_TO_INJECT} ]
        then
            FWFILE_WITH_ASA=${FWFILE_WITH_ASA_TO_INJECT}
            log "debug shell: overriding firmware with ${FWFILE_WITH_ASA} to patch lina correctly"
        fi

        ADDITIONAL_ARGS=""
        if [[ ! -z "${LINAHOOK}" ]]
        then
            ADDITIONAL_ARGS="--hook ${LINAHOOK}"
        fi
        CBPORT="4444"
        if [[ "$FWFILE_WITH_ASA" == *"asav"* ]]
        then
            log "debug shell: using 64-bit ASAv firmware"
            CBHOST=${ATTACKER_GNS3}
        else
            log "debug shell: using 32-bit / 64-bit firmware for real hardware"
            CBHOST=${ATTACKER_ASA}
        fi
        log "Adding debug shell for $CBHOST:$CBPORT"
        # If it is a 32-bit firmware, it should not contain the lib64 path so
        # it is safe to search in this order
        LIBC=$(find ${PWD} -regex ".*/lib64/libc.so.6")
        if [[ "$LIBC" == "" ]]
        then
            LIBC=$(find ${PWD} -regex ".*/lib/libc.so.6")
        fi
        # NOTE: we pass as many arguments as possible to LINA_LINUXSHELL and it is up to that script to know
        #       if libc is used for malloc()/etc. and if lina_monitor needs to be patched.
        CMD="${LINA_LINUXSHELL} -b ${FWFILE_WITH_ASA} -F ${PWD}/asa/bin/lina_monitor -O ${PWD}/asa/bin/lina_monitor -f ${PWD}/asa/bin/lina -o ${PWD}/asa/bin/lina -c $CBHOST -p $CBPORT -d ${ASADBG_DB} ${ADDITIONAL_ARGS} --libc-input ${LIBC} --libc-output ${LIBC}"

        log "Using command: '${CMD}'"
        # XXX - fix fact that we use -b to specify the bin_name but it would not work if the name is not one of the original Cisco ones (such as asa924-k8.bin)
        ${CMD}

        if [ $? != 0 ];
        then
            log "ERROR: '${CMD}' failed"
            exit 1
        fi
    fi
}

# setup_serialshell()
#
# Arguments:
#  None
#
# Required Globals:
#
# Notes:
#  Expects $PWD to be an extracted rootfs directory
#
# Description
#  This setups a Linux shell on 2nd serial. E.g. add this to qemu options in GNS3: ASAv instance > Configure
#  then Advanced settings > Additional settings: "-serial telnet:127.0.0.1:15002,server,nowait"
#
#  Tested with asav962-7.qcow2
##
setup_serialshell()
{
    if [[ "$SERIALSHELL" == "YES" ]]
    then

        FWFILE_WITH_ASA=${FWFILE}
        if [ ! -z ${FWFILE_WITH_ASA_TO_INJECT} ]
        then
            FWFILE_WITH_ASA=${FWFILE_WITH_ASA_TO_INJECT}
            log "serial shell: overriding firmware with ${FWFILE_WITH_ASA} to patch rcS correctly"
        fi

        if [[ "$FWFILE_WITH_ASA" == *"asav"* ]]
        then
            sed -i '/# regular startup/i # serial shell specifics' asa/scripts/rcS

            # we redirect stdin/out/err to the 2nd serial
            # bashrc does not seem to be loaded automatically so we force it to load with --rcfile
            log "Exposing a Linux shell on 2nd serial (GNS3 only?)"
            sed -i '/# regular startup/i \/bin\/bash --rcfile \/root\/bashrc < \/dev\/ttyS1 > \/dev\/ttyS1 2> \/dev\/ttyS1 &' asa/scripts/rcS

            # Not working properly yet so needs to be executed manually
            #log "Starting lina at boot"
            #sed -i 's/echo "$CGEXEC \/asa\/bin\/lina_monitor.*"/    echo "\/asa\/scripts\/lina_start.sh"/' asa/scripts/rcS
            log "Not starting lina at boot"
            sed -i 's/echo "$CGEXEC \/asa\/bin\/lina_monitor.*"/echo ""/' asa/scripts/rcS

            # Avoids reaching the end of rcS script which triggers a reboot
            #sed -i '/# Explicitly call reboot here for consistency across target rcS files/a echo "while true; do echo in while true loop; sleep 1; done" >> \/tmp\/run_cmd' asa/scripts/rcS
            sed -i '/# Explicitly call reboot here for consistency across target rcS files/a echo "read -p \\"[asafw] Press enter to reboot\\"" >> \/tmp\/run_cmd' asa/scripts/rcS
        else
            log "Not starting lina at boot"
            sed -i 's/echo "$CGEXEC \/asa\/bin\/lina_monitor.*"/echo "echo \\"[asafw run_cmd] Not starting lina at boot\\""/' asa/scripts/rcS

            log "Skipping setting baudrate on /dev/ttyUSB0 in serial_init"
            sed -i 's/   if \[ -e \/dev\/ttyUSB0 \]; then stty -F \/dev\/ttyUSB0 115200; fi/   echo "[asafw serial_init] Skipping setting baudrate on \/dev\/ttyUSB0"/' asa/scripts/serial_init

            # XXX - does not work yet - spawning the shell after resets that :( so may need to be done manually anyway
            #log "Adding sourcing bashrc before spawning shell"
            #sed -i '/echo "\/sbin\/reboot -d 3"/i echo "[asafw rcS] Sourcing bashrc"' asa/scripts/rcS
            #sed -i '/echo "\/sbin\/reboot -d 3"/i source /root/bashrc' asa/scripts/rcS

            log "Spawning shell at the end of rcS"
            sed -i '/echo "\/sbin\/reboot -d 3"/i echo "[asafw rcS] End of rcS reached, spawning a shell instead"' asa/scripts/rcS
            sed -i '/echo "\/sbin\/reboot -d 3"/i \/bin\/sh < \/dev\/ttyS0 > \/dev\/ttyS0 2> \/dev\/ttyS0 &' asa/scripts/rcS

            log "Not rebooting in /tmp/run_cmd"
            sed -i 's/echo "\/sbin\/reboot -d 3"/echo "echo \\"[asafw run_cmd] Do nothing instead of rebooting\\""/' asa/scripts/rcS
        fi

        declare -a scripts_list=("lstart.sh" "ldebug.sh" "lattach.sh" "lkill.sh" "lclean.sh" "ltrap.sh")
        for file in "${scripts_list[@]}"
        do
            log "Copying ${file} script"
            CMD="cp ${TOOLDIR}/binfs/${file} asa/scripts/${file}"
            ${CMD}
            if [ $? != 0 ];
            then
                log "ERROR: '${CMD}' failed"
                exit 1
            fi
            CMD="chmod +x asa/scripts/${file}"
            ${CMD}
            if [ $? != 0 ];
            then
                log "ERROR: '${CMD}' failed"
                exit 1
            fi
        done

        file="bashrc"
        log "Copying ${file} script"
        CMD="cp ${TOOLDIR}/binfs/${file} root/${file}"
        ${CMD}
        if [ $? != 0 ];
        then
            log "ERROR: '${CMD}' failed"
            exit 1
        fi
        CMD="chmod +x root/${file}"
        ${CMD}
        if [ $? != 0 ];
        then
            log "ERROR: '${CMD}' failed"
            exit 1
        fi
    fi
}

# custom()
#
# Arguments:
#  None
#
# Required Globals:
#
# Notes:
#  Expects $PWD to be an extracted rootfs directory
#
# Description
#  This function is for testing or doing whatever you want if you want to test
#  making modifications, etc.
##
custom()
{
    # custom: can be used for testing purpose before we add something useful as a real command line option
    if [[ "$CUSTOM" == "YES" ]]
    then
        log "DOING CUSTOM STUFF: fill it yourself :)"
        # ...
    fi
}


# cleanup()
#
# Arguments:
#  None
#
# Referenced Globals:
#  GZIP_ORIGINAL    - set only by unpack_bin
#  CPIO_ORIGINAL    - set only by unpack_bin
#  GZIP_MODIFIED    - set by unpack_bin and repack_bin
#  VMLINUZ_ORIGINAL - set only by unpack_bin
#
# Notes:
#  Expects $PWD to be an extracted rootfs directory
#
# Description
#  This function deletes unneeded files generated by various tools. It is okay
#  if some of the reference globals having been set
##
cleanup()
{
    # cleanup
    if [[ "$NO_CLEANUP" == "NO" ]]
    then
        log "CLEANUP"
        dbglog "Removing $GZIP_ORIGINAL $CPIO_ORIGINAL $GZIP_MODIFIED $VMLINUZ_ORIGINAL"
        rm $GZIP_ORIGINAL $CPIO_ORIGINAL $GZIP_MODIFIED $VMLINUZ_ORIGINAL
    fi
}

# modify_bin()
#
# Arguments:
#   $1 (required) - working directory
#
# Required Globals:
#
# Notes:
#    Modify extracted files (typically the files from the ramdisk)
#    in preparation for later repacking.
#
#    Most functionality is influenced by command-line arguments.
##
modify_bin()
{
    log "modify_bin: $FWFILE"

    # Enter rootfs folder told to us
    dbglog "Entering ${1}"
    OLDDIR=${PWD}
    cd ${1}

    inject_asa_folder # early so all other modifications are done on the right /asa files
    disable_aslr
    enable_gdb
    disable_gdb
    fix_gns3_interface
    free_space
    inject_gdb
    replace_lina_monitor
    inject_debugshell
    setup_serialshell
    custom

    # Return to original folder
    dbglog "Returning to ${OLDDIR}"
    cd ${OLDDIR}
}

# repack_bin()
#
# Arguments:
#  $1 (required) - working directory
#  $2 (optional) - output filename of repacked bin we'll create
#  $3 (optional) - original firmware file from which this file was taken
#
# Globals Required:
#   CPIO
#
# Notes:
#  If $2 is specified, then $3 must also be specified.
#
# TODO:
#  - It would be nice if we just derive $3 from $1
#  - Instead of inferring GZIP_MODIFIED, OUTFILE and FWFILE based on arg count,
#    we could just have them passed.
##
repack_bin()
{
    # Enter working directory. Usually either work/ or <extracted dir>/rootfs/
    OLDDIR=${PWD}
    dbglog "Entering ${1}"
    cd $1

    if [[ $# > 1 ]]; then
        log "beep"
        # If we get additional args it means we are repacking an extracted
        # directory and unpack_bin wasn't called. That means we have to set
        # these ourself
        OUTFILE="${2}"
        FWFILE="${3}"
        GZIP_MODIFIED="${PWD}/../rootfs.img.gz"
    fi

    log "repack_bin: $FWFILE"
    find . | ${CPIO} -o -H newc 2>/dev/null | gzip > "$GZIP_MODIFIED"

    # Leave working directory
    dbglog "Returning to ${OLDDIR}"
    cd ${OLDDIR}
#    cd ..
    #ls -l *.gz

    if [[ "${ROOT}" == "YES" ]]
    then
        ROOTARGS=--root
    else
        ROOTARGS=
    fi
    dbglog ${FWTOOL} -r -f "$FWFILE" -g "$GZIP_MODIFIED" -o "$OUTFILE" $ROOTARGS $DISABLE_ASLR_ARGS
    ${FWTOOL} -r -f "$FWFILE" -g "$GZIP_MODIFIED" -o "$OUTFILE" $ROOTARGS $DISABLE_ASLR_ARGS
    if [ $? != 0 ];
    then
        log "${FWTOOL} -r -f "$FWFILE" -g "$GZIP_MODIFIED" -o "$OUTFILE" $ROOTARGS $DISABLE_ASLR_ARGS failed"
        exit 1
    fi

    echo -n "[unpack_repack_bin] MD5: "
    md5sum "${OUTFILE}"
    cleanup
}

# START OF EXECUTION

if [ -z "${ASATOOLS}" ]; then
    log "This tool relies on env.sh which has not been sourced"
    log "NOTE: Use sudo -E if you already sourced env.sh"
    exit 1
fi

BINWALK=$(which binwalk)
if [ -z "${BINWALK}" ]; then
    log "ERROR: binwalk not found. Required for extract_repack_bin.sh usage"
    log "ERROR: NOTE: binwalk must be > v2.0"
    exit 1
fi
GUNZIP=gunzip
CPIO=cpio

# http://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash
# XXX - Could switch this to an associative array and pass it around instead
#       of relying on globals
INPUT=
OUTDIR=
OUTBIN=
FREE_SPACE="NO"
ENABLE_GDB="NO"
DISABLE_GDB="NO"
ENABLE_ASLR="NO"
DISABLE_ASLR="NO"
INJECT_GDB="NO"
CUSTOM="NO"
NO_CLEANUP="NO"
DEBUGSHELL="NO"
SERIALSHELL="NO"
LINAHOOK=
ROOT="NO"
LINABINDIR=
DELETE_EXTRACTED="NO"
KEEP_ROOTFS="NO"
DELETE_BIN="NO"
UNPACK_ONLY="NO"
SIMPLE_NAME="NO"
REPACK_ONLY="NO"
ORIGINAL_FIRMWARE=
REPLACE_LINAMONITORITOR=
DEBUG=
FWFILE_WITH_ASA_TO_INJECT=
while [[ $# -gt 0 ]]
do
    key="$1"

    case $key in
        -i|--input)
            # Input firmware directory or file
            INPUTFW="$2"
            shift # past argument
            ;;
        -o|--output)
            OUTDIR="$2"
            shift # past argument
            ;;
        --output-bin)
            OUTBIN="$2"
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
        --bin-with-asa-to-inject)
            FWFILE_WITH_ASA_TO_INJECT="$2"
            shift
            ;;
        -b|--debug-shell)
            DEBUGSHELL="YES"
            ;;
        -B|--serial-shell)
            SERIALSHELL="YES"
            ;;
        -H|--lina-hook)
            LINAHOOK="$2"
            shift
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
            log "Created ${LINABINDIR} directory"
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
        -R|--repack-only)
            REPACK_ONLY="YES"
            # root is needed so the repacked version has the right uid/gid
            if [ "$(whoami)" != "root" ]; then
                log "You need to be root so repacked version has the right uid/gid"
                log "NOTE: Use sudo -E if you sourced env.sh"
                exit 1
            fi
            ;;
        --original-firmware)
            ORIGINAL_FIRMWARE="$2"
            shift # past argument
            ;;
        --replace-linamonitor)
            REPLACE_LINAMONITOR="$2"
            if [[ ! -e ${REPLACE_LINAMONITOR} ]]
            then
                log "ERROR: --replace-linamonitor file ${REPLACE_LINAMONITOR} not found"
                exit
            fi
            shift # past argument
            ;;
        -v|--verbose)
            DEBUG="-v"
            ;;
        -h|--help)
            usage
            ;;
        *)
            # unknown option
            log "ERROR: Unknown option provided: $key"
            usage
            ;;
    esac
    shift # past argument or value
done

if [[ -z $INPUTFW || ! -e $INPUTFW ]]
then
    log "ERROR: You must specify at least a valid --input (-i) argument"
    usage
fi

if [[ -d $INPUTFW && -z $OUTDIR && -z $OUTBIN && "${UNPACK_ONLY}" == "NO" ]]
then
    log "ERROR: You must specify an output directory with --output (-o) when specifying a directory with --input (-i)"
    usage
fi

if [[ ! -z $OUTDIR && "${UNPACK_ONLY}" == "YES" ]]
then
    log "ERROR: --output (-o) is ignored if --unpack-only (-u) is specified"
    usage
fi

if [[ -f $INPUTFW && ! -z $OUTDIR ]]
then
    log "ERROR: --output (-o) is ignored if --input (-i) is a file"
    usage
fi

if [[ -f $INPUTFW && ${REPACK_ONLY} == "YES" ]]
then
    log "ERROR: --repack-only requires --input to be an unpacked firmware directory"
    usage
fi

if [[ ! -z "${LINAHOOK}" && "${DEBUGSHELL}" == "NO" ]]
then
    log "ERROR: Use of --lina-hook (-H) currently requires --debug-shell (-b)"
    usage
fi

# When --repack-only is used, $INPUTFW is a directory but not one we loop over, so
# won't enter here.
if [ -d $INPUTFW ] && [[ ${REPACK_ONLY} == "NO" ]]
then
    log "Directory of firmware detected: $INPUTFW"
    ORIGDIR=${PWD}
    cd ${INPUTFW}
    for FWFILE2 in $(find . -maxdepth 1 -type f -name "*.bin");
    do
        # strip "./" in front of the file
        FWFILE=$(basename "${FWFILE2}")
        unpack_repack_bin
    done
    cd ${ORIGDIR}
elif [ -f ${INPUTFW} ]
then
    log "Single firmware detected"
    ORIGDIR=${PWD}
    OUTDIR=$(dirname ${INPUTFW})
    FWFILE=$(basename "${INPUTFW}")
    WORKINGDIR=$(dirname "${INPUTFW}")
    dbglog "Entering ${WORKINGDIR}"
    cd ${WORKINGDIR}
    unpack_repack_bin
    if [[ ${PWD} != $WORKINGDIR ]]; then
        dbglog "WARNING: unpack_repack_bin failed to restore working directory"
    fi

    dbglog "Entering ${ORIGDIR}"
    cd ${ORIGDIR}
elif [[ ${REPACK_ONLY} == "YES" ]]
then
    log "Single unpacked firmware detected"
    if [[ -z ${OUTBIN} ]]; then
        log "ERROR: --repack-only requires --output-bin <bin name>"
        usage
    fi
    if [[ -z ${ORIGINAL_FIRMWARE} ]]; then
        log "ERROR: --repack-only requires --original-firmware <bin name>"
        usage
    fi
    ROOTFS_DIR=${INPUTFW}/rootfs
    if [ -d ${ROOTFS_DIR} ]
    then
        log "ERROR: No ${ROOTFS_DIR} directory found"
        log "ERROR: Bad firmware directory for --repack-only"
        exit
    fi

    ORIGDIR=${PWD}
    modify_bin ${ROOTFS_DIR}
    repack_bin ${ROOTFS_DIR} ${OUTBIN} ${ORIGINAL_FIRMWARE}

    # We expect modify_bin and repack_bin not screw with our path. This just
    # warns about possible bugs being introduced
    if [[ ${PWD} != $ORIGDIR ]]; then
        dbglog "WARNING: modify_bin or repack_bin failed to restore working directory"
    fi
    cd ${ORIGDIR}
fi
