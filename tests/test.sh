#!/bin/bash
TEST_DIR=/tmp/isibackup_test
MYSQL_OPTIONS="-u root -ptest"
ENABLE_MYSQL_TEST=no

KEEP_CONFIG=false
NET=$(hostname -d)
HOST=$(hostname -s)

SPECIAL_CHARS_TEST=yes
# ~ FUNCTIONIERT NICHT!!
SPECIALS="äöü+\"*ç%&\\()=?^'\`\!\${};:,.<>°§|@#3"    
MAPPED_SPECIALS="%e4%f6%fc%2b%22%2a%e7%25%26%5c%28%29%3d%3f%5e%27%60%5c%21%24%7b%7d%3b%3a%2c.%3c%3e%b0%a7%7c%40%233"

LINK_TEST=no
MYSQL_BACKUP_DIR="/var/tmp/mysql_original_$(date +%F)"
ISIBACKUP_OPTIONS="--logdir=$TEST_DIR/log --configdir=./conf --write-debuglog --ui console"
if [ $ENABLE_MYSQL_TEST != "yes" ] ; then
    ISIBACKUP_OPTIONS="$ISIBACKUP_OPTIONS --skip-pre-commands"
fi
FULL_ORIG_BACKUP_DIR=$TEST_DIR/backup/test/full/$NET/$HOST/

# TODO: Test with different packer and compressors (cpio/tar/zip, bzip2/gzip)
# TODO: Test what happens when during backup something is written

#rm -rf $TEST_DIR/
mkdir -p $TEST_DIR/backup
mkdir -p $TEST_DIR/log


cd "$(dirname "$0")"

function show_statistic {
    log_dir=$(ls -ld $TEST_DIR/backup/test/*/*/*/*/isibackup  $TEST_DIR/backup/test/*/*/*/isibackup 2>/dev/null | cut -d " " -f 6,7,8 | sort | tail -1 | cut -d " " -f 3)
    
    cat $log_dir/statistics.txt
}

function assert_statistic {
    log_dir=$(ls -ld $TEST_DIR/backup/test/*/*/*/*/isibackup  $TEST_DIR/backup/test/*/*/*/isibackup 2>/dev/null | cut -d " " -f 6,7,8 | sort | tail -1 | cut -d " " -f 3)
    
    regexp="$1\s*\:\s*$2"
    egrep $regexp $log_dir/statistics.txt    
    if [ $? != 0 ] ; then
	echo "No line matches: '$regexp' in statfile: $log_dir/statistics.txt"
	exit 1
    fi
}

function assert_file_exist {
    if [ ! -e "$1" ] ; then
	echo "$1 does not exist"
	exit 1
    fi
}

function assert_file_not_exist {
    if [ -e "$1" ] ; then
	echo "$1 does exist but shouldn't"
	exit 1
    fi
}

function test() {
    echo "----------------------------------------------"
    echo "---------------> Testing $1 <-----------------"
    echo "----------------------------------------------"
    if [ "$1" != "restore" ] ; then 
	./test.sh $1 $2
	if [ $? == 0 ] ; then
	    echo "Exit code ok."
	else
	    echo "ERROR EXECUTING TEST $1"
	    exit 1
	fi
    fi

    if [ "$1" == "collect-only" -o "$1" == "collect" -o "$1" == "backup" ] ; then
	exit 0
    fi

    find $TEST_DIR/backup -name "*.cpio.bz2.gpg" | 
    grep -v "isibackup.dirlist.cpio.bz2.gpg" | 
    grep -v "big_file.cpio.bz2.gpg" | 
    grep -v "$HOST/rootdir.cpio.bz2.gpg" | 
    grep -v "lot/lot_" | 
    grep -v "big_file_FILE_.cpio.bz2.gpg" | 
    while read f ; do
	expected_dir_name="$(basename "$(dirname "$f")")"
	if [ "$expected_dir_name.cpio.bz2.gpg" != "$(basename "$f")" ] ; then
	    echo "Unexpected packfile: $f"
	    exit 1
	fi
    done
    if [ $? != 0 ] ; then exit 1 ; fi

    fl=$TEST_DIR/backup_filelist
    find $TEST_DIR/backup > $fl
    if grep "empty_directory/filelist.bz2" "$fl" ; then
	echo "filelist.bz generated in empty directory."
	exit 1
    fi
    
    

    if ./test.sh restore == "0"; 
	then 
	echo "----------------------------------------------"
	echo "---------------> Testing $1 $2 OK <--------------"
	echo "----------------------------------------------"
	echo "TEST OK"
    else
	echo "$?"
	echo "----------------------------------------------"
	echo "---------------> Testing $1 $2 ERROR <-----------"
	echo "----------------------------------------------"
    exit 1;
    fi
    
}

