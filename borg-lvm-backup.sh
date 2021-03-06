#!/bin/bash
# BorgBackup LVM Backup Script V1.1

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 configfile (located in folder ./config)" >&2
  exit 1
fi

##INPUT
JOBNAME=$1
##INPUT
WORKINGDIRECTORY=$(dirname "$BASH_SOURCE")
CONFIGFILE="$WORKINGDIRECTORY/config/$JOBNAME"
TIMESTAMP="$(date +"%Y-%m-%d-%H-%M-%S")"

#QUIT IF CONFIGFILE DOES NOT EXIST
if [ ! -f $CONFIGFILE ]
then
        echo "$(date +"%Y-%m-%d-%H-%M-%S"):ERROR: Configfile not found, aborting."
        echo "$(date +"%Y-%m-%d-%H-%M-%S"):----------UNSUCCESSFULLY FINISHED BACKUP OF $HOST $JOBNAME ON $TIMESTAMP----------"
        exit 2
fi

chmod +x $CONFIGFILE
. $CONFIGFILE
export BORG_PASSPHRASE=$BORG_PASSPHRASE

HOST=$(hostname)
SNAPSHOTNAME="borgbackup-$JOBNAME"
LVPATH="/dev/$VOLUMEGROUP/$LOGICALVOLUME"
SNAPSHOTPATH="/dev/$VOLUMEGROUP/$SNAPSHOTNAME"
MOUNTPATH="$WORKINGDIRECTORY/mounts/$JOBNAME"

#Dateien
TIMESTAMPFILE="$WORKINGDIRECTORY/timestamps/$JOBNAME"
LOCKFILE="$WORKINGDIRECTORY/locks/$JOBNAME"
LOGFILE="$WORKINGDIRECTORY/logs/$JOBNAME-$TIMESTAMP"


#Create folder structure
DIRTIMESTAMPFILE="$WORKINGDIRECTORY/timestamps/"
DIRLOCKFILE="$WORKINGDIRECTORY/locks/"
DIRLOGFILE="$WORKINGDIRECTORY/logs/"
mkdir -p $DIRTIMESTAMPFILE $DIRLOCKFILE $DIRLOGFILE $MOUNTPATH

#Logfile erstellen
touch $LOGFILE

echo "$(date +"%Y-%m-%d-%H-%M-%S"):----------STARTING BACKUP OF $HOST $JOBNAME ON $TIMESTAMP----------" | tee -a $LOGFILE

##QUIT IF LOCKFILE EXISTS
if [ -f $LOCKFILE ]
then
        echo "$(date +"%Y-%m-%d-%H-%M-%S"):ERROR: Lockfile found, aborting." | tee -a $LOGFILE
        echo "$(date +"%Y-%m-%d-%H-%M-%S"):----------UNSUCCESSFULLY FINISHED BACKUP OF $HOST $JOBNAME ON $TIMESTAMP----------" | tee -a $LOGFILE
        sendemail -f $MAILFROM -t $MAILTO -u "ERROR: BORGBACKUP $HOST $JOBNAME ON $TIMESTAMP" -m ":(" -s $MAILHOST -xu $MAILUSER -xp $MAILPASSWORD -o tls=yes -a $LOGFILE
        exit 3
fi

##CREATE LOCKFILE
touch $LOCKFILE


##CREATE LVM SNAPSHOT
echo "$(date +"%Y-%m-%d-%H-%M-%S"):----CREATING SNAPSHOT----" | tee -a $LOGFILE
lvcreate -L${SNAPSHOTSIZE} -s -n $SNAPSHOTNAME $LVPATH | tee -a $LOGFILE
if [ $PIPESTATUS -ne 0 ]
then
        echo "$(date +"%Y-%m-%d-%H-%M-%S"):ERROR: Snapshot could not be created, aborting."  | tee -a $LOGFILE
        echo "$(date +"%Y-%m-%d-%H-%M-%S"):----------UNSUCCESSFULLY FINISHED BACKUP OF $HOST $JOBNAME ON $TIMESTAMP----------" | tee -a $LOGFILE
        sendemail -f $MAILFROM -t $MAILTO -u "ERROR: BORGBACKUP $HOST $JOBNAME ON $TIMESTAMP" -m ":(" -s $MAILHOST -xu $MAILUSER -xp $MAILPASSWORD -o tls=yes -a $LOGFILE
        rm $LOCKFILE
        exit 4
fi
echo "$(date +"%Y-%m-%d-%H-%M-%S"):----FINISHED CREATING SNAPSHOT----" | tee -a $LOGFILE

