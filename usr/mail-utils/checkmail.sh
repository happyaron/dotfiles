#!/bin/sh
# vim:fdm=marker
#Author: Aron Xu (happyaron.xu@gmail.com)
set -e

# Who to receive all the messages
receiver="chenyueg@gmail.com"

# Email alert address
admin="happyaron.xu@gmail.com"

# Title name
title="seis0904"

# Working directory
workdir=${HOME}/mail

# Maildirs
mailbox=${workdir}/inbox
failbox=${workdir}/fail

# Date and time format
month=`date +%Y%m`
day=`date +%d`
timestamp="date +%H:%M:%S"

# Log directories
mlogdir=${workdir}/log/${month}
logdir=${mlogdir}/${day}
runlog=${logdir}/runlog
errlog=${logdir}/errlog
sentlog=${logdir}/sentlog

#
# Script starts here.
cd $workdir

# Create log directories if necessary.
if [ ! -d $mlogdir ]; then
    rm -rf $mlogdir
    mkdir -p $mlogdir
fi
if [ ! -d $logdir ]; then
    rm -rf $logdir
    mkdir -p $logdir
fi

# Log the script has started.
echo "${timestamp}: Script up and start running." >> ${runlog}

# Check for msmtprc and the permission.
# This is critical because sending alert email needs it.
if [ ! -f ${HOME}/.msmtprc ]; then
    echo "${timestamp}: msmtprc error occurred." >> ${runlog}
    if [ -f ${workdir}/config/msmtprc ]; then
	chmod 600 ${workdir}/config/msmtprc
        cp ${workdir}/config/msmtprc ${HOME}/.msmtprc
        echo "${timestamp}: msmtprc is missing, copied from ${workdir}." >> ${errlog} 
        echo "${timestamp}: msmtprc is missing, copied from ${workdir}." | mutt -s "$title msmtprc problem occurred" $admin;
	echo "${timestamp}: msmtprc recovered from backup, hopefully." >> ${runlog}
    else
        echo "${timestamp}: msmtprc is missing, failed to copy from ${workdir}, stop processing." >> ${errlog}
        echo "${timestamp}: msmtprc is missing, failed to copy from ${workdir}, stop processing." >> $HOME/MSMTPRC_IS_MISSING
	echo "${timestamp}: Fatal msmtprc error, quit." >> ${runlog}
	exit
    fi
fi

chmod 600 ${HOME}/.msmtprc
echo "${timestamp}: msmtprc okay." >> ${runlog}

# Check for muttrc and the permission.
# This is very useful because sending alert email needs it, but
# not a reason to stop because we still have chance to success.
if [ ! -f ${HOME}/.muttrc ]; then
    echo "${timestamp}: msmtprc error occurred." >> ${runlog}
    if [ -f ${workdir}/config/muttrc ]; then
	chmod 600 ${workdir}/config/muttrc
        cp ${workdir}/config/muttrc ${HOME}/.muttrc
        echo "${timestamp}: muttrc is missing, copied from ${workdir}." >> ${errlog} 
        echo "${timestamp}: muttrc is missing, copied from ${workdir}." | mutt -s "$title msmtprc problem occurred" $admin;
	echo "${timestamp}: muttrc recovered from backup, hopefully." >> ${runlog}
    else
        echo "${timestamp}: muttrc is missing, failed to copy from ${workdir}, email alert will not work." >> ${errlog}
        echo "${timestamp}: muttrc is missing, failed to copy from ${workdir}, email alert will not work." >> $HOME/MUTTRC_IS_MISSING
	echo "${timestamp}: muttrc error, contiune but email alert will not work." >> ${runlog}
    fi
fi

if [ -f ${HOME}/.muttrc ]; then
    chmod -f 600 ${HOME}/.muttrc
    echo "${timestamp}: muttrc okay." >> ${runlog}
fi

