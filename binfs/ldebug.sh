#!/bin/sh
#
# Attach gdbserver to lina userland process without reboot the whole Linux OS

/asa/scripts/lkill.sh
/asa/scripts/lclean.sh

# we don't use lina_monitor to keep it simple and also so it does not reboot
# when lina exits. Also we run it in the background so we can issue other
# commands like killing stale gdbserver or lina after it exits/crashes...
if [ -e /dev/ttyUSB0 ]
then
	# Real ASA
	DEBUG_PORT=/dev/ttyUSB0
else
	# GNS3
	DEBUG_PORT=/dev/ttyS0
fi
echo "[ldebug] Starting gdbserver on lina in the background, listening on $DEBUG_PORT..."
gdbserver $DEBUG_PORT /asa/bin/lina -t -g -l &

echo "[ldebug] Done."