function remove_dir_trap () {
    echo "TRAP"
    sudo rm -rf $1
    trap - INT TERM EXIT
}

function save_mysql() {
    if [ $ENABLE_MYSQL_TEST == "yes" ] ; then
    # save data and binlog dir to temporary directory.
	echo "Saving mysql data and binlog to '$1'"
	set -e
	trap "remove_dir_trap $1" INT TERM EXIT
	sudo mkdir -p $1
	sudo rm -rf $1/binlog
	sudo rm -rf $1/data
	echo "Stopping mysql"
	sudo /etc/init.d/mysql stop
	echo "Copying mysql data to $1/data"
	sudo cp -pr /var/lib/mysql $1/data
	echo "Copying mysqllog to $1/binlog"
	sudo cp -pr /var/log/mysql $1/binlog
	echo "Starting mysql"
	sudo /etc/init.d/mysql start
	echo "Saving mysql data and binlog done."
	trap - INT TERM EXIT
	set +e
    fi
}

function restore_mysql() {
    if [ $ENABLE_MYSQL_TEST == "yes" ] ; then
    # recreate mysql to state before restore
	echo "Restoreing mysql data and binlog from '$1'"
	echo "Stopping mysql"
	sudo /etc/init.d/mysql stop
	echo "Removing current mysql data."
	sudo rm /var/lib/mysql -rf
	sudo rm /var/log/mysql -rf
	echo "Copying mysql data from $1/data"
	sudo cp -rp $1/data /var/lib/mysql
	echo "Copying mysqllog from $1/binlog"
	sudo cp -rp $1/binlog /var/log/mysql
	echo "Starting mysql"
	sudo /etc/init.d/mysql start
	if [ $? != 0 ] ; then
	    echo "Database could not be rewinded to before restore state."
	    exit 1
	fi
	echo "Restore done."
    fi
}

function create_database() {
    if [ $ENABLE_MYSQL_TEST == "yes" ] ; then
	echo "----------------------------------------------"
	echo "-------> Creating Testdatabase 'isibackup_test_$1' <--------"
	echo "----------------------------------------------"

    # create database with that name
	mysql $MYSQL_OPTIONS -e "CREATE DATABASE isibackup_test_$1"
	
    # copy binlogs to target
	mkdir -p $TEST_DIR/original/var/log
	sudo rm -rf $TEST_DIR/original/var/log/mysql
	sudo cp -r /var/log/mysql $TEST_DIR/original/var/log/mysql
	sudo chown -R $(whoami).$(whoami) $TEST_DIR/original/var/log/mysql
    fi
}

