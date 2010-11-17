# Copyright (C) 1999-2007  IMSEC GmbH
# Copyright (C) 2004-2007  Logintas AG
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
#    You should have received a copy of the GNU General Public License along
#    with this program; if not, write to the Free Software Foundation, Inc.,
#    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
# This is a bash script fragment
#

##### date and time settings
# current date
#
TODAY="$(date -I)"

# yesterday's date in words
#
YESTERDAY_WORDS=$(date "+%b %e" -d yesterday)

# date and time one minute ago in words
#
PASTMINUTE_WORDS=$(date "+%b %e %H:%M" -d "1 minute ago")

# date and time at program start
#
STARTDATETIME=$(date "+%Y-%m-%d-%H-%M")

# just the seconds (all of them!)
#
SECONDS=$(date +%s)

##### network and host names
# host name
#
HOST="$(hostname)"

# network name
#
NET="$(hostname -d)"

# short network name
#
NET_SHORT="$(hostname -d | cut -f 1 -d '.')"

DELAY=0

function do_version () {
    echo "$PROGRAM_IDENT $PROGRAM_VERSION"
    echo "$COPYRIGHT"
    echo "$LIABILITY"
    echo
    echo "$AUTHORS"
}

function do_help_common_commands () {
    echo "COMMANDS:"
    echo $'\t-h\t--help\t\t\t\tshow this help'

}

function do_help_common_options () {
    echo "OPTIONS:"
    echo $'\t-v\t--verbose\t\t\tgive more infos'
    echo $'\t-w\t--debug\t\t\t\tgive even more infos'
}

if [ -z "$LOG_VERSION" ] ; then
    LOG_VERSION="$PROGRAM_IDENT $PROGRAM_VERSION"

    LOG_ABORT_ON_FATAL="yes"

    LOG_FATAL="LOG_FATAL"
    LOG_ERROR="LOG_ERROR"
    LOG_WARN="LOG_WARN"
    LOG_MESSAGE="LOG_MESSAGE"
    LOG_INFO="LOG_INFO"
    LOG_DEBUG="LOG_DEBUG"
    LOG_PROGRESS="LOG_PROGRESS"
    
    LOG_NONE="$LOG_FATAL"
    LOG_NORMAL="$LOG_MESSAGE $LOG_WARN $LOG_ERROR $LOG_FATAL"
    LOG_VERBOSE="$LOG_INFO"
    LOG_ALL="$LOG_VERBOSE $LOG_DEBUG"

    # LOG_LEVEL is deprecated
    LOG_LEVEL=$LOG_NORMAL

    ERROR_OCCURED=0
fi

function contains () {
local vElement="$1"
local vList="$2"

    for i in $vList ; do
        for j in $vElement ; do
            if [ "$j" == "$i" ] ; then
                return
            fi
        done
    done

    return 1
}

function conjunction () {
local vList1="$1"
local vList2="$2"

    local lConjunction=""
    
    for i in $vList1 ; do
        for j in $vList2 ; do
            if [ "$j" == "$i" ] ; then
                lConjunction="$lConjunction $i"
            fi
        done
    done
    
    echo "$lConjunction"
}

function indent () {
local vMessage="$1"
local vIndentation="${2:-  }"

    echo "$vMessage" | sed "s/^/$vIndentation/"
}


function fill_line () {
local vLength="$1"
local vChar="$2"

    local line=""
    for i in $(seq $vLength) ; do
        line="$line$vChar"
    done
    echo "$line"
}

function clear_line () {
# TODO:
# Doesn't work if message was longer than one line on the console
# it even will create empty lines:-(
local vMessage="$1"

    echo -n $'\r'"$(fill_line ${#vMessage} " ")"$'\r'
}

function log_init () {
    register_sink "CONSOLE" "$LOG_MESSAGE $LOG_WARN" "/dev/stdout"
    register_sink "ERROR" "$LOG_ERROR $LOG_FATAL $LOG_PROGRESS" "/dev/stderr"
}

