#!/bin/bash

/bin/stty rows 152 cols 105

export PATH=$PATH:/usr/local/bin:/var/lib/gems/1.9.1/bin
cd /opt/nitrogenlogic/webstatus
while true; do
	echo "Starting web status server."
	nice -n -1 ruby $(which rackup) -E production -p 4567 -o 0.0.0.0 -s thin logic_web.ru
	sleep 1
done
