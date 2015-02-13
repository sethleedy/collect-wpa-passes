#!/bin/bash

#	This tool, dev by Seth Leedy - whitehat@sethleedy.name, is to auto update a WPA password list,
# stored in a sqlite3 database, and exportable to a normal text file.

#	First, it will convert if needed, all the files to Unix text standard using dos2unix.
#	Then, it will take all of the words, line by line of a input file(or all files within a different directory)
# and see if they need to be inserted as new. If new, it is given a priority of 1.
# 	If it is a duplicate, it is updated to a higher priority by 1, since it more common.
#  As more and more words are found duplicate, higher and higher will be the priorities of them.

#  When the words are to be exported, the default choice will be by the higher priority to lower within
# the text file.

#	All input words will be judged. If it is too short to use or too long, aka the password
# lengths as specified in WPA details, it will be removed(if short) or cut(if long).

# 	Using John the Ripper, mutations are made on all input words. (pass -> pass1,1pass,PASS1,1PASS,ect)
# before inclusion into the database.

#########################
#### Start Variables ####

this_version="0.2"
db_file="wpa_words_list.db"
temp_file="collect.tmp"
resume_file=".$db_file.resume"
last_execution_args=".$db_file.args"
last_command="Running"
pretend_mode=false
quiet_mode=false

intro="\n
========================================================\n
|C.W.P.\t\t\t\t\t\t|\n
|\tCollect WPA Passes\t\t\t\t|\n
|\t\t\t\t\t\t\t|\n
|\t\tCreated by Seth Leedy\t\t\t|\n
|\t\t\tWhiteHat@SethLeedy.Name\t\t|\n
|\t\t\t\t\t\t\t|\n
|\tVersion .1, 2013/10/22\t\t\t\t|\n
========================================================"

help="\n
========================================================\n
|\tCollect WPA Passes guide\t\t\t|\n
|\t\t-h This help\t\t\t\t|\n
|\tInputs into a SQLite Database\t\t\t|\n
|\t\t-id Input all files within a dir\t|\n
|\t\t\t(-id /root/passes)\t\t|\n
|\t!Do not use the same directory as this script!\t|\n
|\t\t-if Input one file\t\t\t|\n
|\t\t-of Output .txt file of WPA passes\t|\n
|\t\t-q Mute details and descriptions\t|\n
|\t\t-p Pretend,Print to screen the changes\t|\n
|\t-skip-txt-convert Skip the dos2unix tool usage\t|\n
|\t\t\t\t\t\t\t|\n
|\tControl \ = Safely stop the script for resuming\t|\n
|\t-r Resume last process if script was interrupted|\n
|\tPlease use the same commands as your last\t|\n
|execution when using -r, as found within the file\t|\n
|$last_execution_args\t\t\t\t|\n
========================================================\n"

#########################
#### Start Functions ####


# Send a "Ping" back to my server. This allows me to know that my script is being used out in the wild.
# The request will show up in my blog and I can parse it later for stats.
# Sends out this script version.
# Sends out the date/time ran.
function send_ping() {

	datetime=`date '+%Y-%m-%d-%R'`
	wget -qb -O /dev/null -U "CWP_Wget_v.$this_version" "http://techblog.sethleedy.name/?p=24518&datetime=$datetime&agent_code=CWP_Wget_v.$this_version" 1>/dev/null 2>&1

}

# Trap the Control Q event
function trap_shutdown() {

	# 2 = Control C OR SIGINT, Interrupt
	# 3 = Control \ OR SIGQUIT Quit
	trap 'set_shutdown' 2 3

}

# Do the setup of vars for safely shutting down the script for resuming
function set_shutdown() {

	do_shutdown=true
	echo "Shutting down the script."

	echo "$last_command" > "$resume_file"

}

function check_dependents() {

	hash john 2>/dev/null || { echo >&2 "I require john the ripper but it's not installed.  Aborting."; exit 1; }
	hash pw-inspector 2>/dev/null || { echo >&2 "I require pw-inspector but it's not installed.  Aborting."; exit 1; }
	hash cat 2>/dev/null || { echo >&2 "I require cat but it's not installed.  Aborting."; exit 1; }
	hash sqlite3 2>/dev/null || { echo >&2 "I require sqlite3 but it's not installed.  Aborting."; exit 1; }
	hash awk 2>/dev/null || { echo >&2 "I require awk but it's not installed.  Aborting."; exit 1; }
	hash dos2unix 2>/dev/null || { echo >&2 "I require dos2unix but it's not installed.  Aborting."; exit 1; }
	hash pwd 2>/dev/null || { echo >&2 "I require pwd but it's not installed.  Aborting."; exit 1; }
	hash readlink 2>/dev/null || { echo >&2 "I require readlink but it's not installed.  Aborting."; exit 1; }

	# Check if the DB File exists. If not, create it and fill it with structure.
	setup_db

	# Check if the Resume file exists and import it.
	if [ -f "$resume_file" ]; then
		last_resume_command=`cat "$resume_file"`
		echo "Last Resume command is: $last_resume_command"
	fi

}

