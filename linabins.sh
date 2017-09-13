#!/bin/bash
#
# This file is part of asafw.
# Copyright (c) 2017, Aaron Adams <aaron.adams(at)nccgroup(dot)trust>
# Copyright (c) 2017, Cedric Halbronn <cedric.halbronn(at)nccgroup(dot)trust>
#
# This script is used to copy lina executables
# from already extracted firmware and though
# is an alternative to unpack_repack_bin.sh
# to get all lina binaries.

usage()
{
    echo "Extract all firmware in the current folder and save the lina binaries somewhere else"
    echo Usage: linabins.sh \<linabins_output_folder\>
    exit
}

if [[ $1 == "-h" ]]
then
    usage
    exit
fi

LINABINDIR=$1
if [[ -z $LINABINDIR ]]
then
    echo You need to provide a folder for lina binaries
    exit 1
fi
mkdir $LINABINDIR
if [ $? != 0 ];
then
    echo You need to provide a valid output folder for lina binaries
    exit 1
fi

# current folder must contain folder with such names:
# _asa803-k8.bin.extracted        _asa844-9-k8.bin.extracted    _asa917-9-k8.bin.extracted
for EXTRACTEDFW in $(find * -maxdepth 0 -type d);
do
    FWFILE=$(echo $EXTRACTEDFW | cut -d'_' -f 2 | cut -d'.' -f 1)
    FWFILE=$FWFILE.bin
    #echo $OUTDIR
    LINA=$EXTRACTEDFW/rootfs/asa/bin/lina
    echo $LINA
    mkdir ${LINABINDIR}/${FWFILE}
    cp ${LINA} ${LINABINDIR}/${FWFILE}/
done