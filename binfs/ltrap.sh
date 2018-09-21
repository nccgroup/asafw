#!/bin/sh
#
# Send a SIG_TRAP to /asa/bin/lina.
#
# Assumes we are debugging lina (i.e. gdbserver is attached to lina to catch the signal)
# This is to simulate a CTRL+C in gdb.

# # ps|grep /asa/bin/lina
#  1177 root     gdbserver /dev/ttyUSB0 /asa/bin/lina -t -g -l
#  1180 root     /asa/bin/lina -t -g -l
#  1189 root     grep /asa/bin/lina
# # ps|grep /asa/bin/lina|grep -vE "gdbserver|grep"
#  1180 root     /asa/bin/lina -t -g -l
# # ps|grep /asa/bin/lina|grep -vE "gdbserver|grep"|cut -d" " -f2
# 1180
PID=$(ps|grep /asa/bin/lina|grep -vE "gdbserver|grep"|cut -d" " -f2)
echo "[ltrap] Sending SIGTRAP to PID: $PID"
kill -5 $PID

echo "[ltrap] Done."