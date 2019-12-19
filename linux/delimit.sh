#!/bin/bash
IN=$(cat filed)
for i in $(echo $IN | tr " " "\n")
do
  echo $i
done
