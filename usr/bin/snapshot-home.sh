#!/bin/sh

REPL_USER=root
REPL_HOST=backup.localdomain

LOG_TAG=fs-repl
LOGGER="logger -t $LOG_TAG"
SNAP_DATE=$(date +%Y%m%dT%H%M%S)
SNAP_NAME="/repl/home@$SNAP_DATE"

$LOGGER "Starting BTRFS replication for home"

BTRFS=$(PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin which btrfs)
if ! [ -x $BTRFS ]; then
    $LOGGER "Command not found: btrfs, quit"
    exit 1
fi

SNAP_COUNT=$($BTRFS subvolume list / | grep '@' | wc -l)
SNAP_OLDEST=$($BTRFS subvolume list / | grep '@' | grep 'T' | head -1 | awk '{print $9}')
SNAP_LATEST=$($BTRFS subvolume list / | grep '@' | grep 'T' | tail -1 | awk '{print $9}')

$LOGGER "SNAP_COUNT: $SNAP_COUNT"
$LOGGER "SNAP_OLDEST: $SNAP_OLDEST"
$LOGGER "SNAP_LATEST: $SNAP_LATEST"

$BTRFS subvolume snapshot -r /home $SNAP_NAME
$LOGGER "Snapshot created: $SNAP_NAME"

if [ $SNAP_COUNT -ge 7 ]; then
    $BTRFS subvolume delete /$SNAP_OLDEST
    $LOGGER "Snapshot removed: /$SNAP_OLDEST"
    ssh ${REPL_USER}@${REPL_HOST} btrfs subvolume delete /$SNAP_OLDEST
    $LOGGER "Remote snapshot removed: /$SNAP_OLDEST"
fi

if [ "$SNAP_LATEST" != "" ]; then
    $BTRFS send -p /$SNAP_LATEST $SNAP_NAME | ssh ${REPL_USER}@${REPL_HOST} btrfs receive /repl
else
    $BTRFS send $SNAP_NAME | ssh ${REPL_USER}@${REPL_HOST} btrfs receive /repl
fi
$LOGGER "Remote replication to $REPL_HOST completed"