# Check if the DB File exists. If not, create it and fill it with structure.
function setup_db() {

	#Create file if it does not exists
	if [ ! -f "$db_file" ]; then
		touch "$db_file"

		# Defining my databases first table
		STRUCTURE="CREATE TABLE if not exists wpapasses (id INTEGER PRIMARY KEY,prioritylvl INTEGER,pass TEXT);";

		# Creating an Empty db file and filling it with my structure
		cat /dev/null > "$db_file"
		echo $STRUCTURE > tmpstructure
		#echo $STRUCTURE
		sqlite3 "$db_file" < tmpstructure;

	fi
}

function compare_words() {

	# Getting my data
	LIST=`sqlite3 "$db_file" "SELECT prioritylvl,pass FROM wpapasses WHERE pass='$1'"`;

	# For each row
	# !! This needs to be better.!
	for ROW in $LIST; do
		#echo $ROW
		# Parsing data (sqlite3 returns a pipe separated string)
		# a[1] needs to match the SELECT order
		#id=`echo $ROW | awk '{split($0,a,"|"); print a[1]}'`
		prioritylvl=`echo $ROW | awk '{split($0,a,"|"); print a[1]}'`
		pass=`echo $ROW | awk '{split($0,a,"|"); print a[2]}'`

		# Printing my data
		#echo $pass

	done

	# NOT pretending and doing the SQL operations.
	# If no word was found within the DB, do insert else update.
	if [ "$pass" == "" ]; then
		if [ "$quiet_mode" != true ] && [ "$pretend_mode" != true ]; then
			echo "INSERTING $1."
		fi
		if [ "$pretend_mode" == true ]; then
			# Just pretending and outputting the changes to console.
			echo "Inserting $1."
		else
			insertion=`sqlite3 "$db_file" "INSERT INTO wpapasses (prioritylvl,pass) VALUES (1,'$1')"`;
			# Verify ?
		fi

	else
		if [ "$quiet_mode" != true ] && [ "$pretend_mode" != true ]; then
			echo "UPDATING $pass to priority level $prilvlplus."
		fi
		if [ "$pretend_mode" == true ]; then
			# Just pretending and outputing the changes to console.
			prilvlplus=$((prioritylvl+1))
			echo "Updating $pass to priority level $prilvlplus."
		else
			prilvlplus=$((prioritylvl+1))
			updating=`sqlite3 "$db_file" "UPDATE wpapasses SET prioritylvl='$prilvlplus' WHERE pass='$pass'"`;
		fi
	fi

}

