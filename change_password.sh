#!/bin/bash

#set a timestamp that will be used for labeling the log file
timestamp=$(date +%Y-%m-%d-%H:%M:%S)

#set log_file variable; logs will be stored under /var/log/change_password/day-and-time-run.log
log_file="/var/log/change_password/$timestamp.log"

#Ask user to confirm that they have updated the host list (password_change_list)
echo -n "----------   Welcome to the Password Change Script. Have you edited the password_change_list file? (Y or N):"

#Collect user's input
read answer

#handle user's input; proceed with collecting CURRENT password if 'Y', otherwise send message and exit 
if [ "$answer" = "Y" ]
then
	#Prompt user for CURRENT password - will be used to log in at the OS level
	echo "----------   Enter the CURRENT password and press [Enter] NOTE - The password must be the same for all user account on all servers and databases to work correctly"
	echo -n "----------   Current Password:"
	read current_password
fi
if [ "$answer" != "Y" ]
then
        echo "----------   You must edit the password_change_list file first! Exiting!"
        exit 
fi

#Prompt user for NEW password that will be set for several OS user accounts and DB accounts
echo "----------   Enter a NEW password to be applied to all accounts (OS, DB, RMAN) and press [Enter]"
echo -n "----------   New Password:"
read new_password

#Get the number of servers from the text file, based on number of lines
server_count=$(wc -l < password_change_list)

#Communicate to user the number of servers found
echo "----------   Changing passwords on "$server_count" servers..."

#Notice to users not to prematurely kill the process/script, as sometimes it appears to be hung/crashed
echo "----------   Do not kill the process/command until you see the 'Goodbye' message - you will see several ssh connections and password updated successfully messages. Starting in 3 seconds..."

#wait 3 seconds
sleep 3


#create 'i' variable for iteration
i=1
#Execute the code within the while loop for every server name found in host file
while [ $i -le $server_count ]; do
	#set current_server variable to the server name found on each line of the password_change_list file
	current_server=$(sed -n "$i"p password_change_list)

	#communicate to user/log that script is attempting to SSH to the server and change passwords	
	echo "----------   Attempting to connect to server "$current_server" ("$i" of "$server_count" servers) and reset password for all accounts..." 

	#set VAR variable - it will hold the entire expect script command that will SSH to every server and remotely execute password change commands
	VAR=$(expect -c "

	# Set the log file.
	log_file \"$log_file\"

	#start an SSH session as root on the current server
	spawn ssh root@"$current_server"

	#Script has initiated an SSH session; if prompted with the RSA warning, send 'yes' and enter. If prompted for password to login, send password and enter
	expect { 
		\"The authenticity of host\"	{send \"yes\r\"}
		\"password:\"			{send \"$current_password\r\"}
	}
	
	#Script has attempted to authenticate via SSH by passing a password. If prompted for password again, password must be wrong. If prompted with the '#' then script must have successfully connected to server. Change the OS password for user account 'oracle'
	expect {
		\"password:\"	{send_user \"\n----------   SSH failed - most likely due to incorrect password! Exiting!\n\"; exit }
		\"#\"		{send \"passwd oracle\r\"}
	}
	#Script has attempted to change OS password for user account 'oracle'. If prompted for password again, OS has accepted new password and is prompting for confirmation; send password and enter. If OS returns 'Unknown user...' then 'oracle' user account probably doesn't exist
	expect {
		\"password:\"				{send \"$new_password\r\"}
		\"Unknown user name 'oracle'.\"		{send_user \"\n----------   passwd failed - there is no user 'oracle' on host '$current_server'! Exiting!\n\"; exit}
	}	

	#Script has supplied the new password for 'oracle' once, just needs to send again to confirm
	expect \"password:\"
	send \"$new_password\r\"

	#Script will now change password for 'asm' OS user account
	expect \"#\"
	send \"passwd asm\r\"
	
	expect {
		\"password:\"				{send \"$new_password\r\"}
		\"Unknown user name 'oracle'.\"		{send_user \"\n----------   passwd failed - there is no user 'asm' on host '$current_server'! Exiting!\n\"; exit}
	}

	#Script has supplied the new password for 'oracle' once, just needs to send again to confirm
	expect \"password:\"
	send \"$new_password\r\"
	expect \"#\"
	send \"passwd root\r\"

	expect {
		\"password:\"				{send \"$new_password\r\"}
		\"Unknown user name 'root'.\"		{send_user \"\n----------   passwd failed - there is no user 'asm' on host '$current_server'! Exiting!\n\"; exit}
	}

	#Script has supplied the new password for 'oracle' once, just needs to send again to confirm
	expect \"password:\"
	send \"$new_password\r\"
	expect \"#\"

	#Script will now log in to mysql (instead of oracle) and change user passwords there
	#Logging in as root with no password
	send \"mysql -u root -p\r\"
	expect \"password:\"
	send \"$current_password\r\"

	#Expect the mysql prompt
	expect \">\"

	#Set the correct database
	send \"use mysql;\r\"
	expect \">\"

	#Set the new password for DB user 'oracle'
	send \"update user set password=PASSWORD('"$new_password"') where User='oracle';\r\"
	#Set the new password for DB user 'root'
	send \"update user set password=PASSWORD('"$new_password"') where User='root';\r\"

	expect \">\"
	send \"exit\r\"

	#Exit mysql
	expect \"#\"
	#If we haven't exited by now, everything should be OK - send the all clear message
	send_user \"\n----------   No errors while changing passwords on $current_server\n\"
	
	#Exit the SSH session
	send \"exit\r\"
	")

	#Execute the above expect script
	echo "$VAR"
	
	#Notify user/log that all accounts have been updated on current server
	echo "----------   Finished with "$current_server"!"
	
	#Wait one second to allow people to see what's happening
	sleep 1
	
	#Increment i so loop hits the next server in the password_change_list
	(( i++ ))
#finish loop
done

#Prompt user to clear all clear-text passwords in the log file
echo -n "----------   Complete! Do you want to clear clear-text passwords from the log files? (Y or N):"

#Collect user's input
read answer

#If user answers 'Y', replace all clear-text passwords with '********'
if [ "$answer" = "Y" ]
then
        echo "----------   Scrubbing clear-text passwords from log file..."
	sed -i 's/'$new_password'/********/g' $log_file
	echo "----------   All clear-text passwords have been masked!"
	echo "***************   Script has completed"
	echo "***************   Log can be found at $log_file"
	echo "***************   GOODBYE"
	exit
fi
#If user answers with any other string, warn the user of the clear-text passwords
if [ "$answer" != "Y" ]
then
        echo "----------   Log file unmodified. CAUTION - your new password is stored in clear-text the log files!"
	echo "***************   Script has completed"
	echo "***************   Log can be found at $log_file"
	echo "***************   GOODBYE"
        exit 
fi