# Check for getmailrc and the permission.
# This is needed for getting messages. Assume email alert is working.
if [ ! -d ${HOME}/.getmail ]; then
    echo "${timestamp}: getmailrc error occurred." >> ${runlog}
    if [ -d ${workdir}/config/getmail ]; then
	chmod 700 ${workdir}/config/getmail
	chmod 600 ${workdir}/config/getmail/*
        cp -r ${workdir}/config/getmail ${HOME}/.getmail
        echo "${timestamp}: getmailrc is missing, copied from ${workdir}." >> ${errlog} 
        echo "${timestamp}: getmailrc is missing, copied from ${workdir}." | mutt -s "$title getmailrc problem occurred" $admin;
	echo "${timestamp}: getmailrc recovered from backup, hopefully." >> ${runlog}
    else
        echo "${timestamp}: getmailrc is missing, failed to copy from ${workdir}, stop processing." >> ${errlog}
        echo "${timestamp}: getmailrc is missing, failed to copy from ${workdir}, stop processing." | mutt -s "$title getmailrc is missing" $admin;
	echo "${timestamp}: Fatal getmailrc error, quit." >> ${runlog}
	exit
    fi
fi

chmod 700 ${HOME}/.getmail/
chmod 600 ${HOME}/.getmail/rc-*
echo "${timestamp}: getmailrc okay." >> ${runlog}

# Move the old getmail logs to backup.
#
# We need the getmail log to analyse if any problem occurs,
# here we clean the old logs away.
if [ -f $workdir/log/getmail.log ]; then
    mv $workdir/log/getmail.log $logdir/getmail.log.old
    echo "${timestamp}: Found old getmail.log, moved to $logdir/getmail.log.old." >> ${runlog}
fi

if [ -f $workdir/log/msmtp.log ]; then
    mv $workdir/log/msmtp.log $logdir/msmtp.log.old
    echo "${timestamp}: Found old msmtp.log, moved to $logdir/msmtp.log.old." >> ${runlog}
fi

# Run the getmail script to retrive messages.
#
# We make it a seperated script for we can make debuging more
# flexible. And when doing cleaning up we do not need to check too
# much things because the getmail process are owned by init then.
echo "${timestamp}: Start getting messages and sleep for 120 seconds." >> ${runlog}
sh ${maildir}/run-getmail2.sh

# Sleep 60 seconds to wait for all messages to be retrived.
#
# We do not kill the process and just head to sending the messages,
# at the same time retriving can keep running so we give them a
# bigger chance to complete normally.
sleep 60

echo "${timestamp}: Wake up after sleeping 60 seconds, start sending (if any) messages." >> ${runlog}

# Start sending the retrived messages.
#
# Note the getmail process may be still running, but we do not need
# to worry about incomplete downloads lying in the "new" directory of
# Maildir. If some messages did not get sent in this round, we will
# handle all of them in next round (30 minutes later).
for amail in ${mailbox}/new/* ; do
    /usr/bin/msmtp $receiver < ${mailbox}/new/${amail};
# Look at the exit status code of the last msmtp run.
    if [ "$?" -ne "0" ]; then
        echo "${timestamp}: ERROR sending ${amail}, not sending." >> ${errlog};
	echo "${timestamp}: ERROR sending ${amail}, not sending." | mutt -s "$title message sending error" $admin;
        mv ${mailbox}/new/${amail} ${failbox}/new/;
    else
	echo "${timestamp}: SENT: ${amail}." >> ${sentlog};
        mv ${mailbox}/new/${amail} ${mailbox}/cur/;
    fi
# Sleep 1 second to avoid becoming I/O bond.
    sleep 1;
done
echo "${timestamp}: Sending complete, start cleaning up." >> ${runlog}

# Detect remaining getmail process.
#
# We have given them at least 60 seconds to run there jobs,
# If they are still running, then we might have encountered
# problems. We will give them even more time to run, but
# eventually kill them and send alert if they get stucked.
if ps -U $USER | grep -v grep | grep $PROCESS > /dev/null ; then
    echo "${timestamp}: Sleeping for another 120 seconds (1st) to wait for remaining getmail process." >> ${runlog}
    sleep 120
fi
if ps -U $USER | grep -v grep | grep $PROCESS > /dev/null ; then
    echo "${timestamp}: Sleeping for another 120 seconds (2nd) to wait for remaining getmail process." >> ${runlog}
    sleep 120
fi
# Waited for another 180 seconds, this should be enough for
# a common job to complete. If not, then we believe there are
# problems and let's end it.
if ps -U $USER | grep -v grep | grep $PROCESS > /dev/null ; then
    echo "${timestamp}: getmail is still running, this might indicate a problem." >>  ${errlog}
    echo "${timestamp}: getmail is still running, this might indicate a problem." | mutt -s "$title getmail problem" $admin;
    pkill -u $USER getmail;
    echo "${timestamp}: Killed remaining getmail process, please use the traditional run-getmail.sh to debug." >> $runlog
fi
echo "${timestamp}: getmail process clean." >> ${runlog}

# Get the log of getmail, and see if any problem occurred.
if [ -f $workdir/log/getmail.log ]; then
    mv $workdir/log/getmail.log $logdir/getmail.log
    echo "${timestamp}: Found getmail.log, moved to $logdir/getmail.log." >> ${runlog}
    gerr=`grep -i error $logdir/getmail.log`
    if [ -n $gerr ]; then
	echo "${timestamp}: Error in getmail.log." >> ${errlog}
	echo "${timestamp}: Error in getmail.log." | mutt -s "$title getmail error in log" $admin;
    fi
    gwarn=`grep -i warning $logdir/getmail.log`
    if [ -n $gwarn ]; then
	echo "${timestamp}: Warning in getmail.log." >> ${errlog}
	echo "${timestamp}: Warning in getmail.log." | mutt -s "$title getmail warning in log" $admin;
    fi
fi

# Get the log of msmtp.
if [ -f $workdir/log/msmtp.log ]; then
    mv $workdir/log/msmtp.log $logdir/msmtp.log
    echo "${timestamp}: Found msmtp.log, moved to $logdir/msmtp.log." >> ${runlog}
fi

echo "${timestamp}: Script finished." >> ${runlog}
