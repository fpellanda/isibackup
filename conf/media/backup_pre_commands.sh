#!/bin/bash
if mountpoint -q $lSourceDir ; then
  echo "OK, $lSourceDir is a mount point."
  exit 0
else
  echo "$lSourceDir is not a mount point." >&2
  exit 1
fi
