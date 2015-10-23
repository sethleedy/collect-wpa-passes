#!/bin/bash

#	This tool, dev by Seth Leedy - whitehat@sethleedy.name, is to auto update a WPA password list(in the future, hashes and other nifty stuff),
# stored in a sqlite3 database, and exportable to a normal text file.

#	First, it will convert if needed, all the files to Unix text standard using the tr command(was dos2unix, but it complains to much).
#	Then, it will take all of the words, line by line of a input file(or all files within a different directory)
# and see if they need to be inserted as new. If new, it is given a priority of 1.
# 	If it is a duplicate, it is updated to a higher priority by 1, since it more common.
#  As more and more words are found duplicate, higher and higher will be the priorities of them.

#  When the words are to be exported, the default choice will be by the highest priority to lowest within
# the text file. Most common passes(highest priority) are most likely to be used to crack in.

#	All input words will be judged. If it is too short to use or too long, aka the password
# lengths as specified in WPA details, it will be removed(if short) or cut(if long).
# ToDo: add any password as found and then if too short, toss it. Too long cut it and add it as a new pass and mark it as WPA type password and anyother it is compatible with.
# 	Using John the Ripper, mutations are made on all input words. (pass -> pass1,1pass,PASS1,1PASS,ect)
# before inclusion into the database.
#	The database file will be created in the directory of the script. It will not overwrite an existing database file, so it will append to it if it exists on script run.

# MD5 hashes need the newline removed if created with echo
#	md5=$(echo -n "your string here" | md5sum | cut -f1 -d' ')

#------

# Match existing hashes with the Databases
# ??

# Crack hashes using the Databases passwords using the john AND/OR hashcat(hashcat-cli32.bin) tool. Newly compiled version of john is best version for multi threading and rules. Might also speed it up faster with tool parallelization with --fork=N

# Hashcat command file name varies depending on system arch. 32 or 64 or ...
# MD5 cracking hash - hashcat-cli32.bin -m 0 examples/A0.M0.hash examples/A0.M0.word
# See cracked hashes - hashcat --show test.md5
#						5f4dcc3b5aa765d61d8327deb882cf99:password

# Database input is not sanitized yet !!!



#########################
#### Start Variables ####

this_version="0.5"
last_update_date="2014/04/13"
db_file="passes_and_hashes.db"
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
|\tVersion $this_version, $last_update_date\t\t\t\t|\n
========================================================"

help="\n
========================================================\n
|\tCollect WPA Passes guide\t\t\t|\n
|\t\t-h This help\t\t\t\t|\n
|\t\t\t\t\t\t\t|\n
|\tInputs into a SQLite Database\t\t\t|\n
|\t\t-id Input all files contents in a dir\t|\n
|\t\t\t(-id /root/passes)\t\t|\n
|\t!Do not use the same directory as this script!\t|\n
|\t\t-if Input one file contents\t\t|\n
|\t\t-is Input one string into DB\t\t|\n
|\t\t\t\t\t\t\t|\n
|\t\t-of Output .txt file of WPA passes\t|\n
|\t\t-q Mute details and descriptions\t|\n
|\t\t-p Pretend,Print to screen the changes\t|\n
|\t\t-skip-txt-convert Skip the stripping of\t|\n
|Microsoft text formatting\t\t\t\t|\n
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
	wget $skip_wget_digital_check -qb -O /dev/null -U "GRCDownloader_v$this_version" "http://techblog.sethleedy.name/do_count.php?datetime=$datetime&agent_code=CWP_Wget_v.$this_version" 1>/dev/null 2>&1

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

