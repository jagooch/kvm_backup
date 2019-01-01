#!/bin/bash

#
# This is who we'll back up where the var is the path to file containing list of domains ie  machine1 machine2 machine3
#
machines=$(<$1)

#
# Keep the house clean
#
days_to_keep="7"

#
# Store backups here. NFS to another machine would make sense. 
# so that your backups are not local.
#
backup_dir="/mnt/THEVAULT/Backups"

#
# Logs go here.
#
log_dir="/mnt/THEVAULT/Backups/logs"

#
# End parameters
#
#=================================================================


#
# Check if the backup destination is present. If not, exit. 
#
if [ ! -d "${backup_dir}" ]; then 
  echo "The backup dir ${backup_dir} is not available. Exiting...";
  exit 2
fi



#
# Timestamp for the log file
#
right_now=`date '+%m%d%Y_%H%M%p'`

exec 1>/${log_dir}/backup_vms.${right_now}.log 2>&1

print_date() {
   date '+%m%d%Y_%H%M%p'
}

for machine in $machines
do
   if [[ ! -d ${backup_dir}/${machine} ]];
   then
      mkdir -p ${backup_dir}/${machine}
   fi

   echo "Backing up VM configuration"
   virsh dumpxml $machine > ${backup_dir}/${machine}/${machine}.xml

   echo "Sending shutdown signal to $machine"
   virsh shutdown $machine
   echo "   Return code: $?"
   
   echo -n "Waiting for machine to shut down "
   for i in 1 2 3 4 5
   do
      echo -n "."
      virsh list | grep -v "^$" | grep -v "^ Id" | grep -v "\-\-\-\-\-" | awk '{print $2" "$3}' | grep $machine | while read name state
      do
         if [[ $state -eq "running" ]]
         then
            sleep 60
         fi
      done
   done

   echo "Copying disk(s)"
   virsh domblklist $machine | grep -v "^$" | grep -v "^Target" | grep -v "\-\-\-\-\-" | awk '{print $2}' | while read disk
   do
      echo "   $disk ..."
      copy_disk="${backup_dir}/${machine}/`basename ${disk}`.`print_date`"
      echo "   Copying $disk to $copy_disk"
      fuser $disk 1>/dev/null 2>&1
      if (( $? == 0 ))
      then
         echo "   Disk $disk is still in use! "
      else
         echo "   Copy started at `print_date`"
         cp $disk $copy_disk
         echo "   Return code: $?"
         echo "   Copy ended at `print_date`"
         echo "   Backgrounding bzip of $copy_disk"
         nohup bzip2 $copy_disk &
      fi
   done

   echo "Starting machine $machine"
   virsh start $machine
   echo "   Return code: $?"
   echo

done

   echo "Removing old backups."
   find $backup_dir -type f -mtime +$days_to_keep -ls
   find $backup_dir -type f -mtime +$days_to_keep -exec rm -f {} \;

