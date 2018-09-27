#!/bin/sh
#
# Attach gdbserver to already started lina userland process

if [ -e /dev/ttyUSB0 ]
then
	# Real ASA
	DEBUG_PORT=/dev/ttyUSB0
else
	# GNS3
	DEBUG_PORT=/dev/ttyS0
fi

# # ps|grep gdbserver
#  1227 root     gdbserver --attach /dev/ttyUSB0 1174
#  1231 root     grep gdbserver
# # ps|grep gdbserver|grep -v "grep"|cut -d" " -f2
# 1227
PID_GDB=$(ps|grep gdbserver|grep -v "grep"|cut -d" " -f2)
echo "[lattach] Killing gdbserver PID: $PID_GDB"
kill -9 $PID_GDB

echo "[lattach] Sleeping 1 second..."
sleep 1

PID_LINA=$(ps|grep /asa/bin/lina|grep -vE "gdbserver|grep"|cut -d" " -f2)
echo "[lattach] PID lina: $PID_LINA"

# we assume lina has been started with "lina_start.sh". 
# Also we run it in the background so we can issue other
# commands like killing stale gdbserver or lina after it exits/crashes...
echo "[lattach] Attaching gdbserver on existing lina in the background, listening on $DEBUG_PORT..."
gdbserver --attach $DEBUG_PORT $PID_LINA &

echo "[lattach] Done."