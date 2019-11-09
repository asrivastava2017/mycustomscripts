#!/bin/bash

string="fail"

tail -n 0 -F /home/ubuntu/file.log | \
while read LINE
do
echo "$LINE" | grep -q $string
if [ $? = 0 ]
then
echo "$string found on $HOSTNAME"
fi
done
