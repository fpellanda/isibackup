#!/bin/bash
# only make successful
# backup if a mountpoint
# in /media/user-*
# or /media/host-*
# exist
mountpoints=$(find /media -maxdepth 1 -type d \( -name "user-*" -o -name "host-*" \) -exec mountpoint -q {} \; -exec ls -d {} \; | wc -l)

if [ $mountpoints == "0" ] ; then 
    echo "No stick mounted!" >&2
    exit 1
else
    echo "Ok there are sticks mounted."
    exit 0
fi
