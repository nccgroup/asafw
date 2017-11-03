#!/bin/bash
#
# This file is part of asafw.
# Copyright (c) 2017, Aaron Adams <aaron.adams(at)nccgroup(dot)trust>
# Copyright (c) 2017, Cedric Halbronn <cedric.halbronn(at)nccgroup(dot)trust>
#
# This script is used to copy lina executables from already extracted firmware 
# and though is complementary to unpack_repack_bin.sh  to save all lina 
# binaries in a given output folder to be processed by idahunt.
#
# Note: This copy is optional and idahunt can be run on the extracted firmware
# directly but it can be used to save space if we are only interested in 
# analyzing lina.

usage()
{
    echo "Assume all firmware are already extracted in the current directory and save the lina and lina_monitor binaries somewhere else"
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
# _asav932-200.qcow2.extracted    _asav933-10.qcow2.extracted   _asav981-5.qcow2.extracted
for EXTRACTEDFW in $(find * -maxdepth 0 -type d);
do
    FWFILE=$(echo $EXTRACTEDFW | cut -d'_' -f 2 | cut -d'.' -f 1)
    EXTENSION=$(echo $EXTRACTEDFW | cut -d'_' -f 2 | cut -d'.' -f 2)
    FWFILE=$FWFILE.$EXTENSION
    #echo $OUTDIR
    LINA=$EXTRACTEDFW/rootfs/asa/bin/lina
    LINA_MONITOR=$EXTRACTEDFW/rootfs/asa/bin/lina_monitor
    echo $LINA
    echo $LINA_MONITOR
    mkdir ${LINABINDIR}/${FWFILE}
    cp ${LINA} ${LINABINDIR}/${FWFILE}/
    cp ${LINA_MONITOR} ${LINABINDIR}/${FWFILE}/
done