#!/bin/bash
lDpkgSelectionsTargetFile="$lTargetDir/dpkg-selections.bz2.gpg"
echo -n "dumping dpkg selections to ${lDpkgSelectionsTargetFile}... "
rm -f "${lDpkgSelectionsTargetFile}"
dpkg --get-selections | bzip2 |  eval gpg --batch --encrypt $Recipient_Flags > "${lDpkgSelectionsTargetFile}"
if [ -e "${lDpkgSelectionsTargetFile}" -a -s "${lDpkgSelectionsTargetFile}" ] ; then
    echo "done"
    echo "result: $(ls -la "${lDpkgSelectionsTargetFile}")"
else
    echo "failed"
    exit 1
fi

exit 0