#!/bin/bash
#
# This file is part of asafw.
# Copyright (c) 2017, Aaron Adams <aaron.adams(at)nccgroup(dot)trust>
# Copyright (c) 2017, Cedric Halbronn <cedric.halbronn(at)nccgroup(dot)trust>
#
# Display/save mitigations and additional info for all firmware in the current folder
# It is responsible for finding info/mitigations but relies on info.py to do the actual
# saving in a JSON database.

usage()
{
    echo Display/save mitigations and additional info for all firmware in the current folder
    echo Usage: info.sh [--save-result --db-name \<json_db\>]
    exit
}

SAVE_RESULTS="NO"
DBNAME=
while [ $# -gt 0 ]
do
    key="$1"
    case $key in
        -s|--save-result)
        SAVE_RESULTS="YES"
        ;;
        -d|--db-name)
        DBNAME="$2"
        shift
        ;;
        -h|--help)
        usage
        ;;
        *)
        # unknown option
        echo "[!] Unknown option provided"
        usage
        ;;
    esac
    shift
done

if [[ $SAVE_RESULTS == "YES" && "$DBNAME" == "" ]]
then
    echo You must specify a dbname when trying to save results
    usage
fi

get_bin_name()
{
    BIN=$(echo $1 | sed -e 's/.\/_\(asa.*.bin\).*/\1/')
    if [ "$1" == "${BIN}" ]; then
        BIN=$(echo $1 | sed -e 's/.\/_\(asa.*.SPA\).*/\1/')
        if [ "$1" == "${BIN}" ]; then
            BIN=$(echo $1 | sed -e 's/.\/_\(asav.*.qcow2\).*/\1/')
            if [ "$1" == "${BIN}" ]; then
                echo "[info.sh] Error: Cound not find asa*.bin or asav*.qcow2 or asa*.SPA. Skipping"
                return 1
            fi
        fi
    fi
    return 0
}
    
# vmlinuz is automatically extracted by binwalk and has a name representing its offset from the .bin (in hex)
# we are going to try other files too but none of them will have a "Linux version" so we should be safe :)
for VMLINUZ in $(find . -mindepth 2 -maxdepth 2 -regex ".*/[0-9A-F]+"); do
    get_bin_name ${VMLINUZ}
    if [ $? != 0 ]; then
        continue
    fi
    UNAME=$(strings ${VMLINUZ}|grep "Linux version")
    if [ -z "$UNAME" ]; then
        echo "[!] ${BIN} : No detected uname in ${VMLINUZ}. Skipping"
    fi

    if [[ "$SAVE_RESULTS" == "YES" ]]
    then
        info.py -i "${BIN}" -u "${UNAME}" -d "${DBNAME}"
    else
        echo -e "${BIN}: ${UNAME}"
    fi
done

for DIR in $(find . -type d -name "rootfs"); do
    get_bin_name $DIR
    if [ $? != 0 ]; then
        continue
    fi
    if [ ! -e "${DIR}/asa/bin/lina" ]; then
        echo "[!] ${BIN} : No lina binary found. Skipping"
        continue
    fi

    RESULT=$(checksec.sh --file "${DIR}/asa/bin/lina" | grep lina)
    # lina stripped?
    FILE=$(file "${DIR}/asa/bin/lina")
    if [ -z "${FILE##*not stripped*}" ]; then
#        STRIPPED="\033[32Stripped"
        STRIPPED="Stripped"
    else
#        STRIPPED="\033[31Not Stripped"
        STRIPPED="Not Stripped"
    fi
    if [ -z "${FILE##*x86-64*}" ]; then
        ARCH="64-bit"
    else
        ARCH="32-bit"
    fi
    # even a stripped binary can have exported symbols in .dynsym symbol table
    # 931200 contains an exported symbol with "lina" but actually does not contain 
    # any real other exported symbol so we use "ikev1" instead
    SYMBOLS=$(readelf -s "${DIR}/asa/bin/lina" | grep ikev1)
    SYMBOLSCNT=$(readelf -s "${DIR}/asa/bin/lina" | grep .dynsym)
    if [ -z "${SYMBOLS}" ]; then
        SYMBOLS="No symbol table"
    else
        SYMBOLS="Contains symbol table"
    fi
    # XXX - support dwarf symbols which is another symbol table than .dynsym?
    if [[ -e "${DIR}/asa/scripts/rcS.common" ]]; then
        VASPACE=$(grep va_space "${DIR}/asa/scripts/rcS.common")
    else
        # Old init script (e.g. 8.0.3)
        VASPACE=$(grep va_space "${DIR}/etc/init.d/rcS")
    fi
    if [ -z "${VASPACE##*echo 0*}" ]; then
#ASLR="\033[31ASLR Disabled"
        ASLR="ASLR Disabled"
    else
#        ASLR="\033[32ASLR Enabled"
        ASLR="ASLR Enabled"
    fi
    LIBC=$(find ${DIR} -regex ".*libc-.*\.so.*")
    if [[ "$LIBC" == "" ]]; then
        # Old ASA don't have a libc-<version>.so so we need to looks at strings in libc.so
        LIBC="${DIR}/lib/libc.so.6"
        LIBC=$(strings $LIBC | grep -i "GNU C Library stable release version")
    else
        LIBC=$(basename "$LIBC")
    fi
    
    grep "(next == m->top || cinuse(next))" "${DIR}/asa/bin/lina"
    if [[ $? -eq 0 ]]; then
        HEAP_LINA="dlmalloc 2.8.3"
    else
    grep "((unsigned long)((char\*)top + top_size)" "${DIR}/asa/bin/lina"
    if [[ $? -eq 0 ]]; then
        HEAP_LINA="dlmalloc 2.6.x"
    fi
    fi

    BUILD_DATE=$(strings -w "${DIR}/asa/bin/lina" | grep "PIX (")

    if [[ "$SAVE_RESULTS" == "YES" ]]
    then
        info.py -i "${BIN}" -u "\"${RESULT} ${STRIPPED} ${ASLR} ${SYMBOLS} ${LIBC} ${ARCH} ${HEAP_LINA}\"" -b "${BUILD_DATE}" -d "${DBNAME}"
    else
        echo -e "${BIN}: ${RESULT} ${STRIPPED} ${ASLR} ${SYMBOLS} ${SYMBOLSCNT} ${LIBC} ${ARCH} ${HEAP_LINA} ${BUILD_DATE}"
    fi

done