function create_testdata() {
    DIR=$1
    echo "----------------------------------------------"
    echo "-------> Creating Testdata in '$DIR' <--------"
    echo "----------------------------------------------"
    echo "Creating files with special names."
    
    # create a file in root
    mkdir -p $DIR
    touch "$DIR/file_in_root"
    
    mkdir -p $DIR/special_names

    if [ $SPECIAL_CHARS_TEST == "yes" ] ; then
	mkdir -p "$DIR/special_names/$SPECIALS/$SPECIALS 2"
	dd if=/dev/urandom of="$DIR/special_names/$SPECIALS/$SPECIALS" bs=1024 count=10 2>&1 | grep -v records | grep -v copied
	dd if=/dev/urandom of="$DIR/special_names/$SPECIALS/$SPECIALS 2/$SPECIALS" bs=1024 count=10 2>&1 | grep -v records | grep -v copied
	dd if=/dev/zero of="$DIR/special_names/$SPECIALS/$SPECIALS big_file" bs=1M count=3 2>&1 | grep -v records | grep -v copied
    fi
    dd if=/dev/urandom of="$DIR/special_names/sdlfj     slkdfj" bs=1024 count=10 2>&1 | grep -v records | grep -v copied
    dd if=/dev/urandom of="$DIR/special_names/ALOTOFCHARACTERSSssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssss" bs=1024 count=10 2>&1 2>&1 | grep -v records | grep -v copied
    dd if=/dev/urandom of="$DIR/special_names/-start with a minus" bs=1024 count=10 2>&1 2>&1 | grep -v records | grep -v copied
    mkdir "$DIR/special_names/-0000000000000000-0000001800"    
    dd if=/dev/urandom of="$DIR/special_names/-0000000000000000-0000001800/file" bs=1024 count=10 2>&1 2>&1 | grep -v records | grep -v copied
    mkdir -p "$DIR/special_names/.hidden/.hadden"
    dd if=/dev/urandom of="$DIR/special_names/.hidden/.hadden/.file" bs=1024 count=1 2>&1 | grep -v records | grep -v copied
    mkdir -p "$DIR/Dir with space"
    mkdir -p "$DIR/Dir with space2"    
    touch "$DIR/Dir with space2/file with space"

    # create some symbolic links
    ln -s "$DIR/Dir with space" "$DIR/link_to_dir_with_space"
    if [ $SPECIAL_CHARS_TEST == "yes" ] ; then
	ln -s "$DIR/special_names/$SPECIALS" "$DIR/link_to_dir_with_special name"
    fi
    ln -s "$TEST_DIR/must_exist_for_diff_check" "$DIR/link_to_nowhere"
    ln -s "$TEST_DIR/must_exist_for_diff_check" "$DIR/second_link_to_nirvana"

    mkdir -p "$DIR/Maildir/cur"
    dd if=/dev/urandom of="$DIR/Maildir/cur/1211791991.M879888P3858V000000000000FD00I006A403C_0.host,S=95892163:2,S" bs=1024 count=10 2>&1 2>&1 | grep -v records | grep -v copied

    mkdir -p "$DIR/special_names/directory_with_only_directories/empty_directory"

    mkdir -p $DIR/empty/empty
    mkdir -p $DIR/empty2/empty
    touch $DIR/empty2/empty/empty
    
    mkdir -p $DIR/random
    echo "Creating random data."
    for num in `seq 100`; do
	echo -n "*"
	dd if=/dev/urandom of=$DIR/random/$num.rnd bs=1024 count=10 2>&1 | grep -v records | grep -v copied
    done
    echo "done"

    mkdir -p $DIR/lot
    echo "Creating a lot of files."
#    dd if=/dev/zero of=$DIR/lot/1k_ref.rnd bs=1024 count=1 2>&1 | grep -v records | grep -v copied
#    dd if=/dev/zero of=$DIR/lot/10k_ref.rnd bs=1024 count=10 2>&1 | grep -v records | grep -v copied
#    dd if=/dev/zero of=$DIR/lot/33k_ref.rnd bs=1024 count=33 2>&1 | grep -v records | grep -v copied
    dd if=/dev/zero of=$DIR/lot/10k_ref.rnd bs=1024 count=10 2>&1 | grep -v records | grep -v copied
    dd if=/dev/zero of=$DIR/lot/300k_ref.rnd bs=1024 count=300 2>&1 | grep -v records | grep -v copied
    dd if=/dev/zero of=$DIR/lot/700k_ref.rnd bs=1024 count=700 2>&1 | grep -v records | grep -v copied
    for num in `seq 100`; do
#    for num in `seq 1000`; do
	echo -n "*"
#	cp $DIR/lot/1k_ref.rnd $DIR/lot/10k_$num.rnd
#	cp $DIR/lot/10k_ref.rnd $DIR/lot/10k_$num.rnd
#	cp $DIR/lot/33k_ref.rnd $DIR/lot/300k_$num.rnd

	cp $DIR/lot/10k_ref.rnd $DIR/lot/10k_$num.rnd
	cp $DIR/lot/300k_ref.rnd $DIR/lot/300k_$num.rnd
	cp $DIR/lot/700k_ref.rnd $DIR/lot/700k_$num.rnd
    done
    echo "done"
	
 
    mkdir -p $DIR/big_file
    dd if=/dev/zero of=$DIR/big_file/big_file bs=1M count=3 2> /dev/null
    dd if=/dev/zero of=$DIR/big_file/small_file_for_collect_mode bs=1M count=1 2> /dev/null

#    echo "Creating sparse files."
#    mkdir -p $DIR/sparse
#    dd if=/dev/zero of=$DIR/sparse/file1.sparse bs=1M count=1 seek=1200  2> /dev/null
#    dd if=/dev/zero of=$DIR/sparse/file2.sparse bs=1M count=1 seek=1300  2> /dev/null

    mkdir -p $DIR/sbin
    #echo "Copying /usr/bin directory."
    #cp /usr/sbin/* $DIR/sbin

}

