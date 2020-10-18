#!/bin/sh
# vim:fdm=marker
#Author: Aron Xu (happyaron.xu@gmail.com)

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
min=`date +%H\-%M`

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
echo "`date +%H:%M:%S`: Script up and start running." >> ${runlog}

# Check for msmtprc and the permission.
# This is critical because sending alert email needs it.
if [ ! -f ${HOME}/.msmtprc ]; then
    echo "`date +%H:%M:%S`: msmtprc error occurred." >> ${runlog}
    if [ -f ${workdir}/config/msmtprc ]; then
	chmod 600 ${workdir}/config/msmtprc
        cp ${workdir}/config/msmtprc ${HOME}/.msmtprc
        echo "`date +%H:%M:%S`: msmtprc is missing, copied from ${workdir}." >> ${errlog} 
        echo "`date +%H:%M:%S`: msmtprc is missing, copied from ${workdir}." | mutt -s "$title msmtprc problem occurred" $admin;
	echo "`date +%H:%M:%S`: msmtprc recovered from backup, hopefully." >> ${runlog}
    else
        echo "`date +%H:%M:%S`: msmtprc is missing, failed to copy from ${workdir}, stop processing." >> ${errlog}
        echo "`date +%H:%M:%S`: msmtprc is missing, failed to copy from ${workdir}, stop processing." >> $HOME/MSMTPRC_IS_MISSING
	echo "`date +%H:%M:%S`: Fatal msmtprc error, quit." >> ${runlog}
	exit
    fi
fi

chmod 600 ${HOME}/.msmtprc
echo "`date +%H:%M:%S`: msmtprc OK." >> ${runlog}

# Check for muttrc and the permission.
# This is very useful because sending alert email needs it, but
# not a reason to stop because we still have chance to success.
if [ ! -f ${HOME}/.muttrc ]; then
    echo "`date +%H:%M:%S`: msmtprc error occurred." >> ${runlog}
    if [ -f ${workdir}/config/muttrc ]; then
	chmod 600 ${workdir}/config/muttrc
        cp ${workdir}/config/muttrc ${HOME}/.muttrc
        echo "`date +%H:%M:%S`: muttrc is missing, copied from ${workdir}." >> ${errlog} 
        echo "`date +%H:%M:%S`: muttrc is missing, copied from ${workdir}." | mutt -s "$title msmtprc problem occurred" $admin;
	echo "`date +%H:%M:%S`: muttrc recovered from backup, hopefully." >> ${runlog}
    else
        echo "`date +%H:%M:%S`: muttrc is missing, failed to copy from ${workdir}, email alert will not work." >> ${errlog}
        echo "`date +%H:%M:%S`: muttrc is missing, failed to copy from ${workdir}, email alert will not work." >> $HOME/MUTTRC_IS_MISSING
	echo "`date +%H:%M:%S`: muttrc error, contiune but email alert will not work." >> ${runlog}
    fi
fi

if [ -f ${HOME}/.muttrc ]; then
    chmod -f 600 ${HOME}/.muttrc
    echo "`date +%H:%M:%S`: muttrc OK." >> ${runlog}
fi

