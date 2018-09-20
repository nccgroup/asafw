#!/bin/sh
#
# Remove files required to be non-existent when lina start

# _mm_reserve_hugetlb_pages() will fail if it holds a value ~ 1800 due to a previous start
# 0 is the default value at boot so should be safe
# E.g.: asa912-smp
echo "[lclean] Reseting hugepages..."
echo 0 > /proc/sys/vm/nr_hugepages

# lina "syslogd" internal process needs this file to NOT exist when initializing
# e.g.: asav941-200
echo "[lclean] Removing /dev/log..."
rm /dev/log

# lina "syslogd" internal process needs these files to NOT exist when initializing
# E.g.: asa912-smp
echo "[lclean] Removing /dev/ttyS0_vmX files..."
rm /dev/ttyS0_vm1
rm /dev/ttyS0_vm2

echo "[lclean] Done."