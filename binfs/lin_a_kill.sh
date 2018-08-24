#!/bin/bash
#
# Kill stale gdbserver or lina processes
#
# Note: the typo "lin_a" instead of "lina" is so we don't kill our script before it finishes


echo "[lin_a_kill] Killing gdbserver"
pkill -9 gdbserver

echo "[lin_a_kill] Killing lina"
pkill -9 lina

echo "[lin_a_kill] Sleeping 5 seconds..."
sleep 5

echo "[lin_a_kill] Done."