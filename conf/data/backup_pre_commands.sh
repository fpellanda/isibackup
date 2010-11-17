#!/bin/bash
# TODO: Note (from http://dev.mysql.com/doc/refman/5.1/en/mysqldump.html)
# Prior to MySQL 5.1.21, this option did not create
# valid SQL if the database dump contained views. 
# he recreation of views requires the creation and
# removal of temporary tables and this option suppressed
# the removal of those temporary tables. As a workaround,
# use --compact with the --add-drop-table option and then
# manually adjust the dump file.
 #############
### mysql ###
#############
function dump_mysql {
    echo $lMySqlDumpCommand $lMySqlCompressCommand
    echo -n "dumping mysql data ..."
    eval $lMySqlDumpCommand $lMySqlCompressCommand
    _RES=${PIPESTATUS[*]}
    for res in $_RES; do
	if [[ ( $res > 0 ) ]]; then
	    echo "failed" >&2
	    exit 1
	fi
    done
    echo "done"
}
if [ -d /var/lib/mysql ] ; then

    if [ "$OPT_MYSQL_DUMP_MODE" == "incr" ] ; then
        # check if binlog is enabled
        egrep "^log-bin\s*=\s*/var/log/mysql/mysql-bin.log$" /etc/mysql/my.cnf > /dev/null
        if [ $? != 0 ] ; then
            echo "Line:"
            echo " log-bin=/var/log/mysql/mysql-bin.log" >&2
            echo "Not found in /etc/mysql/my.cnf." >&2
            echo "Please enable this for incremental backup" >&2
            exit 1
        fi
    fi

    lMySqlUserName=${lMySqlUserName:-'backup'}
    lMySqlPassword=${lMySqlPassword:-"$(</etc/isibackup/${OPT_SET}/mysql.backup.pw)"}
    lMySqlDumpTargetFile=${lMySqlDumpTargetFile:-"$lTargetDir/mysql.dump.bz2.gpg"}
    lMySqlDumpCommand="mysqldump -u '$lMySqlUserName' --max_allowed_packet=99M --password='$lMySqlPassword' --single-transaction --all-databases --flush-logs"
    lMySqlCompressCommand="| bzip2 | gpg --batch --encrypt $Recipient_Flags > '$lMySqlDumpTargetFile'"

    if [ -e "$lMySqlDumpTargetFile" ] ; then
        if [ ! -e "$lMySqlDumpTargetFile.old" ] ; then
            mv "$lMySqlDumpTargetFile" "$lMySqlDumpTargetFile.old"
        fi
    fi

    if [ "$OPT_MODE" == "full" ] ; then
        if [ "$OPT_MYSQL_DUMP_MODE" == "incr" ] ; then
          lMySqlDumpCommand="$lMySqlDumpCommand --delete-master-logs --master-data=2"
        fi
        dump_mysql
        rm -f "$lMySqlDumpTargetFile.old"
        # TODO: change_perms "$lMySqlDumpTargetFile"
        echo "result: $(ls -la $lMySqlDumpTargetFile)"
    else
        if [ "$OPT_MYSQL_DUMP_MODE" == "incr" ] ; then
            # if we make a incr backup, check that binlog is activiated and full backup is available.

	    lMySqlDumpCommand="$lMySqlDumpCommand --no-data"
            echo -n "flushing mysql logs..."
            if mysqladmin -u "$lMySqlUserName" --password="$lMySqlPassword" flush-logs ; then
                echo "done"
            else
                echo "failed" >&2
                exit 1
            fi
        else
            dump_mysql
        fi

    fi
fi

  ################
  ### postgres ###
  ################

if [ -d /var/lib/postgres ] ; then
    echo -n "dumping postgres data ..."
    lPostgresUserName="backup"
    lPostgresPassword="$(</etc/isibackup/${OPT_SET}/postgres.backup.pw)"
    lPostgresDumpTargetFile="$lTargetDir/postgres.dump.bz2.gpg"
    rm -f "${lPostgresDumpTargetFile}"
    sudo -u postgres pg_dumpall | bzip2 | eval gpg --batch --encrypt $Recipient_Flags > "$lPostgresDumpTargetFile"
    if [ -e "${lPostgresDumpTargetFile}" -a -s "${lPostgresDumpTargetFile}" ] ; then
	echo "done"
	# TODO: change_perms "$lPostgresDumpTargetFile"
	echo "result: $(ls -la $lPostgresDumpTargetFile)"
    else
	echo "failed"
	exit 1 >&2
    fi
fi
exit 0
