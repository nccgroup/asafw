#!/bin/bash
#
# Restart lina userland process without reboot the whole Linux OS
#
# Note:
# You can use "crashinfo force page-fault" to force a crash from Cisco CLI for testing purpose
#

while true; do
	# we can't just read on stdin as we get the following error:
	# bash: read: read error: 0: Resource temporarily unavailable
	# so we use serial input instead
    read -p "[lina_loop] Press enter to continue" < /dev/ttyS1
    echo "[lina_loop] Removing /dev/log..."
    rm /dev/log
    echo "[lina_loop] Restarting lina..."
    echo "[lina_loop] Expect a Cisco CLI sooner than later..."
    #/asa/bin/lina -t -l
    #bash -c "/asa/bin/lina -t -l"
	/asa/bin/lina_monitor -l
	#id
    echo "[lina_loop] lina exited, probably crashed?"
done