function main_working_function() {
#echo "$do_resume"
	#First combine all wordlists into a single temp file. --> This should be more dynamic. Instead of one huge file, open each file in turn and go line by line.
	if [[ "$do_resume" == false ]] || [[ $do_resume == true && $last_command == "combine_words" ]]; then
		do_resume=false
		if [ "$directory_path" != "" ]; then
			if [ "$quiet_mode" != true ]; then
				echo "Combining all files(*.*) within directory: $directory_path."
			fi
			# Mark our spot for resuming
			echo "combine_words" > $resume_file
#			exit
			"cat" $directory_path/*.* >> $temp_file
		fi
		if [ "$input_file" != "" ]; then
			if [ "$quiet_mode" != true ]; then
				echo "Sourcing the input file: $input_file."
			fi
			# Mark our spot for resuming
			echo "combine_words" > $resume_file
#			exit
			"cat" $input_file > $temp_file
		fi
	fi
#exit
	# Convert any windows text files to unix type
	#	-n, --newfile INFILE OUTFILE ...
    #	       New file mode. Convert file INFILE and write output to file OUTFILE.  File names must be given in pairs and wildcard names should not be
    #	       used or you will lose your files.
	if [[ $do_resume == false || ($do_resume == true && $last_command == "convert_words") ]]; then
		do_resume=false
		if [ "$skip_txt_convert" != true ]; then
			if [ "$quiet_mode" != true ]; then
				echo "Converting the temp text file to unix standard."
			fi
			# Mark our spot for resuming
			echo "convert_words" > $resume_file
			mv "$temp_file" "$temp_file.old"
			dos2unix -n "$temp_file.old" "$temp_file"
		fi
	fi

	# Split the file into manageable pieces.
	# Had to do this because john tool was borking on a 2.3 gig file.
	if [[ $do_resume == false || ($do_resume == true && $last_command == "split_words") ]]; then
		do_resume=false
		echo "split_words" > $resume_file
		split -d -b 200m "$temp_file" tsplit_
		rm $temp_file
	fi

	#Make mutations of these words with john the ripper
	# This command could make a large difference in the variants. Make it better ?
	# Each time we take in already variant words, it makes it even more varied. This can get ugly. Solution ?
	if [[ $do_resume == false || ($do_resume == true && $last_command == "mutate_words") ]]; then
		do_resume=false
		if [ "$quiet_mode" != true ]; then
			echo "Mutating the words to get derivative words."
		fi
		echo "mutate_words" > $resume_file
		for file in tsplit_*
		do
			john -w:$file -rules -session:johnrestore.dat -stdout:63 >> new_$temp_file
			rm $file
		done
		rm tsplit_*
	fi

	# Remove any too short or too long words. Makes it the right length for WPA.
	if [[ $do_resume || ($do_resume == true && $last_command == "trim_words") ]]; then
		do_resume=false
		if [ "$quiet_mode" != true ]; then
			echo "Chopping any words that are too short or long to fit WPA passwords"
		fi
		echo "trim_words" > $resume_file
		"cat" new_$temp_file | pw-inspector -m 8 -M 63 > WPA_lengthed_$temp_file
		rm new_$temp_file
	fi


	# Check line by line to see if the new additions will have duplicates without redoing the ordering or the output_file
	if [[ $do_resume || ($do_resume == true && $last_command == "compare_words") ]]; then
		do_resume=false
		echo "compare_words" > $resume_file
		for i in `cat WPA_lengthed_$temp_file`
		do
			# Call function to insert or update the SQLITE
			compare_words $i
			#echo " "
		done
		rm WPA_lengthed_$temp_file
	fi
}

# Write SQL output to text file
function write_output() {

	write_out=`sqlite3 "$db_file" "SELECT prioritylvl,pass FROM wpapasses ORDER BY prioritylvl DESC" > "$output_file"`

}

function clean_up() {

	# remove some temp files if present.
	rm -f WPA_lengthed_$temp_file
	rm -f new_$temp_file
	rm -f $temp_file
	rm -f tmpstructure
}
#### End Functions ####
#######################

####################
#### Start Code ####

# See if all required programs are present.
check_dependents

# Clean up any files that were left behind from a prev killed script run.
clean_up

# Check arguments

if [ $# -eq 0 ]; then
	clear
	echo -e $intro
	echo -e $help
	clean_up
	exit 1
fi


until [ -z "$1" ]; do

	if [ "$1" == "-h" ]; then
		clear
		#echo -e $intro
		echo -e $help
		clean_up
		exit
	fi

	if [ "$1" == "-id" ]; then
		shift
		directory_path="$1"
		# Remove the end / and expand the path
		directory_path=`readlink -f $directory_path`
	fi

	if [ "$1" == "-if" ]; then
		shift
		input_file="$1"
	fi

	if [ "$1" == "-of" ]; then
		shift
		output_file="$1"
	fi

	if [ "$1" == "-p" ]; then
		pretend_mode=true
		echo "Pretend mode active."
		sleep 2
	fi

	if [ "$1" == "-q" ]; then
		quiet_mode=true
	fi

	if [ "$1" == "-skip-txt-convert" ]; then
		skip_txt_convert=true
	fi

	if [ "$1" == "-r" ]; then
		do_resume=true
	else
		do_resume=false
	fi

	shift
done

#echo "1 $do_resume"

# Write out a .hidden file containing the last command use. Used for -r resuming.
echo "$0 $*" > $last_execution_args

# Make sure we have a input source
#if [ "$directory_path" == "" ] && [ "$input_file" == "" ]; then
#	echo "Please include a wordlist source. See $0 -h."
#	clean_up
#	exit 1
#fi

if [ "$directory_path" == "" ] && [ "$input_file" == "" ]; then

	if [ "$quiet_mode" != true ]; then
		echo "No input files to process."
	fi

else

	# Make sure it is not the same directory this script is running from.
	# I am trying to avoid importing the script and the sqlite database into the script database :).
	if [ "$directory_path" == `pwd` ] || [ `pwd | rev | cut -d "/" -f 1 | rev` == "$directory_path" ] || [ "$directory_path" == "." ]; then
		echo "Change the input source directory to something other than this $0 script location."
		clean_up
		exit 1
	fi

	# Ready to work.
	main_working_function
fi

# Write out a file of the words collected so far.
if [[ $do_resume == false || ($do_resume == true && $last_command == "write_words") ]]; then
	do_resume=false
	echo "write_words" > $resume_file
	if [ "$output_file" != "" ]; then
		write_output
	fi
fi

# Clean up after myself
clean_up

# Send Ping
if [ "$quiet_mode" != true ]; then
	echo "Sending ping.."
fi
send_ping

exit 0