# Play a wav file
# Arg 1 = wave file or if file does not exist, a preset file.
# Arg 2 = how many times. 1 is default if not specified. A * means don't stop. (To stop it later, use function stop_wav() )
function play_wav() {

	# Customize here until setup script is done. Set to use aplay right now.
	# Find the aplay or other program using the loc_file()
	pwc=$(loc_file "aplay")
	#echo "-- $pwc"
	#exit
	play_wav_command_args="-q"

	# Find the wav file
	sound_byte=$(loc_file "$1" ".")

	# If we cannot find the wav file, use a preset by that name.
	if [ "$sound_byte" == "" ]; then
		#Match a preset
		case "$1" in
			default_tone)
				sound_byte=$(loc_file "a_very_nice_single_tone.wav")
				;;

			general_error)
				sound_byte=$(loc_file "criticalstop.wav")
				;;

			*)
				#If no preset matches, exit with error code 1
				return 1
 		esac



	fi

	# Play wav $2 amount of times. If $2 == *, then play in the background until killed by function stop_wav()
	if [ "$2" == "*" ]; then
		stop_count=9000
	elif [ "$2" == "" ]; then
		stop_count=1
	else
		stop_count=$2
	fi
	loop_count=0
	#echo "Play Command: $pwc"
	#echo "Sound: $sound_byte"
	while [ $loop_count -ne $stop_count ]; do
		$pwc $play_wav_command_args $sound_byte
		loop_count=$((loop_count+1))
	done

}

# Find the location of a script and return the path + script
# Returns the first one found.
# Use like; rm_command=$(loc_file "rm")
# Will return the path and command to the variable "rm_command" and allow you to use it via $rm_command "File_to_delete"
# Optional Second Argument ( $2 ) is to be search paths, separated by spaces. Eg; rm_command=$(loc_file "rm" "/bin /sbin /usr/bin /usr/sbin")
function loc_file() {

#echo "locating $1"

	loc_file_return=$(type "$1" 2>&1>/dev/null)
	if [ $? -eq 1 ] || [ "$loc_file_return" == "" ]; then
		# Pass as second arg a space separated list of paths to search within for $1 arg.
		# I was doing just /, but it can be too slow...
		# Recommend as the default, all command paths. ". ~ /bin /sbin /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin /etc/init.d /"
		if [ "$2" == "" ]; then
			# Good default. Same directory as called from and all of the system. But SLOW!
			sec_arg=". /bin /sbin /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin /etc/init.d ~ /"
		else
			sec_arg="$2"
		fi
		for pathing in $sec_arg # note that $sec_arg must NOT be quoted here!
		do
			#echo "Loop path = $pathing"
			loc_file_return=$(find $pathing -ignore_readdir_race -name "$1" 2>/dev/null | grep -m 1 "$1")
			#echo "=1 $loc_file_return within $pathing"

			if [ "$loc_file_return" != "" ]; then
				#echo "Breaking"
				break
			fi
		done
	else
		# The following is what works in terminal, strange in script. In script the return does not have the (). So a different cut is required.
		#loc_file_return=$(type "$1" | cut -d " " -f 4 | cut -d "(" -f 2 | cut -d ")" -f 1)

		# The following works in script, but not terminal...(strange, different results).
		loc_file_return=$(type "$1" | cut -d " " -f 3)

		#echo "=2 $loc_file_return"
	fi
	echo "$loc_file_return"
}

