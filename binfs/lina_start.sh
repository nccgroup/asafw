#!/bin/bash
#
# Restart lina userland process without reboot the whole Linux OS
#
# Note:
# You can use "crashinfo force page-fault" to force a crash from Cisco CLI for testing purpose
#


# lina "syslogd" internal process needs this file to NOT exist when initializing
echo "[lina_start] Removing /dev/log..."
rm /dev/log

# we don't use lina_monitor to keep it simple and also so it does not reboot
# when lina exits
echo "[lina_start] Starting lina..."
echo "[lina_start] Expect a Cisco CLI sooner than later..."
/asa/bin/lina -t -l
echo "[lina_start] lina exited, probably crashed?"
