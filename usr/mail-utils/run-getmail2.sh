#!/bin/sh
# vim:fdm=marker
#
# Just start a process for every rc file, but do not wait it
# to complete. The main script will handle them.
#
# Sleep 5 seconds will make no more than 3 process running at
# the same time and reduce the pressure to server.
#
set -e
cd $HOME/.getmail

for file in rc-* ; do
	exec /usr/bin/getmail --rcfile $file &
	sleep 5
done