##MOUNT SNAPSHOT
echo "$(date +"%Y-%m-%d-%H-%M-%S"):----MOUNTING SNAPSHOT----" | tee -a $LOGFILE
mount $SNAPSHOTPATH $MOUNTPATH | tee -a $LOGFILE
if [ $PIPESTATUS -ne 0 ]
then
        echo "$(date +"%Y-%m-%d-%H-%M-%S"):ERROR: Snapshot could not be mounted, aborting."  | tee -a $LOGFILE
        echo "$(date +"%Y-%m-%d-%H-%M-%S"):----------UNSUCCESSFULLY FINISHED BACKUP OF $HOST $JOBNAME ON $TIMESTAMP----------" | tee -a $LOGFILE
        sudo lvremove -f $SNAPSHOTPATH | tee -a $LOGFILE
        sendemail -f $MAILFROM -t $MAILTO -u "ERROR: BORGBACKUP $HOST $JOBNAME ON $TIMESTAMP" -m ":(" -s $MAILHOST -xu $MAILUSER -xp $MAILPASSWORD -o tls=yes -a $LOGFILE
        rm $LOCKFILE
        exit 5
fi
echo "$(date +"%Y-%m-%d-%H-%M-%S"):----FINISHED MOUNTING SNAPSHOT----" | tee -a $LOGFILE

##DO BACKUP
echo "$(date +"%Y-%m-%d-%H-%M-%S"):----RUNNING BACKUP JOB----" | tee -a $LOGFILE
$BORGLOCATION create --info --compression $COMPRESSION --stats $REPOSITORY::$JOBNAME-$TIMESTAMP $MOUNTPATH 2>&1 >/dev/null | tee -a $LOGFILE
BORGERRORLEVEL=$PIPESTATUS
if [ $BORGERRORLEVEL -gt 1 ]
then
        echo "$(date +"%Y-%m-%d-%H-%M-%S"):ERROR: Borg returned error $BORGERRORLEVEL, aborting." | tee -a $LOGFILE
        umount -f $MOUNTPATH | tee -a $LOGFILE
        sudo lvremove -f $SNAPSHOTPATH | tee -a $LOGFILE
        echo "$(date +"%Y-%m-%d-%H-%M-%S"):----------UNSUCCESSFULLY FINISHED BACKUP OF $HOST $JOBNAME ON $TIMESTAMP----------" | tee -a $LOGFILE
        sendemail -f $MAILFROM -t $MAILTO -u "ERROR: BORGBACKUP $HOST $JOBNAME ON $TIMESTAMP" -m ":(" -s $MAILHOST -xu $MAILUSER -xp $MAILPASSWORD -o tls=yes -a $LOGFILE
        rm $LOCKFILE
        exit 6
fi
echo "$(date +"%Y-%m-%d-%H-%M-%S"):----FINISHED BACKUP JOB WITH RETURN CODE $ERRORLEVEL----" | tee -a $LOGFILE

##COMMIT SNAPSHOT
echo "$(date +"%Y-%m-%d-%H-%M-%S"):----DELETING SNAPSHOT----" | tee -a $LOGFILE
sudo umount -f $MOUNTPATH | tee -a $LOGFILE
sudo lvremove -f $SNAPSHOTPATH | tee -a $LOGFILE
echo "$(date +"%Y-%m-%d-%H-%M-%S"):----FINISHED DELETING SNAPSHOT----" | tee -a $LOGFILE

##PRUNE
echo "$(date +"%Y-%m-%d-%H-%M-%S"):----PRUNING BORG REPO----" | tee -a $LOGFILE
$BORGLOCATION prune --force -s -H $KEEPHOURS -d $KEEPDAYS -w $KEEPWEEKS -m $KEEPMONTHS --keep-last $KEEPLAST -P $JOBNAME $REPOSITORY 2>&1 >/dev/null | tee -a $LOGFILE
echo "$(date +"%Y-%m-%d-%H-%M-%S"):----Finished Pruning Borg Repo----" | tee -a $LOGFILE

##FINISH
if [ $BORGERRORLEVEL -gt 0 ]
then
	echo "$(date +"%Y-%m-%d-%H-%M-%S"):----------FINISHED BACKUP OF $HOST $JOBNAME ON $TIMESTAMP WITH WARNINGS----------" | tee -a $LOGFILE
	sendemail -f $MAILFROM -t $MAILTO -u "WARNING: BORGBACKUP $HOST $JOBNAME ON $TIMESTAMP" -m ":/" -s $MAILHOST -xu $MAILUSER -xp $MAILPASSWORD -o tls=yes -a $LOGFILE
fi
if [ $BORGERRORLEVEL -eq 0 ]
then
	echo "$(date +"%Y-%m-%d-%H-%M-%S"):----------SUCCESSFULLY FINISHED BACKUP OF $HOST $JOBNAME ON $TIMESTAMP WITHOUT ERROR----------" | tee -a $LOGFILE
	sendemail -f $MAILFROM -t $MAILTO -u "SUCCESS: BORGBACKUP $HOST $JOBNAME ON $TIMESTAMP" -m ":)" -s $MAILHOST -xu $MAILUSER -xp $MAILPASSWORD -o tls=yes -a $LOGFILE
fi
rm $TIMESTAMPFILE
touch $TIMESTAMPFILE
rm $LOCKFILE
exit 0