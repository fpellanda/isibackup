#!/bin/bash
# Copyright 1999-2007 IMSEC GmbH
#
# This file is part of ISiBackup.
#
#    ISiBackup is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    ISiBackup is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with ISiBackup; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#

# Test program for isibackup

ISIBACKUP_LIBRARY=1
source "../isibackup"

LOG_ABORT_ON_FATAL="no"

function test_make_absolute () {
    make_absolute "bin"
    make_absolute "/bin"
    make_absolute "/bin" "/usr"
    make_absolute "bin" "/usr"
}

function test_normalize_path () {
    normalize_path "/"
    normalize_path "//"
    normalize_path "///"
    normalize_path "/usr"
    normalize_path "/usr/"
    normalize_path "/usr//"
    normalize_path "//usr/bin///X"
}

function test_init_log () {
    log_init

    log "default 1"
    log "message 1" $LOG_MESSAGE
    log "debug 1" $LOG_DEBUG
    log "info 1" $LOG_INFO
    log "error 1" $LOG_ERROR
    log "fatal 1" $LOG_FATAL
}

function test () {
name=$1
	echo -n "Test $name:"
	rm -rf tests/$name
	mkdir -p tests/$name

	pushd tests/$name >/dev/null
	$name >>stdout 2>stderr
	popd >/dev/null

	if diff -rN -x CVS >tests/$name.diff tests/$name checks/$name ; then
		echo "[PASSED]"
	else
        echo
        cat tests/$name.diff
		echo "[FAILED]"
	fi
	echo
}

function update () {
name=$1
	echo "Update $name"
	rm -rf tests/$name
	mkdir -p tests/$name
	rm -rf checks/$name
	mkdir -p checks

	pushd tests/$name >/dev/null
	$name >>stdout 2>stderr
	popd >/dev/null

	cp -r tests/$name checks/$name
	show $name
}

function show () {
name=$1
    for i in $(find tests/$name -type f) ; do
	echo "Content of file '$i':"
	cat "$i"
	echo
    done
}

if [ "$#" == "2" ] ; then
    tests=$2
else
    tests="test_make_absolute test_normalize_path test_init_log"
fi

for i in $tests; do
	$1 $i
done
