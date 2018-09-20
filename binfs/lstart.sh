#!/bin/sh
#
# Restart lina userland process without reboot the whole Linux OS
#
# Note:
# You can use "crashinfo force page-fault" to force a crash from Cisco CLI for testing purpose
#

/asa/scripts/lkill.sh
/asa/scripts/lclean.sh

# we don't use lina_monitor to keep it simple and also so it does not reboot
# when lina exits

# GNS3
# XXX - detect GNS3 if we want to keep this method?
#echo "[lstart] Starting lina..."
#echo "[lstart] Expect a Cisco CLI sooner than later..."
#/asa/bin/lina -t -l
#echo "[lstart] lina exited, probably crashed?"

# Real ASA
echo "[lstart] Starting lina in the background..."
/asa/bin/lina -t -l &
echo "[lstart] Done."