function assert_testdata() {
    if [ ! -e $TEST_DIR/original ]; then
	echo "Test directory '$TEST_DIR/original' does not exist!!"
	exit 1
    fi
}

if [ ! -f "conf/defaults.conf" -o ! -f "conf/isibackup.conf" ] ; then
	cp ../conf/defaults.conf conf
	cp ../conf/isibackup.conf conf
	cp ../conf/mount_points conf
	patch conf/isibackup.conf <<EOF
1a2,5
> LOG_LEVEL=
> LOG_DIR=/tmp/isibackup_test/log
> DEFAULT_PATH_STATE=/tmp/isibackup_test/backup/state
> CPIO_MAX_SIZE=4000000000
20c24
< CRYPT_KEYS="Backup"
---
> CRYPT_KEYS="Flavio Pellanda (Logintas 2008); Management Backup (Logintas 2008) <mgmt-backup@logintas.ch>"
32c36
< BACKUP_ROOT=/var/backups/isibackup
---
> BACKUP_ROOT=/tmp/isibackup_test/backup
43,44c47,48
< #IDENT_USER_BACKUP=backup
< #IDENT_GROUP_BACKUP=backup
---
> IDENT_USER_BACKUP=
> IDENT_GROUP_BACKUP=
EOF

        cp conf/isibackup.conf conf/isibackup-tar.conf
	patch conf/isibackup-tar.conf <<EOF
17c17
< OPT_PACKMETHOD=cpio.bz2
---
> OPT_PACKMETHOD=tar.bz2
EOF

fi

SCRIPT_SHELL=ruby

if [ -z "$1" -o "$1" == "debug" ] ; then
	set -- all "$1"
fi
if [ "$2" == "debug" ]; then
    SHELL_ARGS=-vx
else
    if [ -z "$2" ] ; then
	ISIBACKUP_OPTIONS="$ISIBACKUP_OPTIONS --progress"
    else
	ISIBACKUP_OPTIONS="$ISIBACKUP_OPTIONS $2"
    fi
fi

export PATH_LIB=..
if [ $ENABLE_MYSQL_TEST == "yes" ] ; then
    if [ ! -d $MYSQL_BACKUP_DIR ] ; then
	echo ""
	echo "I will save the mysql data and binlog directory"
	echo "to $MYSQL_BACKUP_DIR. This database"
	echo "Will be the basis for our test. Recall the"
	echo "Database by ./test.sh clean."
	echo "/!\ EXECUTION MYSQLRESTORE AS ROOT - DO NOT "
	echo "CONTINUE IF YOU HAVE PRODUCTIVE DATA IN YOUR MYSQL!!"
	echo "YOU CAN LOOSE ALL YOUR MYSQL DATA IF SOME ERROR"
	echo "HAPPENS!!"
 	echo ""
	echo "Press enter to continue."
	
	
	read 
	save_mysql $MYSQL_BACKUP_DIR
    fi
