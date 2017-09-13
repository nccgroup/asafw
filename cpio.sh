#!/bin/bash
#
# This file is part of asafw.
# Copyright (c) 2017, Aaron Adams <aaron.adams(at)nccgroup(dot)trust>
# Copyright (c) 2017, Cedric Halbronn <cedric.halbronn(at)nccgroup(dot)trust>
#
# Main script to deal with a rootfs extracted from a firmware

usage()
{
    echo "-c  Create cpio image"
    echo "-d  Directory to turn into cpio image"
    echo "-e  Extract cpio image"
    echo "-o  Output file"
    echo "Examples:"
    echo "Create ./cpio.sh -c -d rootfs -o rootfs.img"
    echo "Extract ./cpio.sh -e -i rootfs.img"
}

CREATE=
EXTRACT=
OUTPUT=
DIR=
CPIOFILE=
while [ $# -gt 0 ]
do
    key="$1"

    case $key in
        -c|--create)
        CREATE="Y"
        ;;
        -e|--extract)
        EXTRACT="Y"
        ;;
        -i|--cpio-image)
        CPIOFILE="$2"
        shift
        ;;
        -d|--dir)
        DIR="$2"
        shift # past argument
        ;;
        -o|--output)
        OUTPUT="$2"
        shift # past argument
        ;;
        *)
        # unknown option
        echo "Unknown option"
        usage
        ;;
    esac
    shift
done

CPIODIR=$(dirname "$CPIOFILE")
# Checking for . allows us to specify relative paths...
if [[ ${CPIODIR} == '.' ]]; then
    CPIODIR=$(pwd)
fi

if [ ! -z "${CREATE}" ]; then
    OLDDIR=$(pwd)
    cd "${DIR}"
    find . | cpio -o -H newc | gzip -9 > "${OUTPUT}"
    cd ${OLDDIR}
fi

if [ ! -z "${EXTRACT}" ]; then
    OLDDIR=$(pwd)
    if [ -z "${DIR}" ]; then
        echo "Extraction requires -d to specify dir to extract to"
        exit
    fi;

    if [ -z "${CPIOFILE}" ]; then
        echo "Extraction requires -i to specify cpio image to extract"
        exit
    fi;
    mkdir -p "${DIR}"
    cd ${DIR}
    cpio -id < ${CPIODIR}/${CPIOFILE}
    cd ${OLDDIR}
fi