function check_dependents() {

	if [ "$quiet_mode" != true ] && [ "$pretend_mode" != true ]; then
		echo "Checking dependents"
	fi
	hash john 2>/dev/null || { echo >&2 "I require john the ripper but it's not installed.  Aborting."; exit 1; }
	hash pw-inspector 2>/dev/null || { echo >&2 "I require pw-inspector but it's not installed.  Aborting."; exit 1; }
	hash cat 2>/dev/null || { echo >&2 "I require cat but it's not installed.  Aborting."; exit 1; }
	hash sqlite3 2>/dev/null || { echo >&2 "I require sqlite3 but it's not installed.  Aborting."; exit 1; }
	hash awk 2>/dev/null || { echo >&2 "I require awk but it's not installed.  Aborting."; exit 1; }
	hash pwd 2>/dev/null || { echo >&2 "I require pwd but it's not installed.  Aborting."; exit 1; }
	hash readlink 2>/dev/null || { echo >&2 "I require readlink but it's not installed.  Aborting."; exit 1; }
	hash tr 2>/dev/null || { echo >&2 "I require tr but it's not installed.  Aborting."; exit 1; }
	hash md5sum 2>/dev/null || { echo >&2 "I require md5sum but it's not installed.  Aborting."; exit 1; }

	# Set some variables
	if [ "$quiet_mode" != true ] && [ "$pretend_mode" != true ]; then
		echo "Finding rm command"
	fi
	rm_command=$(loc_file "rm" ". /bin /sbin /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin /etc/init.d ~")
	#echo $rm_command
	#exit
	if [ "$quiet_mode" != true ] && [ "$pretend_mode" != true ]; then
		echo "Finding john command"
	fi
	john_command=$(loc_file "john" ". /bin /sbin /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin /etc/init.d ~")
	#echo $john_command
	#exit

	# Check if the DB File exists. If not, create it and fill it with structure.
	if [ "$quiet_mode" != true ] && [ "$pretend_mode" != true ]; then
		echo "Setting up the database"
	fi
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
		STRUCTURE1="CREATE TABLE if not exists passwords (id INTEGER PRIMARY KEY,prioritylvl INTEGER,password TEXT,wpa_password TEXT,md5_hash TEXT);";
		STRUCTURE2="CREATE TABLE if not exists hashofinputfiles (id INTEGER PRIMARY KEY,filename TEXT,md5_hash_of_file TEXT,file_location TEXT,asked_to_upload INTEGER);";

		# Combine all Structures
		Final_Structure="$STRUCTURE1$STRUCTURE2"

			# Additional tables and columns I need to create for the expanded role this script can take
			# Table of HASHES, Fields for every type of hash, md4,md5,sha1,sha2,sha3,sha224,sha256,sha384,sha512,blowfish,eksblowfish,scrypt,crypt(1),etc..

			#hashcat can do the following hashes
				    #0 = MD5
				   #10 = md5($pass.$salt)
				   #20 = md5($salt.$pass)
				   #30 = md5(unicode($pass).$salt)
				   #40 = md5($salt.unicode($pass))
				   #50 = HMAC-MD5 (key = $pass)
				   #60 = HMAC-MD5 (key = $salt)
				  #100 = SHA1
				  #110 = sha1($pass.$salt)
				  #120 = sha1($salt.$pass)
				  #130 = sha1(unicode($pass).$salt)
				  #140 = sha1($salt.unicode($pass))
				  #150 = HMAC-SHA1 (key = $pass)
				  #160 = HMAC-SHA1 (key = $salt)
				  #200 = MySQL
				  #300 = MySQL4.1/MySQL5
				  #400 = phpass, MD5(Wordpress), MD5(phpBB3)
				  #500 = md5crypt, MD5(Unix), FreeBSD MD5, Cisco-IOS MD5
				  #800 = SHA-1(Django)
				  #900 = MD4
				 #1000 = NTLM
				 #1100 = Domain Cached Credentials, mscash
				 #1400 = SHA256
				 #1410 = sha256($pass.$salt)
				 #1420 = sha256($salt.$pass)
				 #1430 = sha256(unicode($pass).$salt)
				 #1440 = sha256($salt.unicode($pass))
				 #1450 = HMAC-SHA256 (key = $pass)
				 #1460 = HMAC-SHA256 (key = $salt)
				 #1600 = md5apr1, MD5(APR), Apache MD5
				 #1700 = SHA512
				 #1710 = sha512($pass.$salt)
				 #1720 = sha512($salt.$pass)
				 #1730 = sha512(unicode($pass).$salt)
				 #1740 = sha512($salt.unicode($pass))
				 #1750 = HMAC-SHA512 (key = $pass)
				 #1760 = HMAC-SHA512 (key = $salt)
				 #1800 = SHA-512(Unix)
				 #2400 = Cisco-PIX MD5
				 #2500 = WPA/WPA2
				 #2600 = Double MD5
				 #3200 = bcrypt, Blowfish(OpenBSD)
				 #3300 = MD5(Sun)
				 #3500 = md5(md5(md5($pass)))
				 #3610 = md5(md5($salt).$pass)
				 #3710 = md5($salt.md5($pass))
				 #3720 = md5($pass.md5($salt))
				 #3810 = md5($salt.$pass.$salt)
				 #3910 = md5(md5($pass).md5($salt))
				 #4010 = md5($salt.md5($salt.$pass))
				 #4110 = md5($salt.md5($pass.$salt))
				 #4210 = md5($username.0.$pass)
				 #4300 = md5(strtoupper(md5($pass)))
				 #4400 = md5(sha1($pass))
				 #4500 = sha1(sha1($pass))
				 #4600 = sha1(sha1(sha1($pass)))
				 #4700 = sha1(md5($pass))
				 #4800 = MD5(Chap)
				 #5000 = SHA-3(Keccak)
				 #5100 = Half MD5
				 #5200 = Password Safe SHA-256
				 #5300 = IKE-PSK MD5
				 #5400 = IKE-PSK SHA1
				 #5500 = NetNTLMv1-VANILLA / NetNTLMv1-ESS
				 #5600 = NetNTLMv2
				 #5700 = Cisco-IOS SHA256
				 #5800 = Samsung Android Password/PIN
				 #6300 = AIX {smd5}
				 #6400 = AIX {ssha256}
				 #6500 = AIX {ssha512}
				 #6700 = AIX {ssha1}
				 #6900 = GOST, GOST R 34.11-94
				 #7000 = Fortigate (FortiOS)
				 #7100 = OS X v10.8
				 #7200 = GRUB 2
				 #7300 = IPMI2 RAKP HMAC-SHA1
				 #7400 = sha256crypt, SHA256(Unix)
				 #9999 = Plaintext

				#* Specific hash types:

				   #11 = Joomla
				   #21 = osCommerce, xt:Commerce
				  #101 = nsldap, SHA-1(Base64), Netscape LDAP SHA
				  #111 = nsldaps, SSHA-1(Base64), Netscape LDAP SSHA
				  #112 = Oracle 11g
				  #121 = SMF > v1.1
				  #122 = OS X v10.4, v10.5, v10.6
				  #123 = EPi
				  #131 = MSSQL(2000)
				  #132 = MSSQL(2005)
				  #141 = EPiServer 6.x < v4
				 #1441 = EPiServer 6.x > v4
				 #1711 = SSHA-512(Base64), LDAP {SSHA512}
				 #1722 = OS X v10.7
				 #1731 = MSSQL(2012)
				 #2611 = vBulletin < v3.8.5
				 #2711 = vBulletin > v3.8.5
				 #2811 = IPB2+, MyBB1.2+
				 #3721 = WebEdition CMS
				 #7600 = Redmine Project Management Web App

		# Creating an Empty db file and filling it with my structure
		cat /dev/null > "$db_file"
		echo $Final_Structure > tmpstructure
		#echo $Final_Structure
		sqlite3 "$db_file" < tmpstructure;
	else
		echo "DB File already exists. I'm not overwriting it!"
	fi
}

