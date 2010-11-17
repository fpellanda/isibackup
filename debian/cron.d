# execute isibackup every night
# the new version knows which backup
# should be done.
0 1 * * * root isibackup --quiet
