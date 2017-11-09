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
    echo "      -m, --inject-gdb             Inject gdbserver to run"
    echo "      -b, --debug-shell            Inject ssh-triggered debug shell"
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
    echo "      -v, --verbose                Display debug messages"
    echo "Examples:"
    echo " # Unpack and repack a firmware file, freeing space, enabling gdb, and injecting gdbserver bin. Output modifications to firmware_repacked fir" 
    echo " ./unpack_repack_bin.sh -i /home/user/firmware -o /home/user/firmware_repacked --free-space --enable-gdb --inject-gdb"
    echo " # Unpack and repack a firmware file, freeing space, enabling gdb, and injecting gdbserver bin" 
    echo " ./unpack_repack_bin.sh -i /home/user/firmware/asa961-smp-k8.bin -f -g -m"
    echo " # Unpack a firmware file and copy the lina and lina_monitor file in to linabins dir"
    echo " ./unpack_repack_bin.sh -u -i /home/user/firmware -l /home/user/linabins"
    echo " # Unpack a firmware file and keep the rootfs on disk for analysis"
    echo " ./unpack_repack_bin.sh -u -i /home/user/firmware/asa924-k8.bin -k"
    echo " # Repack an already unpacked firmware dir, freeing space and patching lina_monitor to bypass checksum validation"
    echo " ./unpack_repack_bin.sh --repack-only -i _asa924-smp-k8.bin.extracted --output-bin asa924-smp-k8-repacked.bin --original-firmware /home/user/firmware/asa924-smp-k8.bin --free-space --replace-linamonitor /home/user/firmware/lina_monitor_patched"
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

    OUTFILE_SUFFIX=
    if [[ "${SIMPLE_NAME}" != "YES" ]]; then
        # the more complex filename we could get is something like
        # "asaXXX-smp-k8-noaslr-debugshell-hooked-gdbserver.bin"
        if [[ "${DISABLE_ASLR}" == "YES" ]] 
        then
            OUTFILE_SUFFIX=$OUTFILE_SUFFIX-noaslr
        fi
        if [[ "${DEBUGSHELL}" == "YES" ]] 
        then
            OUTFILE_SUFFIX=$OUTFILE_SUFFIX-debugshell
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
        log "ERROR: ${FWTOOL} -u -f "$INFILE" failed"
        exit 1
    fi
    ${GUNZIP} -c "$GZIP_ORIGINAL" > "$CPIO_ORIGINAL"
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
        sed -i 's/echo 2 > \/proc\/sys\/kernel\/randomize_va_space/echo 0 > \/proc\/sys\/kernel\/randomize_va_space/' asa/scripts/rcS.common
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
            log "Using old ASA gdb patching method and patching serial port in lina_monitor"
            sed -i 's/\(\/asa\/bin\/lina_monitor\)/\1 -g -s \/dev\/ttyS0 -d/' etc/init.d/rcS
            # XXX - This assumption about the ${FIRMWAREDIR} contents is
            # error prone. If we require it, we should document it. We could
            # consider include thihs _asa803/lina_monitor_patched file in asafw
            cp ${FIRMWAREDIR}/_asa803/lina_monitor_patched $(pwd)/asa/bin/lina_monitor
        else
            log "Using recent ASA gdb patching method"
            sed -i 's/#\(.*\)ttyUSB0\(.*\)/\1ttyS0\2/' asa/scripts/rcS
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
        ADDITIONAL_ARGS=""
        if [[ "${LINAHOOK}" == "YES" ]]
        then
            ADDITIONAL_ARGS="--hook"
        fi
        CBPORT="4444"
        if [[ "$FWFILE" == *"asav"* ]]
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
        CMD="${LINA_LINUXSHELL} -b ${FWFILE} -F ${PWD}/asa/bin/lina_monitor -O ${PWD}/asa/bin/lina_monitor -f ${PWD}/asa/bin/lina -o ${PWD}/asa/bin/lina -c $CBHOST -p $CBPORT -d ${ASADBG_DB} ${ADDITIONAL_ARGS} --libc-input ${LIBC} --libc-output ${LIBC}"

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

    disable_aslr
    enable_gdb
    disable_gdb
    fix_gns3_interface
    free_space
    inject_gdb
    replace_lina_monitor
    inject_debugshell
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
    dbglog ${FWTOOL} -r -f "$FWFILE" -g "$GZIP_MODIFIED" -o "$OUTFILE" $ROOTARGS
    ${FWTOOL} -r -f "$FWFILE" -g "$GZIP_MODIFIED" -o "$OUTFILE" $ROOTARGS
    if [ $? != 0 ];
    then
        log "${FWTOOL} -r -f "$FWFILE" -g "$GZIP_MODIFIED" -o "$OUTFILE" $ROOTARGS failed"
        exit 1
    fi

    echo -n "[unpack_repack_bin] MD5: "
    md5sum "${OUTFILE}"
    cleanup
}

# START OF EXECUTION

if [ -z "${ASATOOLS}" ]; then
    log "This tool relies on env.sh which has not been sourced"
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
LINAHOOK="NO"
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

if [[ -d $INPUTFW && -z $OUTDIR && -z $OUTBIN ]]
then
    log "ERROR: You must specify an output directory with --output (-o) when specifying a directory with --input (-i)"
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

if [[ "${LINAHOOK}" == "YES" && "${DEBUGSHELL}" == "NO" ]]
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
    for FWFILE in $(find . -name "*.bin" -maxdepth 0 -type f);
    do
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