fi

USE_CONFIG=conf/isibackup.conf
if [ "$2" == "tar" ] ; then
  USE_CONFIG=conf/isibackup-tar.conf
fi

case "$1" in
        data)
	create_testdata $TEST_DIR/original
	create_database data
	;;
 	clean)
	rm -rf $TEST_DIR
	if [ $ENABLE_MYSQL_TEST == "yes" ] ; then restore_mysql $MYSQL_BACKUP_DIR ; fi
#	rm -rf $MYSQL_BACKUP_DIR
	;;
 	full)
 	        assert_testdata
		$SCRIPT_SHELL $SHELL_ARGS ../isibackup-main $ISIBACKUP_OPTIONS --config=$USE_CONFIG --backup --full --set test
		if [ $? != 0 ] ; then exit 1 ; fi
		show_statistic
		;;                
	diff|incr)
	assert_testdata
		$SCRIPT_SHELL $SHELL_ARGS ../isibackup-main $ISIBACKUP_OPTIONS --backup "--$1" --dir-numbering --set test
		show_statistic
		if [ $? != 0 ] ; then exit 1 ; fi
		;;
	collect)
		if [ -e $TEST_DIR/backup.sav ] ; then
		    echo "Rmoving old backup.sav directory $TEST_DIR/backup.sav"
		    rm -rf $TEST_DIR/backup.sav
		fi

	        rm -rf $TEST_DIR/original
	        rm -rf $TEST_DIR/backup
		mkdir -p $TEST_DIR/backup
		
		create_testdata $TEST_DIR/original
		mkdir -p $TEST_DIR/original/var/log/mysql/backup
		create_database original
	        
		test full

		touch $TEST_DIR/original/big_file/small_file2_in_big_file_dir
		touch $TEST_DIR/original/random/16.rnd

		mkdir -p $TEST_DIR/original/new
		echo "Moving $TEST_DIR/original/random  to $TEST_DIR/original/new/moved_from_old_random"
	        mv $TEST_DIR/original/random  $TEST_DIR/original/new/moved_from_old_random
		
		test incr

		test collect-only
		;;
        collect-only)

		if [ -e $TEST_DIR/backup.sav ] ; then
		    rm -rf $TEST_DIR/backup
		    mv $TEST_DIR/backup.sav $TEST_DIR/backup
		fi
		rm -rf $TEST_DIR/collect

		# rsync to another backup directory
                #    $SCRIPT_SHELL $SHELL_ARGS ../isibackup-main $ISIBACKUP_OPTIONS --collect-content --remote-set data --remote-host aristoteles --host test --net example.com --archive $TEST_DIR/collect
		# $SCRIPT_SHELL $SHELL_ARGS ../isibackup-main $ISIBACKUP_OPTIONS "--$1" --remote-user $(whoami) --remote-host localh --remote-path $TEST_DIR/backup --archive $TEST_DIR/collect


		mkdir -p $TEST_DIR/backup/test/full/$NET/anotherhost
		touch $TEST_DIR/backup/test/full/$NET/anotherhost/isis
		mkdir -p $TEST_DIR/backup/test/incr/$NET/2009-01-01/anotherhost
		touch $TEST_DIR/backup/test/incr/$NET/2009-01-01/anotherhost/isis

		echo "Executing rsyncs"

		COLLECT_COMMAND="$SCRIPT_SHELL $SHELL_ARGS ../isibackup-main $ISIBACKUP_OPTIONS --remote-set test --host $HOST --net $NET --remote-host $HOST.$NET"

		NO_RSYNC_LOGIN_FOR_TEST=true $COLLECT_COMMAND --collect-content --remote-path $TEST_DIR/backup --archive $TEST_DIR/collect
		if [ $? != 0 ] ; then exit 1 ; fi

		NO_RSYNC_LOGIN_FOR_TEST=true $COLLECT_COMMAND --collect-state --remote-path $TEST_DIR/backup --archive $TEST_DIR/collect

		if [ $? != 0 ] ; then exit 1 ; fi

		# the following files may not be synct too
		assert_file_not_exist $TEST_DIR/collect/test/full/$NET/anotherhost
		assert_file_not_exist $TEST_DIR/collect/test/incr/$NET/2009-01-01/anotherhost


		rm -rf $TEST_DIR/collect/test/full/$NET/$HOST/TODELETE
		mkdir -p $TEST_DIR/backup/test/full/$NET/$HOST/TODELETE
		touch $TEST_DIR/backup/test/full/$NET/$HOST/TODELETE/file
		rm -rf $TEST_DIR/backup/test/full/$NET/$HOST/TOCOPY
		mkdir -p $TEST_DIR/collect/test/full/$NET/$HOST/TOCOPY
		touch $TEST_DIR/collect/test/full/$NET/$HOST/TOCOPY/file
		
		# the files still must exist after a collect
		# with delete in the other direction
		NO_RSYNC_LOGIN_FOR_TEST=true $COLLECT_COMMAND --collect-content --rsync-add-option "--delete" --remote-path $TEST_DIR/collect --archive $TEST_DIR/backup
		if [ $? != 0 ] ; then exit 1 ; fi
		assert_file_not_exist $TEST_DIR/backup/test/full/$NET/$HOST/TODELETE
		assert_file_exist $TEST_DIR/backup/test/full/$NET/$HOST/TOCOPY/file
		assert_file_exist $TEST_DIR/backup/test/full/green.lakestreet1.ch/anotherhost
		assert_file_exist $TEST_DIR/backup/test/incr/green.lakestreet1.ch/2009-01-01/anotherhost

		rm -rf $TEST_DIR/collect/test/full/$NET/$HOST/TODELETE
		rm -rf $TEST_DIR/*/test/full/$NET/$HOST/TOCOPY

		echo "Checking backups"

		# restore must still work for original directory
		test restore

		# restore must work for collected directory		
		mv $TEST_DIR/backup $TEST_DIR/backup.sav
		mv  $TEST_DIR/collect $TEST_DIR/backup
		test restore

		;;
	restore)
	assert_testdata
	        if [ $ENABLE_MYSQL_TEST == "yes" ] ; then
		    save_mysql ${TEST_DIR}_mysql
		    
 		    # mysqldump before restore
		    rm -rf $TEST_DIR/mysql_dump_before_restore
		    mysqldump $MYSQL_OPTIONS -A | grep -v "Dump completed on" > $TEST_DIR/mysql_dump_before_restore
		    mysql $MYSQL_OPTIONS -e "CREATE DATABASE isibackup_test_if_exist_no_restore_performed"
		fi
	
	        rm -rf $TEST_DIR/restore/
        	export ISIBACKUP_CONFIGDIR=./conf
		echo "Executing isirestore"
		$SCRIPT_SHELL $SHELL_ARGS ../isirestore-main --restore --source-dir=$TEST_DIR/backup --target-dir=$TEST_DIR/restore --net $NET --host $HOST --set test

		if [ $? != 0 ] ; then
		    echo "Error restoring data"
		    exit 1
		fi
		
		touch "$TEST_DIR/must_exist_for_diff_check"
		echo "Comparing '$TEST_DIR/restore' with '$TEST_DIR/original'"
		if diff -r $TEST_DIR/restore $TEST_DIR/original; then
		    echo "OK, no differences between restore and original."
		else
		    echo "ERROR: THE RESTORE DIRECTORY DIFFER!"
		    exit 1
		fi

		pushd $TEST_DIR/restore
		ls -RAlL --full-time > $TEST_DIR/restore.list
		popd
		
		pushd $TEST_DIR/original
		ls -RAlL --full-time > $TEST_DIR/original.list
		popd

		if diff $TEST_DIR/restore.list $TEST_DIR/original.list ; then
		    rm "$TEST_DIR/must_exist_for_diff_check"
		    echo "OK, no differences between restore and original listentries."
		else
		    rm "$TEST_DIR/must_exist_for_diff_check"
		    echo "ERROR: THE RESTORE DIRECTORY DIFFER IN LIST ENTRIES!"
		    exit 1
		fi



	        if [ $ENABLE_MYSQL_TEST == "yes" ] ; then
		    sudo rm -rf /var/log/mysql
		    sudo cp -r $TEST_DIR/restore/var/log/mysql /var/log/mysql
		    sudo chown -R root.root /var/log/mysql
		    sudo $SCRIPT_SHELL $SHELL_ARGS ../isirestore-main --force --restore-mysql --source-dir=$TEST_DIR/restore

		    if [ $? != 0 ] ; then
			echo "Error restoring mysql"
			exit 1
		    fi


		    if mysql $MYSQL_OPTIONS -e"SHOW DATABASES" | grep  isibackup_test_if_exist_no_restore_performed ; then
			echo "ERROR, database has not been restored."
			echo "Database isibackup_test_if_exist_no_restore_performed still exist."
			exit 1
		    else
			echo "OK, database has been restored."
		    fi
		    
  		    # mysqldump after restore
		    rm -rf $TEST_DIR/mysql_dump_after_restore
		    mysqldump $MYSQL_OPTIONS -A | grep -v "Dump completed on" > $TEST_DIR/mysql_dump_after_restore
		    
		    
		    if diff $TEST_DIR/mysql_dump_before_restore $TEST_DIR/mysql_dump_after_restore; then
			echo "OK, no difference between database restores found."
	    else
			echo "ERROR: Restored database differ!! The original dumps can be found at:"
			echo " $TEST_DIR/mysql_dump_before_restore"
			echo " $TEST_DIR/mysql_dump_after_restore"
			echo "use 'cat $TEST_DIR/mysql_dump_before_restore | mysql $MYSQL_OPTIONS' to restore it"
			exit 1
		    fi
		fi
		    
	        if [ $ENABLE_MYSQL_TEST == "yes" ] ; then restore_mysql ${TEST_DIR}_mysql ; fi
		;;
	backup)	
	        if [ $ENABLE_MYSQL_TEST == "yes" ] ; then restore_mysql $MYSQL_BACKUP_DIR ; fi
	        rm -rf $TEST_DIR/original

		if [ $ENABLE_MYSQL_TEST == "yes" ] ; then
		    mysql $MYSQL_OPTIONS -e "show databases" | cut -d ' ' -f 2 | grep isibackup_test | while read db
		      do 
		      echo "Removing test db $db"
		      mysql $MYSQL_OPTIONS -e "DROP DATABASE $db"
		    done 
		fi

	        rm -rf $TEST_DIR/backup
		mkdir -p $TEST_DIR/backup

		create_testdata $TEST_DIR/original
		mkdir -p $TEST_DIR/original/var/log/mysql/backup
		create_database original
	        
		test full

		assert_file_exist "$FULL_ORIG_BACKUP_DIR/big_file/big_file.cpio.bz2.gpg"
		assert_file_exist "$FULL_ORIG_BACKUP_DIR/rootdir.cpio.bz2.gpg"
		assert_file_exist "$FULL_ORIG_BACKUP_DIR/special_names/$MAPPED_SPECIALS/$MAPPED_SPECIALS 2/$MAPPED_SPECIALS 2.cpio.bz2.gpg"
		assert_file_exist "$TEST_DIR/original/special_names/$SPECIALS/$SPECIALS 2"

		assert_statistic directories_total 25
		assert_statistic files_mode_collect 116
		assert_statistic files_mode_separate 2
		
		touch $TEST_DIR/original/big_file/small_file_for_collect_mode

		test full tar

		assert_file_exist "$FULL_ORIG_BACKUP_DIR/isibackup.dirlist.tar.bz2.gpg"
		assert_file_exist "$FULL_ORIG_BACKUP_DIR/big_file/big_file.tar.bz2.gpg"

		rm $TEST_DIR/original/big_file/small_file_for_collect_mode

		rm -r "$TEST_DIR/original/special_names/$SPECIALS/$SPECIALS 2"

		test full

		assert_file_not_exist "$FULL_ORIG_BACKUP_DIR/big_file/big_file.cpio.bz2.gpg"
		assert_file_not_exist "$FULL_ORIG_BACKUP_DIR/special_names/$MAPPED_SPECIALS/$MAPPED_SPECIALS 2/$MAPPED_SPECIALS 2.cpio.bz2.gpg"
		assert_file_exist "$FULL_ORIG_BACKUP_DIR/big_file/big_file_FILE_.cpio.bz2.gpg" ]

		touch $TEST_DIR/original/big_file/small_file_for_collect_mode
		rm $TEST_DIR/original/big_file/big_file

		assert_statistic directories_changed 2
		assert_statistic files_mode_collect 0
		assert_statistic files_mode_separate 0
		assert_statistic directories_removed 1
		assert_statistic files_removed 1

		test full

		assert_file_not_exist "$FULL_ORIG_BACKUP_DIR/big_file/big_file_FILE_.cpio.bz2.gpg"
		assert_file_exist "$FULL_ORIG_BACKUP_DIR/big_file"

		rm -r $TEST_DIR/original/big_file

		assert_statistic directories_changed 1
		assert_statistic files_mode_collect 1
		assert_statistic files_removed 1

		test full

		assert_file_not_exist "$FULL_ORIG_BACKUP_DIR/big_file" ]
		assert_statistic directories_removed 1

		# now create some files
		mkdir -p $TEST_DIR/original/new
		create_testdata $TEST_DIR/original/new		
		create_database original_new

		MAIL_FILE="Maildir/cur/1111791991.M879888P3858V000000000000FD00I006A403C_0.host,S=95892163:2,S"
		dd if=/dev/urandom of="$TEST_DIR/original/$MAIL_FILE" bs=1024 count=10 2>&1 2>&1 | grep -v records | grep -v copied

		test incr

		touch $TEST_DIR/original/new/big_file/small_file2_in_big_file_dir
		touch $TEST_DIR/original/new/random/16.rnd
		touch $TEST_DIR/original/random/16.rnd
		
		test incr

		assert_statistic files_changed 2
		assert_statistic files_new 1

	        mv $TEST_DIR/original/random  $TEST_DIR/original/new/random/moved_from_old_random
		
		test incr

#		echo $TEST_DIR/restore/test/incr/$((date +%F))_0/$HOST/tmp/isibackup_test/original/Maildir/cur/$MAIL_FILE.cpio.bz2.gpg
#		exit 0

		# now delete some files
	        rm -rf $TEST_DIR/original/random/1*
		test incr

		test full

		# now the random directory in the full backup should be gone
		random_dir="$TEST_DIR/backup/test/full/$NET/*/tmp/isibackup_test/original/random"		
		echo $random_dir
		if [ -e $random_dir ] ; then
		    echo ""
		    echo "FAILED: Deleted directory not removed from full backup $random_dir"
		    exit 1
		fi

		mkdir -p $TEST_DIR/original/new2
		create_testdata $TEST_DIR/original/new2
		create_database original_new2

		test incr

		mkdir -p $TEST_DIR/original/new3
		create_testdata $TEST_DIR/original/new3
		create_database original_new3

		test incr

		mkdir -p $TEST_DIR/original/new4
		create_testdata $TEST_DIR/original/new4
		create_database original_new4
		
		exit 0
		
		test diff

		mkdir -p $TEST_DIR/original/new5
		create_testdata $TEST_DIR/original/new5
		create_database original_new5
		
		test diff

		rm -rf $TEST_DIR/original/random

		test incr
		;;
        all)
	        test backup
		test collect
	        ;;

	*)
		echo "Error. Invalid command specified. RTFS for usage."
		;;
esac

if [ "$KEEP_CONFIG" == "false" ] ; then
	rm conf/isibackup.conf
	rm conf/isibackup-tar.conf
	rm conf/defaults.conf
	rm conf/mount_points
fi

exit 0