# Check for getmailrc and the permission.
# This is needed for getting messages. Assume email alert is working.
if [ ! -d ${HOME}/.getmail ]; then
    echo "`date +%H:%M:%S`: getmailrc error occurred." >> ${runlog}
    if [ -d ${workdir}/config/getmail ]; then
	chmod 700 ${workdir}/config/getmail
	chmod 600 ${workdir}/config/getmail/*
        cp -r ${workdir}/config/getmail ${HOME}/.getmail
        echo "`date +%H:%M:%S`: getmailrc is missing, copied from ${workdir}." >> ${errlog} 
        echo "`date +%H:%M:%S`: getmailrc is missing, copied from ${workdir}." | mutt -s "$title getmailrc problem occurred" $admin;
	echo "`date +%H:%M:%S`: getmailrc recovered from backup, hopefully." >> ${runlog}
    else
        echo "`date +%H:%M:%S`: getmailrc is missing, failed to copy from ${workdir}, stop processing." >> ${errlog}
        echo "`date +%H:%M:%S`: getmailrc is missing, failed to copy from ${workdir}, stop processing." | mutt -s "$title getmailrc is missing" $admin;
	echo "`date +%H:%M:%S`: Fatal getmailrc error, quit." >> ${runlog}
	exit
    fi
fi

chmod 700 ${HOME}/.getmail/
chmod 600 ${HOME}/.getmail/rc-*
echo "`date +%H:%M:%S`: getmailrc OK." >> ${runlog}

# Move the old getmail logs to backup.
#
# We need the getmail log to analyse if any problem occurs,
# here we clean the old logs away.
if [ -f $workdir/log/getmail.log ]; then
    mv $workdir/log/getmail.log $logdir/getmail.log.old
    echo "`date +%H:%M:%S`: Found old getmail.log, moved to $logdir/getmail.log.old." >> ${runlog}
fi

if [ -f $workdir/log/msmtp.log ]; then
    mv $workdir/log/msmtp.log $logdir/msmtp.log.old
    echo "`date +%H:%M:%S`: Found old msmtp.log, moved to $logdir/msmtp.log.old." >> ${runlog}
fi

# Run the getmail script to retrive messages.
#
# We make it a seperated script for we can make debuging more
# flexible. And when doing cleaning up we do not need to check too
# much things because the getmail process are owned by init then.
echo "`date +%H:%M:%S`: Start getting messages and sleep for 60 seconds." >> ${runlog}
sh ${workdir}/run-getmail2.sh

# Sleep 60 seconds to wait for all messages to be retrived.
#
# We do not kill the process and just head to sending the messages,
# at the same time retriving can keep running so we give them a
# bigger chance to complete normally.
sleep 60

echo "`date +%H:%M:%S`: Wake up after sleeping 60 seconds, start sending (if any) messages." >> ${runlog}

# Start sending the retrived messages.
#
# Note the getmail process may be still running, but we do not need
# to worry about incomplete downloads lying in the "new" directory of
# Maildir. If some messages did not get sent in this round, we will
# handle all of them in next round (30 minutes later).
for amail in `ls ${mailbox}/new/` ; do
    /usr/bin/msmtp $receiver < ${mailbox}/new/${amail};
# Look at the exit status code of the last msmtp run.
    if [ "$?" -ne "0" ]; then
        echo "`date +%H:%M:%S`: ERROR sending `basename ${amail}`, not sending." >> ${errlog};
	echo "`date +%H:%M:%S`: ERROR sending `basename ${amail}`, not sending." | mutt -s "$title message sending error" $admin;
        mv ${mailbox}/new/${amail} ${failbox}/new/;
    else
	echo "`date +%H:%M:%S`: SENT: `basename ${amail}`." >> ${sentlog};
        mv ${mailbox}/new/${amail} ${mailbox}/cur/;
    fi
# Sleep 1 second to avoid becoming I/O bond.
    sleep 1;
done
echo "`date +%H:%M:%S`: Sending complete, start cleaning up." >> ${runlog}

# Detect remaining getmail process.
#
# We have given them at least 60 seconds to run there jobs,
# If they are still running, then we might have encountered
# problems. We will give them even more time to run, but
# eventually kill them and send alert if they get stucked.
if ps -U $USER | grep -v grep | grep getmail > /dev/null ; then
    echo "`date +%H:%M:%S`: Sleeping for another 120 seconds (1st) to wait for remaining getmail process." >> ${runlog}
    sleep 120
fi
if ps -U $USER | grep -v grep | grep getmail > /dev/null ; then
    echo "`date +%H:%M:%S`: Sleeping for another 120 seconds (2nd) to wait for remaining getmail process." >> ${runlog}
    sleep 120
fi
# Waited for another 240 seconds, this should be enough for
# a common job to complete. If not, then we believe there are
# problems and let's end it.
if ps -U $USER | grep -v grep | grep getmail > /dev/null ; then
    echo "`date +%H:%M:%S`: getmail is still running, this might indicate a problem." >>  ${errlog}
    echo "`date +%H:%M:%S`: getmail is still running, this might indicate a problem." | mutt -s "$title getmail problem" $admin;
    pkill -u $USER getmail;
    echo "`date +%H:%M:%S`: Killed remaining getmail process, please use the traditional run-getmail.sh to debug." >> $runlog
fi
echo "`date +%H:%M:%S`: getmail process clean." >> ${runlog}

# Get the log of getmail, and see if any problem occurred.
if [ -f $workdir/log/getmail.log ]; then
    mv $workdir/log/getmail.log $logdir/getmail.log.${min}
    echo "`date +%H:%M:%S`: Found getmail.log, moved to $logdir/getmail.log.${min}" >> ${runlog}
    gerr=`grep -i error $logdir/getmail.log.${min}` 
    if [ ! -z $gerr ]; then
	printf "`date +%H:%M:%S`: Error in $logdir/getmail.log.${min}\n-------------getmail error log start-------------\n$gerr\n-------------getmail error log finished-------------" >> ${errlog}
	printf "`date +%H:%M:%S`: Error in $logdir/getmail.log.${min}\n-------------getmail error log start-------------\n$gerr\n-------------getmail error log finished-------------" | mutt -s "$title getmail error in log" $admin;
    fi
    gwarn=`grep -i warning $logdir/getmail.log.${min}`
    if [ ! -z $gwarn ]; then
	printf "`date +%H:%M:%S`: Waring in $logdir/getmail.log.${min}\n-------------getmail waring log start-------------\n$gerr\n-------------waring error log finished-------------" >> ${errlog}
	printf "`date +%H:%M:%S`: Waring in $logdir/getmail.log.${min}\n-------------getmail waring log start-------------\n$gerr\n-------------waring error log finished-------------" | mutt -s "$title getmail warning in log" $admin;
    fi
else
    echo "`date +%H:%M:%S`: getmail log missing." >> ${errlog}
fi

# Get the log of msmtp.
if [ -f $workdir/log/msmtp.log ]; then
    mv $workdir/log/msmtp.log $logdir/msmtp.log.${min}
    echo "`date +%H:%M:%S`: Found msmtp.log, moved to $logdir/msmtp.log.${min}" >> ${runlog}
fi

echo "`date +%H:%M:%S`: Script finished." >> ${runlog}