function register_sink () {
local vSink="$1"
local vMask="$2"
local vFile="$3"

    unregister_sink "$vSink"

    LOG_SINKS="$LOG_SINKS $vSink"
    eval "LOG_MASK_$vSink='$vMask'"

    if cat /dev/null 2>/dev/null >>"$vFile" ; then
        eval "LOG_FILE_$vSink='$vFile'"
    else
        eval "LOG_MASK_$vSink=''"
        log "Cannot write to logfile '$vFile'." $LOG_ERROR
        log "Stop logging to this file." $LOG_ERROR
    fi
}

function unregister_sink () {
local vSink="$1"

    LOG_SINKS=$(echo "$LOG_SINKS" | sed "s/^$vSink\$\|^$vSink \| $vSink\| $vSink\$//g")
    sync
}

function register_stream_sink () {
local vSink="$1"
local vMask="$2"
local vFile="$3"

    register_sink "$vSink" "$vMask" "$vFile"
}

function format_ERROR() {
local vMessage="$1"

    echo "[ERROR]: $vMessage"
}

function format_FATAL() {
local vMessage="$1"

    echo "[FATAL]: $vMessage"
}

function format_DEBUG() {
local vMessage="$1"

    echo "[DEBUG]: $vMessage"
}

function format_INFO() {
local vMessage="$1"
    if [ -z "$vMessage" ] ; then
	echo ""
    else
        echo "[INFO ]: $vMessage"
    fi
}

function format_title() {
local vMessage="$1"

    echo "$vMessage"
    echo "$(fill_line ${#vMessage} "-")"
}

function log_title() {
local vMessage="$1"
shift

    log "$(format_title "$vMessage")" $@
}

function log_FILE() {
local vMessage="$1"
local vFile="${2:-/dev/stdout}"

    if [ "$vFile" == "/dev/stderr" ] ; then
        echo "$vMessage" >&2
    elif [ "$vFile" == "/dev/stdout" ] ; then
        if [ ! "$lShownConsole" == "true" ] ; then
            echo "$vMessage"
            lShownConsole=true
        fi
    elif ! echo "$vMessage" 2>/dev/null >>"$vFile"; then
        if [ ! "$lShownConsole" == "true" ] ; then
            echo "$vMessage"
            lShownConsole=true
        fi
    fi
}

function log () {
local vMessage="$1"
local vLevel="${2:-$LOG_MESSAGE}"

    lShownConsole=false
    
    for i in $LOG_SINKS ; do
        local lMask="LOG_MASK_$i"
        local lFile="LOG_FILE_$i"
        for j in $(conjunction "$vLevel" "${!lMask} $i"); do
            local lMessage="$vMessage"
            case "$j" in
            $LOG_FATAL)
                lMessage=$(format_FATAL "$vMessage")
                ;;
            $LOG_ERROR)
                lMessage=$(format_ERROR "$vMessage")
                ;;
            $LOG_DEBUG)
                lMessage=$(format_DEBUG "$vMessage")
		;;
            $LOG_INFO)
                lMessage=$(format_INFO "$vMessage")
            esac
            
            log_FILE "$lMessage" "${!lFile}"
            # logger -p "isibackup.$vLevel" "$vMessage"
        done
    done

    if [ "$vLevel" == $LOG_FATAL -a "$LOG_ABORT_ON_FATAL" == "yes" ] ; then
        exit 1
    fi
    if [ "$vLevel" == $LOG_ERROR ] ; then
        ERROR_OCCURED=1
    fi
}

function log_stream () {
local vLevel="$1"
    
    while read line ; do
        if [ ! -z "$line" ] ;then 
            log "$line" "$vLevel"
        fi
    done
}

function show_progress () {
local vMessage="$1"
local vStay="$2"

if [ "$OPT_SHOW_PROGRESS" == "true" ]; then
    clear_line "$PROGRESS_LINE"
    PROGRESS_LINE="$vMessage"
    if [ -z "$vStay" ] ; then
        echo -n "$PROGRESS_LINE"
    else
        echo "$PROGRESS_LINE"
    fi
    log "" $LOG_INFO
fi
}

function follow_progress () {
local vMessage="$1"
local vStep="${2:-1}"
local vFrom="${3:-1}"

    local lCount=$vFrom

    while read line ; do
        if [ $(( $lCount % $vStep )) == 0 ] ; then
            show_progress "$vMessage$lCount"
        fi
        lCount=$(( $lCount + 1 ))
    done
}