# 1rst arg is the password to insert into the DB.
function check_with_db() {

	prioritylvl=1
	pass=""
	password_arg="$1"

	# Do WPA var
	# WPA needs to be larger than 8 in length. MAX 64.
	length=${#password_arg}
	if [ $length -ge 8 ]; then
		# Cut to 64 chars if it is larger.
		wpa_password=$(get_wpa_length "$password_arg")
	else
		wpa_password=""
	fi

	# Ok, getting some errors because the password string contains single quotes and other chars that needs to be escaped.
	# NOTICE!: All passwords inserted into the DataBase are ESCAPED!
	# UNESCAPE to use them, if you are directly reading from the DataBase.
	# The OUTPUT text file this script creates, will be unescaped.
	password_arg=$(escape_str "")

	# Getting my data
	LIST=$(sqlite3 "$db_file" "SELECT prioritylvl,password FROM passwords WHERE password='$password_arg';");
	if [ $? -ne 0 ]; then
		echo "Getting data from DB Error"
		exit
	fi
	#if [ "$quiet_mode" != true ] && [ "$pretend_mode" != true ]; then
	#	echo "-> $LIST"
	#fi

	for ROW in $LIST; do

		# Parsing data (sqlite3 returns a pipe separated string)
		# a[1] needs to match the SELECT order
		#id=$(echo $ROW | awk '{split($0,a,"|"); print a[1]}')
		prioritylvl=$(echo $ROW | awk '{split($0,a,"|"); print a[1]}')
		pass=$(echo $ROW | awk '{split($0,a,"|"); print a[2]}')

		# Printing my data
		echo "Priority: $prioritylvl"
		echo "Pass from DB: $pass"

	done

	# NOT pretending and doing the SQL operations.
	# If no word was found within the DB, do -> insert, else -> update.
	if [ "$pass" == "" ]; then
		if [ "$quiet_mode" != true ] && [ "$pretend_mode" != true ]; then
			echo "INSERTING $password_arg"
		fi
		if [ "$pretend_mode" == true ]; then
			# Just pretending and outputting the changes to console.
			echo "Inserting $password_arg"
		else

			# Compute the varios hashes and things before insertion. Not until now should it be done, otherwise we may compute on just an update...
			# Get md5 hash
			password_md5_hash=$(get_md5_hash "$password_arg")

			if [ "$wpa_password" != "" ]; then
				wpa_password=$(escape_str "$wpa_password")
			fi

			# Do SQL Insertion
			insertion=$(sqlite3 "$db_file" "INSERT INTO passwords (prioritylvl,password,wpa_password,md5_hash) VALUES (1,'$password_arg','$wpa_password','$password_md5_hash');")
			if [ $? -ne 0 ]; then
				echo "Insert into DB Error"
				exit
			fi
			# Verify ?
		fi

	else
		prilvlplus=$((prioritylvl+1))

		if [ "$quiet_mode" != true ] && [ "$pretend_mode" != true ]; then
			echo "UPDATING $password_arg to priority level $prilvlplus."
		fi
		if [ "$pretend_mode" == true ]; then
			# Just pretending and outputting the changes to console.
			echo "Updating $password_arg to priority level $prilvlplus."
		else
			updating=$(sqlite3 "$db_file" "UPDATE passwords SET prioritylvl='$prilvlplus' WHERE password='$password_arg';")
			if [ $? -ne 0 ]; then
				echo "Update DB Error"
				exit
			fi
		fi
	fi

	echo " "
}

function main_working_function() {
#echo "$do_resume"
	#First combine all wordlists into a single temp file.
	if [[ "$do_resume" == false ]] || [[ $do_resume == true && $last_command == "combine_words" ]]; then
		do_resume=false

		if [ "$directory_path" != "" ]; then
			if [ "$quiet_mode" != true ]; then
				echo "Combining all files(*.*) within directory: $directory_path."
			fi
			# Mark our spot for resuming
			echo "combine_words" > $resume_file
#			exit
			#"cat" $directory_path/*.* >> $temp_file

			for combine_file in $directory_path/*.*
				# Hash the file and add it to known inputted files list in the DB
				result=do_file_input_hash "$combine_file"

				# If this has already been hashed, it is already in the DB. No need to continue on this file. SKIP!
				if !result; then
					cat "$combine_file" >> "$temp_file"
				fi

				rm -f "$combine_file"
			done
		fi

		if [ "$input_file" != "" ]; then
			if [ "$quiet_mode" != true ]; then
				echo "Sourcing the input file: $input_file."
			fi
			# Mark our spot for resuming
			echo "combine_words" > $resume_file
#			exit
			cat "$input_file" > "$temp_file"
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
			mv "$temp_file" "$temp_file.do-strip"

			# Remove any BINARY Data.
			# Warning: SET2 is extended to length of SET1 by repeating its last character as necessary.
			# Here's all you have to remove non-printable binary characters (garbage) from a Unix text file:
				# tr -cd '\11\12\15\40-\176' < file-with-binary-chars > clean-file
			#This command uses the -c and -d arguments to the tr command to remove all the characters from the input stream other than the ASCII octal values that are shown between the single quotes. This command specifically allows the following characters to pass through this Unix filter:
				#octal 11: tab
				#octal 12: linefeed
				#octal 15: carriage return
				#octal 40 through octal 176: all the "good" keyboard characters
			#All the other binary characters -- the "garbage" characters in your file -- are stripped out during this translation process.
			if [ "$quiet_mode" != true ]; then
				echo " - Step 1"
			fi
			tr -cd '[:alnum:][:space:][:punct:]' < "$temp_file.do-strip" > "$temp_file.old1"

			$rm_command "$temp_file.do-strip"

			if [ "$quiet_mode" != true ]; then
				echo " - Step 2"
			fi
			# Convert each sequence of repeated newlines to a single newline.
			# Should get rid of blank rows within the text files.
			tr -s '\n' < "$temp_file.old1" > "$temp_file.old"

			$rm_command "$temp_file.old1"

			# Do conversion or you should pass the option to skip it
			# If this command does not do the job, try the tr command. It has an option to remove Microsoft new lines as well
			if [ "$quiet_mode" != true ]; then
				echo " - Step 3"
			fi
			tr -d '\r' < "$temp_file.old" > "$temp_file"

			$rm_command "$temp_file.old"
		fi
	fi

	# Split the file into manageable pieces.
	# Had to do this because john tool was borking on a 2.3 gig file.
	if [[ $do_resume == false || ($do_resume == true && $last_command == "split_words") ]]; then
		do_resume=false
		echo "split_words" > $resume_file
		if [ "$quiet_mode" != true ]; then
			echo "Splitting files"
		fi
		split -d -b 50m "$temp_file" tsplit_
		$rm_command $temp_file
	fi

	#Make mutations of these words with john the ripper
	# This command could make a large difference in the variants. Make it better ?
	# Each time we take in already variant words, it makes it even more varied. This can get ugly. Solution ?
		# To get John working on some Ubuntu upgrades, fix the missing john.ini by linking to john.conf in /etc/john/
		# In home directory, execute: ln -s /etc/john/john.conf ~/john.ini
		# I also needed to create this john.ini in the directory where john itself resides. In mine, /usr/sbin.
		# SO, ln -s /etc/john/john.conf /usr/sbin/john.ini
		# Also, you may have to create the variable $JOHN or $john in your user or global alias within .bash_rc or /etc/bash.bashrc
		# Set variable $JOHN to equal "/usr/share/john/"; JOHN="/usr/share/john/"
	# Install the multi-thread version of John the Ripper to speed things up AND enable cracking of raw md5 hashes..
	#	https://scottlinux.com/2013/01/29/john-the-ripper-multithreaded-multicore-how-to-linux/

	if [[ $do_resume == false || ($do_resume == true && $last_command == "mutate_words") ]]; then
		do_resume=false
		if [ "$quiet_mode" != true ]; then
			echo "Mutating the words to get derivative words."
		fi
		echo "mutate_words" > $resume_file

		for file in tsplit_*
		do
			$john_command -w:$file -rules -session:johnrestore.dat -stdout:64 >> new_$temp_file
			$rm_command -f $file 2> /dev/null &
		done
		$rm_command -f tsplit_* 2> /dev/null &
	fi

	# Send to database, for insertion or updating, with Hashes and any other data we can create and associate with the password.
	if [[ $do_resume || ($do_resume == true && $last_command == "send_to_db") ]]; then
		do_resume=false
		if [ "$quiet_mode" != true ]; then
			echo "Reading the collected passwords and sending them to the database with extra information."
		fi
		echo "send_to_db" > $resume_file

		COUNTER=0
		# This is correct way to read file.
		while read line;do

			#echo "Line # $COUNTER: $line"
			#((COUNTER++))

			# Call function to insert or update the SQLITE
			check_with_db "$line"

		done < "new_$temp_file"

		$rm_command new_$temp_file

	fi
}

# Cuts word to 64 so it fits WPA specs.
function get_wpa_length() {

	cutline="$1"
	echo ${cutline:0:63}
}

# Check and see if the input file has already been inputted.
function do_file_input_hash() {

# Reference
	#STRUCTURE2="CREATE TABLE if not exists hashofinputfiles (id INTEGER PRIMARY KEY,filename TEXT,md5_hash_of_file TEXT,file_location TEXT,asked_to_upload INTEGER);";

	# SELECT from table
	LIST=$(sqlite3 "$db_file" "SELECT filename,asked_to_upload FROM hashofinputfiles WHERE md5_hash_of_file='$password_arg';");
	if [ $? -ne 0 ]; then
		echo "Getting data from DB Error"
		exit
	fi

	# If not found, insert it!
	# Do SQL Insertion
	insertion=$(sqlite3 "$db_file" "INSERT INTO passwords (prioritylvl,password,wpa_password,md5_hash) VALUES (1,'$password_arg','$wpa_password','$password_md5_hash');")
	if [ $? -ne 0 ]; then
		echo "Insert into DB Error"
		exit
	fi
	# Verify ?

	# Exit 0 if empty, ELSE Exit 1 if Inserted

}

#Takes password and computes md5 hash from it and returns the hash
function get_md5_hash() {

	# Do MD5 Hash var
	# add the -n flag to echo unless you want the newline included in the value being md5summed.
	password_md5_hash=$(echo -n "$1" | md5sum)
	# Strip the space and dash appended to the hash.
	password_md5_hash="${password_md5_hash%% *}" # remove the first space and everything after it
	# MD5 should never need escaping

	# Alternative method, but not pure BASH
	#md5=$(echo -n "your string here" | md5sum | cut -f1 -d' ')


	echo "$password_md5_hash"
}

function escape_str() {

	printf -v escaped_var "%q" "$password_arg"

	echo "$escaped_var"

}


# Write SQL output to text file
function write_output() {

	write_out=`sqlite3 "$db_file" "SELECT prioritylvl,password FROM passwords ORDER BY prioritylvl DESC" > "$output_file"`

}

function clean_up() {

	# remove some temp files if present.
	$rm_command -f WPA_lengthed_$temp_file
	$rm_command -f new_$temp_file
	$rm_command -f $temp_file
	$rm_command -f tmpstructure
	$rm_command -f .wpa*

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

	if [ "$1" == "-is" ]; then
		shift
		directory_path=""
		string_input="$1"
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
#if [ "$directory_path" == "" ] && [ "$input_file" == "" ] && [ "$string_input" == "" ]; then
#	echo "Please include a password source. A file, directory of files or a string. See $0 -h."
#	clean_up
#	exit 1
#fi

if [ "$directory_path" == "" ] && [ "$input_file" == "" ] && [ "$input_string" == "" ]; then

	if [ "$quiet_mode" != true ]; then
		echo "No passwords to process."
	fi

else if [ "$input_string" != "" ]; then

	# Ready to work.
	#echo "Play Wav"
	play_wav "default_tone"

	# Call function to insert or update the SQLITE
	check_with_db "$input_string"

else

	# Make sure it is not the same directory this script is running from.
	# I am trying to avoid importing the script and the sqlite database into the script database :).
	if [ "$directory_path" == `pwd` ] || [ `pwd | rev | cut -d "/" -f 1 | rev` == "$directory_path" ] || [ "$directory_path" == "." ]; then
		echo "Change the input source directory to something other than this $0 script location."
		clean_up
		exit 1
	fi

	# Ready to work.
	#echo "Play Wav"
	play_wav "default_tone"
	#echo "Main Function"
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

play_wav "default_tone" 3

# Send Ping
if [ "$quiet_mode" != true ]; then
	echo "Sending ping.."
fi
send_ping

exit 0
