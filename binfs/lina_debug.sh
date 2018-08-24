#!/bin/bash
#
# Attach gdbserver to lina userland process without reboot the whole Linux OS


# lina "syslogd" internal process needs this file to NOT exist when initializing
echo "[lina_debug] Removing /dev/log..."
rm /dev/log

# we don't use lina_monitor to keep it simple and also so it does not reboot
# when lina exits. Also we run it in the background so we can issue other
# commands like killing stale gdbserver or lina after it exits/crashes...
echo "[lina_debug] Starting gdbserver on lina in the background..."
gdbserver /dev/ttyS0 /asa/bin/lina -t -g -l &

echo "[lina_debug] Done."