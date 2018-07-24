#!/bin/bash

# The absolute path to the folder whjch contains all the scripts.
# Unless you are working with symlinks, leave the following line untouched.
PATHDATA="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# NO CHANGES BENEATH THIS LINE
# source the configuration file
. $PATHDATA/../settings/rfid_trigger_play.conf

# include the functions
. $PATHDATA/include/functions.sh

# Get args from command line (see Usage above)
for i in "$@"
do
   case $i in
       -c=*|--cardid=*)
                     CARDID="${i#*=}"
                     ;;
   esac
done

#read -p "swipe tag: " CARDID rubbish
#CARDID=$($PATHDATA/read_rfid.py)
#echo $CARDID

# Set the date and time of now
NOW=`date +%Y-%m-%d.%H:%M:%S`
if [ $DEBUG == 1 ]
then
   echo "$NOW" >> $PATHDATA/logs/debug.log
fi

# Get Foldername and add info into the log, making it easer to monitor cards
echo "Card ID '$CARDID' was used at '$NOW'." > $PATHDATA/../shared/latestID.txt
if [ -f $PATHDATA/../shared/shortcuts/$CARDID ]
then
   FOLDERNAME=`cat $PATHDATA/../shared/shortcuts/$CARDID`
   echo "This ID has been used before." >> $PATHDATA/../shared/latestID.txt
else
   echo "$CARDID" > $PATHDATA/../shared/shortcuts/$CARDID
   FOLDERNAME=$CARDID
   echo "This ID was used for the first time." >> $PATHDATA/../shared/latestID.txt
fi
echo "The shortcut points to audiofolder '$FOLDERNAME'." >> $PATHDATA/../shared/latestID.txt

if [ -d "$PATHDATA/../shared/audiofolders/$FOLDERNAME" ] && [ ! -f $PATHDATA/../playlists/$FOLDERNAME.m3u ]
then
   find "$PATHDATA/../shared/audiofolders/$FOLDERNAME" -type f | sort -n > "$PATHDATA/../playlists/$FOLDERNAME.m3u"
fi




# PLAY/PAUSE/STOP/
# player running? 
if pgrep -f RPi-Jukebox-Player > /dev/null
then
   # first kill any possible Player process => stop playing audio
   for pid_RPi in $(pgrep -f RPi-Jukebox-Player);
   do

      run_folder=$(strings -1 /proc/$pid_RPi/cmdline | tail -n 1 |  rev | cut -d" " -f1 | rev)

      if [ $DEBUG == 1 ]
      then
         echo "detected running pid: $pid_RPi" >> $PATHDATA/logs/debug.log
         echo "commandline of the detected process: $run_folder" >> $PATHDATA/logs/debug.log  
      fi

      # Replay Track and exit
      if [ $CARDID == $CMDTRACKREPLAY ]
      then
         $PATHDATA/playout_controls.sh -c=playerreplay 
         exit
      fi

      # if same playlist, only stop the player
      if [ "$PATHDATA/../playlists/$FOLDERNAME.m3u" == "$run_folder" ]
      then
	 if [ $DEBUG == 1 ]
	 then
            echo "Same Playlist" >> $PATHDATA/logs/debug.log
	 fi
	 only_stop=1
      else
	 # if playlist is different, stop the running player and restart with new playlist
	 only_stop=0
      fi

      # terminate the running instance by sendign quit to the correspondig playout controls
      if $PATHDATA/playout_controls.sh -c=playerquit
      then
	 sleep 0.2
         if [ ! -e /proc/$pid_RPi ]
         then
	    if [ $DEBUG == 1 ]
	    then
               echo "Sigterm [success]" >> $PATHDATA/logs/debug.log
	    fi
         else
	    if [ $DEBUG == 1 ]
	    then
               echo "Sigterm [failed]" >> $PATHDATA/logs/debug.log
	    fi
         fi
      else
	 if [ $DEBUG == 1 ]
	 then
            echo "Instance not stoppable" >> $PATHDATA/logs/debug.log
	 fi
      fi
   done
   # Reset Playlists or replay Track and exit!
   if [ $CARDID == $CMDLISTREPLAY ]
   then
      # TODO change FOLDERNAME to running playlist ID to restart from beginning
      if [ $DEBUV == 1 ]
      then
         echo "restartlist $run_folder" >> $PATHDATA/logs/debug.log
      fi
      $PATHDATA/playout_controls.sh -c=restartlist -v=$run_folder
      FOLDERNAME=$run_folder| rev | cut -d"/" -f1 | rev
      $PATHDATA/playout_controls.sh -c=play -v="$run_folder" 
      exit
   fi
   if [ $only_stop != 1 ]
   then
      $PATHDATA/playout_controls.sh -c=play -v="$PATHDATA/../playlists/$FOLDERNAME.m3u" 
   fi
else
   if [ $DEBUG == 1 ]
   then
      echo "No Instance start with $PATHDATA/playout_controls.sh -c=play -v=$PATHDATA/../playlists/$FOLDERNAME.m3u" >> $PATHDATA/logs/debug.log
   fi
#   $PATHDATA/playout_controls.sh -c=init -v="$PATHDATA"
   $PATHDATA/playout_controls.sh -c=play -v="$PATHDATA/../playlists/$FOLDERNAME.m3u" 
fi

case $CARDID in
   $CMDMUTE)
                   $PATHDATA/playout_controls.sh -c=mute
                   ;;
   $CMDVOL30)
                   $PATHDATA/playout_controls.sh -c=setvolume -v=30
                   ;;
   $CMDVOL50)
                   $PATHDATA/playout_controls.sh -c=setvolume -v=50
                   ;;
   $CMDVOL75)
                   $PATHDATA/playout_controls.sh -c=setvolume -v=75
                   ;;
   $CMDVOL85)
                   $PATHDATA/playout_controls.sh -c=setvolume -v=85
                   ;;
   $CMDVOL90)
                   $PATHDATA/playout_controls.sh -c=setvolume -v=90
                   ;;
   $CMDVOL95)
                   $PATHDATA/playout_controls.sh -c=setvolume -v=95
                   ;;
   $CMDVOL100)
                   $PATHDATA/playout_controls.sh -c=setvolume -v=100
                   ;;
   $CMDVOLUP)
                   $PATHDATA/playout_controls.sh -c=volumeup
                   ;;
   $CMDVOLDOWN)
                   $PATHDATA/playout_controls.sh -c=volumedown
                   ;;
   $CMDQUIT) 
                   $PATHDATA/playout_controls.sh -c=playerquit
                   ;;
   $CMDSHUTDOWN)
                   $PATHDATA/playout_controls.sh -c=shutdown
                   ;;
   $CMDREBOOT)
                   $PATHDATA/playout_controls.sh -c=reboot
                   ;;
   $CMDNEXT)
                   $PATHDATA/playout_controls.sh -c=playernext
                   ;;
   $CMDPREV)
                   $PATHDATA/playout_controls.sh -c=playerprev
                   ;;
   $CMDTRACKREPLAY)
                   $PATHDATA/playout_controls.sh -c=playerreplay 
		   ;;
esac
