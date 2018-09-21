#!/bin/sh
#
# Kill stale gdbserver or lina processes

pkill -h &>2 /dev/null
if [ $? = 127 ]; then
	# Real ASA
	echo "[lkill] No pkill binary, using custom method..."
	# # ps|grep lina
	#  1248 root     gdbserver /dev/ttyUSB0 /asa/bin/lina -t -g -l
	#  1251 root     [lina]
	#  1304 root     grep lina
	# # ps|grep lina|cut -d" " -f2
	# 1248
	# 1251
	# 1306
	PID_LIST=$(ps|grep lina|cut -d" " -f2)
	for PID in $PID_LIST
	do
		echo "[lkill] Killing PID: $PID"
		kill -9 $PID
	done
else
	# GNS3
	echo "[lkill] Killing gdbserver"
	pkill -9 gdbserver

	echo "[lkill] Killing lina"
	pkill -9 lina
fi

echo "[lkill] Sleeping 5 seconds..."
sleep 5

echo "[lkill] Done."