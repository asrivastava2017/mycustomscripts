#!/bin/bash

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export AWS_DEFAULT_REGION=us-east-1
d=`date`

echo "================================================================Script Started" >> /home/ubuntu/crondisklog.txt
echo "Date : $d" >> /home/ubuntu/crondisklog.txt
echo "Threshold is 80%" >> /home/ubuntu/crondisklog.txt

useddiskpercent=`df -h | grep '/dev/md0' | awk '{print $5}'`
echo $useddiskpercent
diskpercent=`df -h | grep '/dev/md0' | awk '{print $5}' | tr -d %`
echo $diskpercent
echo "Disk is $useddiskpercent" >> /home/ubuntu/crondisklog.txt
ip4=$(/sbin/ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1)
echo $ip4
serverid=`curl http://instance-data/latest/meta-data/instance-id`
echo $serverid

if [ $diskpercent -gt 80 ]
then

        aws sns publish --topic arn:aws:sns:us-east-1:111111181398:sns-pre-Launch-db-rw-master --message "CRITICAL DISK STORAGE is '$useddiskpercent'  ServerIP='$ip4'  InstanceID='$serverid'"
        echo "ScriptRan . Alerting Threshold BREACHED ." >> /home/ubuntu/crondisklog.txt

else

        echo "ScriptRan . Alerting Threshold did not Breached" >> /home/ubuntu/crondisklog.txt

fi

echo "================================================================Script Completed" >> /home/ubuntu/crondisklog.txt
