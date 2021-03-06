#!/usr/bin/env bash
#
# see https://github.com/MiczFlor/RPi-Jukebox-RFID for details
# Especially the docs folder for documentation

# The absolute path to the folder which contains this script
PATHDATA="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
GIT_BRANCH=${GIT_BRANCH:-master}

LOGDIR=${PATHDATA}/logfiles
DATE=$(date +"%Y%m%d")
DATETIME=$(date +"%Y%m%d_%H%M%S")
 
SCRIPTNAME="$(basename $0)"
JOB="${SCRIPTNAME}"

JUKEBOX_HOME_DIR="/home/pi/RPi-Jukebox-RFID"
JUKEBOX_BACKUP_DIR="/home/pi/BACKUP"

# Setup logger functions
# Input from http://www.ludovicocaldara.net/dba/bash-tips-5-output-logfile/
log_open() {
    [[ -d ${LOGDIR} ]] || mkdir -p ${LOGDIR}
    PIPE=${LOGDIR}/${JOB}_${DATETIME}.pipe
    mkfifo -m 700 ${PIPE}
    LOGFILE=${LOGDIR}/${JOB}_${DATETIME}.log
    exec 3>&1
    tee ${LOGFILE} <${PIPE} >&3 &
    TEEPID=$!
    exec 1>${PIPE} 2>&1
    PIPE_OPENED=1
}
 
log_close() {
    if [ ${PIPE_OPENED} ]; then
        exec 1<&3
        sleep 0.2
        ps --pid ${TEEPID} >/dev/null
        if [ $? -eq 0 ] ; then
            # a wait ${TEEPID} whould be better but some
            # commands leave file descriptors open
            sleep 1
            kill  ${TEEPID}
        fi
        rm ${PIPE}
        unset PIPE_OPENED
    fi
}


welcome() {
    clear
    echo "#####################################################
#    ___  __ ______  _  __________ ____   __  _  _  #
#   / _ \/ // / __ \/ |/ /  _/ __/(  _ \ /  \( \/ ) #
#  / ___/ _  / /_/ /    // // _/   ) _ ((  O ))  (  #
# /_/  /_//_/\____/_/|_/___/____/ (____/ \__/(_/\_) #
#                                                   #
#####################################################

Welcome to the installation script.

This script will install Phoniebox on your Raspberry Pi.
To do so, you must be online. The install script can
automatically configure:

* WiFi settings (SSID, password and static IP)

All these are optional and can also be done later
manually.

If you are ready, hit ENTER"
    read -r INPUT
}

reset_install_config_file() {
    #####################################################
    # CONFIG FILE
    # This file will contain all the data given in the
    # following dialogue
    # At a later stage, the install should also be done
    # from such a config file with no user input.

    # Remove existing config file
    rm PhonieboxInstall.conf
    # Create empty config file
    touch PhonieboxInstall.conf
    echo "# Phoniebox config" > "${PATHDATA}/PhonieboxInstall.conf"
}

config_wifi() {
    #####################################################
    # Ask if wifi config

    clear

    echo "#####################################################
#
# CONFIGURE WIFI
#
# Requires SSID, WiFi password and the static IP you want
# to assign to your Phoniebox.
# (Note: can be done manually later, if you are unsure.)
"
read -rp "Do you want to configure your WiFi? [Y/n] " response
echo ""
case "$response" in
    [nN][oO]|[nN])
        WIFIconfig=NO
        echo "You want to configure WiFi later."
        # append variables to config file
        echo "WIFIconfig=$WIFIconfig" >> "${PATHDATA}/PhonieboxInstall.conf"
        # make a fallback for WiFi Country Code, because we need that even without WiFi config
        echo "WIFIcountryCode=DE" >> "${PATHDATA}/PhonieboxInstall.conf"
        ;;
    *)
        WIFIconfig=YES
        #Ask for SSID
        read -rp "* Type SSID name: " WIFIssid
        #Ask for wifi country code
        read -rp "* WiFi Country Code (e.g. DE, GB, CZ or US): " WIFIcountryCode
        #Ask for password
        read -rp "* Type password: " WIFIpass
        #Ask for IP
        read -rp "* Static IP (e.g. 192.168.1.199): " WIFIip
        #Ask for Router IP
        read -rp "* Router IP (e.g. 192.168.1.1): " WIFIipRouter
        echo ""
        echo "Your WiFi config:"
        echo "SSID              : $WIFIssid"
        echo "WiFi Country Code : $WIFIcountryCode"
        echo "Password          : $WIFIpass"
        echo "Static IP         : $WIFIip"
        echo "Router IP         : $WIFIipRouter"
        read -rp "Are these values correct? [Y/n] " response
        echo ""
        case "$response" in
            [nN][oO]|[nN])
                echo "The values are incorrect."
                read -rp "Hit ENTER to exit and start over." INPUT; exit
                ;;
            *)
                # append variables to config file
                {
                    echo "WIFIconfig=\"$WIFIconfig\"";
                    echo "WIFIcountryCode=\"$WIFIcountryCode\"";
                    echo "WIFIssid=\"$WIFIssid\"";
                    echo "WIFIpass=\"$WIFIpass\"";
                    echo "WIFIip=\"$WIFIip\"";
                    echo "WIFIipRouter=\"$WIFIipRouter\"";
                } >> "${PATHDATA}/PhonieboxInstall.conf"
                ;;
        esac
        ;;
esac
read -rp "Hit ENTER to proceed to the next step." INPUT
}

check_existing() {
    local jukebox_dir="$1"
    local backup_dir="$2"

    #####################################################
    # Check for existing Phoniebox
    #
    # In case there is no existing install,
    # set the var now for later use:
    EXISTINGuse=NO

    # The install will be in the home dir of user pi
    # Move to home directory now to check
    cd ~ || exit
    if [ -d ${jukebox_dir} ]; then
        # Houston, we found something!
        clear
        echo "#####################################################
#
# . . . * alert * alert * alert * alert * . . .
#
# WARNING: an existing Phoniebox installation was found.
#
"
        # check if we find the version number
        if [ -f ${jukebox_dir}/settings/version ]; then
            echo "The version of your installation is: $(cat ${jukebox_dir}/settings/version)"

            # get the current short commit hash of the repo
            CURRENT_REMOTE_COMMIT="$(git ls-remote https://github.com/MiczFlor/RPi-Jukebox-RFID.git ${GIT_BRANCH} | cut -c1-7)"
        fi
        echo "IMPORTANT: you can use the existing content and configuration files for your new install."
        echo "Whatever you chose to keep will be moved to the new install."
        echo "Everything else will remain in a folder called 'BACKUP'.
        "
        # Delete or use existing installation?
        read -rp "Re-use config, audio and RFID codes for the new install? [Y/n] " response
        case "$response" in
            [nN][oO]|[nN])
                EXISTINGuse=NO
                echo "Phoniebox will be a fresh install. The existing version will be dropped."
                sudo rm -rf ${jukebox_dir}
                read -rp "Hit ENTER to proceed to the next step." INPUT
                ;;
            *)
                EXISTINGuse=YES
                # CREATE BACKUP
                # delete existing BACKUP dir if exists
                if [ -d ${backup_dir} ]; then
                    sudo rm -r ${backup_dir}
                fi
                # move install to BACKUP dir
                mv ${jukebox_dir} ${backup_dir}
                # delete .git dir
                if [ -d ${backup_dir}/.git ]; then
                    sudo rm -r ${backup_dir}/.git
                fi
                # delete placeholder files so moving the folder content back later will not create git pull conflicts
                rm ${backup_dir}/shared/audiofolders/placeholder
                rm ${backup_dir}/shared/shortcuts/placeholder

                # ask for things to use
                echo "Ok. You want to use stuff from the existing installation."
                echo "What would you want to keep? Answer now."
                read -rp "RFID config for system control (e.g. 'volume up' etc.)? [Y/n] " response
                case "$response" in
                    [nN][oO]|[nN])
                        EXISTINGuseRfidConf=NO
                        ;;
                    *)
                        EXISTINGuseRfidConf=YES
                        ;;
                esac
                # append variables to config file
                echo "EXISTINGuseRfidConf=$EXISTINGuseRfidConf" >> "${PATHDATA}/PhonieboxInstall.conf"

                read -rp "RFID shortcuts to play audio folders? [Y/n] " response
                case "$response" in
                    [nN][oO]|[nN])
                        EXISTINGuseRfidLinks=NO
                        ;;
                    *)
                        EXISTINGuseRfidLinks=YES
                        ;;
                esac
                # append variables to config file
                echo "EXISTINGuseRfidLinks=$EXISTINGuseRfidLinks" >> "${PATHDATA}/PhonieboxInstall.conf"

                read -rp "Audio folders: use existing? [Y/n] " response
                case "$response" in
                    [nN][oO]|[nN])
                        EXISTINGuseAudio=NO
                        ;;
                    *)
                        EXISTINGuseAudio=YES
                        ;;
                esac
                # append variables to config file
                echo "EXISTINGuseAudio=$EXISTINGuseAudio" >> "${PATHDATA}/PhonieboxInstall.conf"

                read -rp "GPIO: use existing file? [Y/n] " response
                case "$response" in
                    [nN][oO]|[nN])
                        EXISTINGuseGpio=NO
                        ;;
                    *)
                        EXISTINGuseGpio=YES
                        ;;
                esac
                # append variables to config file
                echo "EXISTINGuseGpio=$EXISTINGuseGpio" >> "${PATHDATA}/PhonieboxInstall.conf"

                read -rp "Sound effects: use existing startup / shutdown sounds? [Y/n] " response
                case "$response" in
                    [nN][oO]|[nN])
                        EXISTINGuseSounds=NO
                        ;;
                    *)
                        EXISTINGuseSounds=YES
                        ;;
                esac
                # append variables to config file
                echo "EXISTINGuseSounds=$EXISTINGuseSounds" >> "${PATHDATA}/PhonieboxInstall.conf"

                echo "Thanks. Got it."
                echo "The existing install can be found in the BACKUP directory."
                read -rp "Hit ENTER to proceed to the next step." INPUT
                ;;
        esac
    fi
    # append variables to config file
    echo "EXISTINGuse=$EXISTINGuse" >> "${PATHDATA}/PhonieboxInstall.conf"
}

config_audio_interface() {
    #####################################################
    # Audio iFace

    clear

    echo "#####################################################
#
# CONFIGURE AUDIO INTERFACE (iFace)
#
# By default for the RPi the audio interface would be 'PCM'.
# But this does not work for every setup, alternatives are
# 'Master' or 'Speaker'. Other external sound cards might
# use different interface names.
# To list all available iFace names, type 'amixer scontrols'
# in the terminal.
"
    read -rp "Use PCM as iFace? [Y/n] " response
    case "$response" in
        [nN][oO]|[nN])
            read -rp "Type the iFace name you want to use:" AUDIOiFace
            ;;
        *)
            AUDIOiFace="PCM"
            ;;
    esac
    # append variables to config file
    echo "AUDIOiFace=\"$AUDIOiFace\"" >> "${PATHDATA}/PhonieboxInstall.conf"
    echo "Your iFace is called'$AUDIOiFace'"
    read -rp "Hit ENTER to proceed to the next step." INPUT
}

config_spotify() {
    #####################################################
    # Configure spotify

    clear

    echo "#####################################################
#
# OPTIONAL: INCLUDE SPOTIFY
#
# Note: if this is your first time installing a phoniebox
# it might be best to do a test install without Spotify
# to make sure all your hardware works.
#
# If you want to include Spotify, MUST have your
# credentials ready:
#
# * username
# * password
# * client_id
# * client_secret

"
    read -rp "Do you want to enable Spotify? [Y/n] " response
    case "$response" in
        [nN][oO]|[nN])
            SPOTinstall=NO
            echo "You don't want spotify support."
            ;;
        *)
            SPOTinstall=YES
            clear
            echo "#####################################################
#
# CREDENTIALS for Spotify
#
# Requires Spotify username, password, client_id and client_secret
# to get connection to Spotify.
#
# (Note: You need a device with browser to generate ID and SECRET)
#
# Please go to this website:
# https://www.mopidy.com/authenticate/
# and follow the instructions.
#
# Your credential will appear on the site below the login button.
# Please note your client_id and client_secret!
#
"
            read -rp "Type your Spotify username: " SPOTIuser
            read -rp "Type your Spotify password: " SPOTIpass
            read -rp "Type your client_id: " SPOTIclientid
            read -rp "Type your client_secret: " SPOTIclientsecret
            ;;
    esac
    # append variables to config file
    {
        echo "SPOTinstall=\"$SPOTinstall\"";
        echo "SPOTIuser=\"$SPOTIuser\"";
        echo "SPOTIpass=\"$SPOTIpass\"";
        echo "SPOTIclientid=\"$SPOTIclientid\"";
        echo "SPOTIclientsecret=\"$SPOTIclientsecret\""
    } >> "${PATHDATA}/PhonieboxInstall.conf"
    read -rp "Hit ENTER to proceed to the next step." INPUT
}

config_mpd() {
    #####################################################
    # Configure MPD

    clear

    echo "#####################################################
#
# CONFIGURE MPD
#
# MPD (Music Player Daemon) runs the audio output and must
# be configured. Do it now, if you are unsure.
# (Note: can be done manually later.)
"
    read -rp "Do you want to configure MPD? [Y/n] " response
    case "$response" in
        [nN][oO]|[nN])
            MPDconfig=NO
            echo "You want to configure MPD later."
            ;;
        *)
            MPDconfig=YES
            echo "MPD will be set up with default values."
            ;;
    esac
    # append variables to config file
    echo "MPDconfig=\"$MPDconfig\"" >> "${PATHDATA}/PhonieboxInstall.conf"
    read -rp "Hit ENTER to proceed to the next step." INPUT
}

config_audio_folder() {
    local jukebox_dir="$1"

    #####################################################
    # Folder path for audio files
    # default: /home/pi/RPi-Jukebox-RFID/shared/audiofolders

    clear

    echo "#####################################################
#
# FOLDER CONTAINING AUDIO FILES
#
# The default location for folders containing audio files:
# ${jukebox_dir}/shared/audiofolders
#
# If unsure, keep it like this. If your files are somewhere
# else, you can specify the folder in the next step.
# IMPORTANT: the folder will not be created, only the path
# will be remembered. If you use a custom folder, you must
# create it.
"

    read -rp "Do you want to use the default location? [Y/n] " response
    case "$response" in
        [nN][oO]|[nN])
            echo "Please type the absolute path here (no trailing slash)."
            echo "Default would be for example: ${jukebox_dir}/shared/audiofolders"
            read -r DIRaudioFolders
            ;;
        *)
            DIRaudioFolders="${jukebox_dir}/shared/audiofolders"
            ;;
    esac
    # append variables to config file
    echo "DIRaudioFolders=\"$DIRaudioFolders\"" >> "${PATHDATA}/PhonieboxInstall.conf"
    echo "Your audio folders live in this dir:"
    echo $DIRaudioFolders
    read -rp "Hit ENTER to proceed to the next step." INPUT
}

main_install() {
    local jukebox_dir="$1"
    local apt_get="sudo apt-get -qq --yes"
    local allow_downgrades="--allow-downgrades --allow-remove-essential --allow-change-held-packages"

    clear

    echo "#####################################################
#
# START INSTALLATION
#
# Good news: you completed the input.
# Let the install begin.
#
# Get yourself a cup of something. The install takes
# between 15 minutes to half an hour, depending on
# your Raspberry Pi and Internet connectivity.
#
# You will be prompted later to complete the installation.
"

    read -rp "Do you want to start the installation? [Y/n] " response
    case "$response" in
        [nN][oO]|[nN])
            echo "Exiting the installation."
            echo "Your configuration data was saved in this file:"
            echo "${PATHDATA}/PhonieboxInstall.conf"
            echo
            exit
            ;;
    esac

    # Start logging here
    log_open

    # Add conffile into logfile for better debugging
    echo "################################################"
    grep -v -e "SPOTI" -e "WIFIpass" "${PATHDATA}/PhonieboxInstall.conf"
    echo "################################################"

    #####################################################
    # INSTALLATION

    # Read install config as written so far
    # (this might look stupid so far, but makes sense once
    # the option to install from config file is introduced.)
    # shellcheck source=scripts/installscripts/tests/ShellCheck/PhonieboxInstall.conf
    . "${PATHDATA}/PhonieboxInstall.conf"

    # power management of wifi: switch off to avoid disconnecting
    sudo iwconfig wlan0 power off

    # create backup of /etc/resolv.conf
    sudo cp /etc/resolv.conf /etc/resolv.conf.orig

    # Generate locales
    sudo locale-gen "${LANG}"

    # Install required packages
    ${apt_get} ${allow_downgrades} install apt-transport-https
    wget -q -O - https://apt.mopidy.com/mopidy.gpg | sudo apt-key add -
    sudo wget -q -O /etc/apt/sources.list.d/mopidy.list https://apt.mopidy.com/buster.list

    ${apt_get} update
    ${apt_get} upgrade
    ${apt_get} install libspotify-dev

    # some packages are only available on raspberry pi's but not on test docker containers running on x86_64 machines
    if [[ $(uname -m) =~ ^armv.+$ ]]; then
        ${apt_get} ${allow_downgrades} install raspberrypi-kernel-headers
    fi

    ${apt_get} ${allow_downgrades} install samba samba-common-bin gcc lighttpd php7.3-common php7.3-cgi php7.3 at mpd mpc mpg123 git ffmpeg resolvconf spi-tools

    # restore backup of /etc/resolv.conf in case installation of resolvconf cleared it
    sudo cp /etc/resolv.conf.orig /etc/resolv.conf

    # prepare python3
    ${apt_get} ${allow_downgrades} install python3 python3-dev python3-pip python3-mutagen python3-gpiozero python3-spidev

    # use python3.7 as default
    sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.7 1

    # Get github code
    cd /home/pi/ || exit
    git clone https://github.com/MiczFlor/RPi-Jukebox-RFID.git --branch "${GIT_BRANCH}"

    # add used git branch and commit hash to version file
    USED_BRANCH="$(git --git-dir=${jukebox_dir}/.git rev-parse --abbrev-ref HEAD)"
    sudo sed -i 's/%GIT_BRANCH%/'"$USED_BRANCH"'/' ${jukebox_dir}/settings/version

    # add git commit hash to version file
    COMMIT_NO="$(git --git-dir=${jukebox_dir}/.git describe --always)"
    sudo sed -i 's/%GIT_COMMIT%/'"$COMMIT_NO"'/' ${jukebox_dir}/settings/version

    # Install required spotify packages
    if [ $SPOTinstall == "YES" ]; then
        # keep major verson 3 of mopidy
        echo -e "Package: mopidy\nPin: version 3.*\nPin-Priority: 1001" | sudo tee /etc/apt/preferences.d/mopidy

        wget -q -O - https://apt.mopidy.com/mopidy.gpg | sudo apt-key add -
        sudo wget -q -O /etc/apt/sources.list.d/mopidy.list https://apt.mopidy.com/buster.list
        ${apt_get} update
        ${apt_get} upgrade
        ${apt_get} ${allow_downgrades} install mopidy mopidy-mpd mopidy-local mopidy-spotify
        ${apt_get} ${allow_downgrades} install libspotify12 python3-cffi python3-ply python3-pycparser python3-spotify

        # Install necessary Python packages
        cd ${jukebox_dir}/ || exit
        sudo python3 -m pip install -r requirements-spotify.txt
    fi

    cd ${jukebox_dir}/misc/sampleconfigs/ || exit
    sudo rm phoniebox-rfid-reader.service.stretch-default.sample
    wget https://raw.githubusercontent.com/MiczFlor/RPi-Jukebox-RFID/develop/misc/sampleconfigs/phoniebox-rfid-reader.service.stretch-default.sample
    cd ${jukebox_dir}/scripts/ || exit
    sudo rm RegisterDevice.py
    wget https://raw.githubusercontent.com/MiczFlor/RPi-Jukebox-RFID/develop/scripts/RegisterDevice.py

    # Jump into the Phoniebox dir
    cd ${jukebox_dir} || exit

    # Install more required packages
    sudo python3 -m pip install -r requirements.txt
    sudo pip3 install -r ${jukebox_dir}/components/rfid-reader/PN532/requirements.txt

    # Switch of WiFi power management
    sudo iwconfig wlan0 power off

    # Samba configuration settings
    # -rw-r--r-- 1 root root 9416 Apr 30 09:02 /etc/samba/smb.conf
    sudo cp ${jukebox_dir}/misc/sampleconfigs/smb.conf.buster-default.sample /etc/samba/smb.conf
    sudo chown root:root /etc/samba/smb.conf
    sudo chmod 644 /etc/samba/smb.conf
    # for $DIRaudioFolders using | as alternate regex delimiter because of the folder path slash
    sudo sed -i 's|%DIRaudioFolders%|'"$DIRaudioFolders"'|' /etc/samba/smb.conf
    # Samba: create user 'pi' with password 'raspberry'
    (echo "raspberry"; echo "raspberry") | sudo smbpasswd -s -a pi

    # Web server configuration settings
    # -rw-r--r-- 1 root root 1040 Apr 30 09:19 /etc/lighttpd/lighttpd.conf
    sudo cp /${jukebox_dir}/misc/sampleconfigs/lighttpd.conf.buster-default.sample /etc/lighttpd/lighttpd.conf
    sudo chown root:root /etc/lighttpd/lighttpd.conf
    sudo chmod 644 /etc/lighttpd/lighttpd.conf

    # Web server PHP7 fastcgi conf
    # -rw-r--r-- 1 root root 398 Apr 30 09:35 /etc/lighttpd/conf-available/15-fastcgi-php.conf
    sudo cp ${jukebox_dir}/misc/sampleconfigs/15-fastcgi-php.conf.buster-default.sample /etc/lighttpd/conf-available/15-fastcgi-php.conf
    sudo chown root:root /etc/lighttpd/conf-available/15-fastcgi-php.conf
    sudo chmod 644 /etc/lighttpd/conf-available/15-fastcgi-php.conf
    # settings for php.ini to support upload
    # -rw-r--r-- 1 root root 70999 Jun 14 13:50 /etc/php/7.3/cgi/php.ini
    sudo cp ${jukebox_dir}/misc/sampleconfigs/php.ini.buster-default.sample /etc/php/7.3/cgi/php.ini
    sudo chown root:root /etc/php/7.3/cgi/php.ini
    sudo chmod 644 /etc/php/7.3/cgi/php.ini

    # SUDO users (adding web server here)
    # -r--r----- 1 root root 703 Nov 17 21:08 /etc/sudoers
    sudo cp ${jukebox_dir}/misc/sampleconfigs/sudoers.buster-default.sample /etc/sudoers
    sudo chown root:root /etc/sudoers
    sudo chmod 440 /etc/sudoers

    # copy shell script for player
    cp ${jukebox_dir}/settings/rfid_trigger_play.conf.sample ${jukebox_dir}/settings/rfid_trigger_play.conf

    # creating files containing editable values for configuration
    # DISCONTINUED: now done by MPD? echo "PCM" > /home/pi/RPi-Jukebox-RFID/settings/Audio_iFace_Name
    echo "$AUDIOiFace" > ${jukebox_dir}/settings/Audio_iFace_Name
    echo "$DIRaudioFolders" > ${jukebox_dir}/settings/Audio_Folders_Path
    echo "3" > ${jukebox_dir}/settings/Audio_Volume_Change_Step
    echo "100" > ${jukebox_dir}/settings/Max_Volume_Limit
    echo "0" > ${jukebox_dir}/settings/Idle_Time_Before_Shutdown
    echo "RESTART" > ${jukebox_dir}/settings/Second_Swipe
    echo "${jukebox_dir}/playlists" > ${jukebox_dir}/settings/Playlists_Folders_Path
    echo "ON" > ${jukebox_dir}/settings/ShowCover

    # The new way of making the bash daemon is using the helperscripts
    # creating the shortcuts and script from a CSV file.
    # see scripts/helperscripts/AssignIDs4Shortcuts.php

    # create config file for web app from sample
    sudo cp ${jukebox_dir}/htdocs/config.php.sample ${jukebox_dir}/htdocs/config.php

    # Starting web server and php7
    sudo lighttpd-enable-mod fastcgi
    sudo lighttpd-enable-mod fastcgi-php
    sudo service lighttpd force-reload

    # create copy of GPIO script
    sudo cp ${jukebox_dir}/misc/sampleconfigs/gpio-buttons.py.sample ${jukebox_dir}/scripts/gpio-buttons.py
    sudo chmod +x ${jukebox_dir}/scripts/gpio-buttons.py

    # make sure bash scripts have the right settings
    sudo chown pi:www-data ${jukebox_dir}/scripts/*.sh
    sudo chmod +x ${jukebox_dir}/scripts/*.sh
    sudo chown pi:www-data ${jukebox_dir}/scripts/*.py
    sudo chmod +x ${jukebox_dir}/scripts/*.py

    # services to launch after boot using systemd
    # -rw-r--r-- 1 root root  304 Apr 30 10:07 phoniebox-rfid-reader.service
    # 1. delete old services (this is legacy, might throw errors but is necessary. Valid for versions < 1.1.8-beta)
    echo "### Deleting older versions of service daemons. This might throw errors, ignore them"
    sudo systemctl disable idle-watchdog
    sudo systemctl disable rfid-reader
    sudo systemctl disable startup-sound
    sudo systemctl disable gpio-buttons
    sudo rm /etc/systemd/system/rfid-reader.service
    sudo rm /etc/systemd/system/startup-sound.service
    sudo rm /etc/systemd/system/gpio-buttons.service
    sudo rm /etc/systemd/system/idle-watchdog.service
    echo "### Done with erasing old daemons. Stop ignoring errors!"
    # 2. install new ones - this is version > 1.1.8-beta
    sudo cp ${jukebox_dir}/misc/sampleconfigs/phoniebox-rfid-reader.service.stretch-default.sample /etc/systemd/system/phoniebox-rfid-reader.service
    sudo cp ${jukebox_dir}/misc/sampleconfigs/phoniebox-startup-sound.service.stretch-default.sample /etc/systemd/system/phoniebox-startup-sound.service
    sudo cp ${jukebox_dir}/misc/sampleconfigs/phoniebox-gpio-buttons.service.stretch-default.sample /etc/systemd/system/phoniebox-gpio-buttons.service
    sudo cp ${jukebox_dir}/misc/sampleconfigs/phoniebox-idle-watchdog.service.sample /etc/systemd/system/phoniebox-idle-watchdog.service
    sudo cp ${jukebox_dir}/misc/sampleconfigs/phoniebox-rotary-encoder.service.stretch-default.sample /etc/systemd/system/phoniebox-rotary-encoder.service
    sudo chown root:root /etc/systemd/system/phoniebox-rfid-reader.service
    sudo chown root:root /etc/systemd/system/phoniebox-startup-sound.service
    sudo chown root:root /etc/systemd/system/phoniebox-gpio-buttons.service
    sudo chown root:root /etc/systemd/system/phoniebox-idle-watchdog.service
    sudo chown root:root /etc/systemd/system/phoniebox-rotary-encoder.service
    sudo chmod 644 /etc/systemd/system/phoniebox-rfid-reader.service
    sudo chmod 644 /etc/systemd/system/phoniebox-startup-sound.service
    sudo chmod 644 /etc/systemd/system/phoniebox-gpio-buttons.service
    sudo chmod 644 /etc/systemd/system/phoniebox-idle-watchdog.service
    sudo chmod 644 /etc/systemd/system/phoniebox-rotary-encoder.service
    # enable the services needed
    sudo systemctl enable phoniebox-idle-watchdog
    sudo systemctl enable phoniebox-rfid-reader
    sudo systemctl enable phoniebox-startup-sound
    sudo systemctl enable phoniebox-gpio-buttons
    sudo systemctl enable phoniebox-rotary-encoder.service

    # copy mp3s for startup and shutdown sound to the right folder
    cp ${jukebox_dir}/misc/sampleconfigs/startupsound.mp3.sample ${jukebox_dir}/shared/startupsound.mp3
    cp ${jukebox_dir}/misc/sampleconfigs/shutdownsound.mp3.sample ${jukebox_dir}/shared/shutdownsound.mp3

    # Spotify config
    if [ $SPOTinstall == "YES" ]; then
        sudo systemctl disable mpd
        sudo systemctl enable mopidy
        # Install Config Files
        sudo cp ${jukebox_dir}/misc/sampleconfigs/locale.gen.sample /etc/locale.gen
        sudo cp ${jukebox_dir}/misc/sampleconfigs/locale.sample /etc/default/locale
        sudo locale-gen
        sudo mkdir /home/pi/.config
        sudo mkdir /home/pi/.config/mopidy
        sudo cp ${jukebox_dir}/misc/sampleconfigs/mopidy-etc.sample /etc/mopidy/mopidy.conf
        sudo cp ${jukebox_dir}/misc/sampleconfigs/mopidy.sample ~/.config/mopidy/mopidy.conf
        # Change vars to match install config
        sudo sed -i 's/%spotify_username%/'"$SPOTIuser"'/' /etc/mopidy/mopidy.conf
        sudo sed -i 's/%spotify_password%/'"$SPOTIpass"'/' /etc/mopidy/mopidy.conf
        sudo sed -i 's/%spotify_client_id%/'"$SPOTIclientid"'/' /etc/mopidy/mopidy.conf
        sudo sed -i 's/%spotify_client_secret%/'"$SPOTIclientsecret"'/' /etc/mopidy/mopidy.conf
        sudo sed -i 's/%spotify_username%/'"$SPOTIuser"'/' ~/.config/mopidy/mopidy.conf
        sudo sed -i 's/%spotify_password%/'"$SPOTIpass"'/' ~/.config/mopidy/mopidy.conf
        sudo sed -i 's/%spotify_client_id%/'"$SPOTIclientid"'/' ~/.config/mopidy/mopidy.conf
        sudo sed -i 's/%spotify_client_secret%/'"$SPOTIclientsecret"'/' ~/.config/mopidy/mopidy.conf
    fi

    if [ $MPDconfig == "YES" ]; then
        # MPD configuration
        # -rw-r----- 1 mpd audio 14043 Jul 17 20:16 /etc/mpd.conf
        sudo cp ${jukebox_dir}/misc/sampleconfigs/mpd.conf.buster-default.sample /etc/mpd.conf
        # Change vars to match install config
        sudo sed -i 's/%AUDIOiFace%/'"$AUDIOiFace"'/' /etc/mpd.conf
        # for $DIRaudioFolders using | as alternate regex delimiter because of the folder path slash
        sudo sed -i 's|%DIRaudioFolders%|'"$DIRaudioFolders"'|' /etc/mpd.conf
        sudo chown mpd:audio /etc/mpd.conf
        sudo chmod 640 /etc/mpd.conf
    fi

    # set which version has been installed
    if [ $SPOTinstall == "YES" ]; then
        echo "plusSpotify" > ${jukebox_dir}/settings/edition
    else
        echo "classic" > ${jukebox_dir}/settings/edition
    fi

    # update mpc / mpd DB
    mpc update

    # / INSTALLATION
    #####################################################
}

wifi_settings() {
    local sample_configs_dir="$1"
    local dhcpcd_conf="$2"
    local wpa_supplicant_conf="$3"

    ###############################
    # WiFi settings (SSID password)
    #
    # https://www.raspberrypi.org/documentation/configuration/wireless/wireless-cli.md
    #
    # $WIFIssid
    # $WIFIpass
    # $WIFIip
    # $WIFIipRouter
    if [ $WIFIconfig == "YES" ]; then
        # DHCP configuration settings
        echo "Setting ${dhcpcd_conf}..."
        #-rw-rw-r-- 1 root netdev 0 Apr 17 11:25 /etc/dhcpcd.conf
        sudo cp ${sample_configs_dir}/dhcpcd.conf.buster-default-noHotspot.sample ${dhcpcd_conf}
        # Change IP for router and Phoniebox
        sudo sed -i 's/%WIFIip%/'"$WIFIip"'/' ${dhcpcd_conf}
        sudo sed -i 's/%WIFIipRouter%/'"$WIFIipRouter"'/' ${dhcpcd_conf}
        sudo sed -i 's/%WIFIcountryCode%/'"$WIFIcountryCode"'/' ${dhcpcd_conf}
        # Change user:group and access mod
        sudo chown root:netdev ${dhcpcd_conf}
        sudo chmod 664 ${dhcpcd_conf}

        # WiFi SSID & Password
        echo "Setting ${wpa_supplicant_conf}..."
        # -rw-rw-r-- 1 root netdev 137 Jul 16 08:53 /etc/wpa_supplicant/wpa_supplicant.conf
        sudo cp ${sample_configs_dir}/wpa_supplicant.conf.buster-default.sample ${wpa_supplicant_conf}
        sudo sed -i 's/%WIFIssid%/'"$WIFIssid"'/' ${wpa_supplicant_conf}
        sudo sed -i 's/%WIFIpass%/'"$WIFIpass"'/' ${wpa_supplicant_conf}
        sudo sed -i 's/%WIFIcountryCode%/'"$WIFIcountryCode"'/' ${wpa_supplicant_conf}
        sudo chown root:netdev ${wpa_supplicant_conf}
        sudo chmod 664 ${wpa_supplicant_conf}
    fi

    # start DHCP
    echo "Starting dhcpcd service..."
    sudo service dhcpcd start
    sudo systemctl enable dhcpcd

# / WiFi settings (SSID password)
###############################
}

existing_assets() {
    local jukebox_dir="$1"
    local backup_dir="$2"

    #####################################################
    # EXISTING ASSETS TO USE FROM EXISTING INSTALL

    if [ $EXISTINGuse == "YES" ]; then
        # RFID config for system control
        if [ $EXISTINGuseRfidConf == "YES" ]; then
            # read old values and write them into new file (copied above already)
            # do not overwrite but use 'sed' in case there are new vars in new version installed

            # Read the existing RFID config file line by line and use
            # only lines which are separated (IFS) by '='.
            while IFS='=' read -r key val ; do
                # $var should be stripped of possible leading or trailing "
                val=${val%\"}
                val=${val#\"}
                key=${key}
                # Additional error check: key should not start with a hash and not be empty.
                if [ ! "${key:0:1}" == '#' ] && [ -n "$key" ]; then
                    # Replace the matching value in the newly created conf file
                    sed -i 's/%'"$key"'%/'"$val"'/' ${jukebox_dir}/settings/rfid_trigger_play.conf
                fi
            done <${backup_dir}/settings/rfid_trigger_play.conf
        fi

        # RFID shortcuts for audio folders
        if [ $EXISTINGuseRfidLinks == "YES" ]; then
            # copy from backup to new install
            cp -R ${backup_dir}/shared/shortcuts/* ${jukebox_dir}/shared/shortcuts/
        fi

        # Audio folders: use existing
        if [ $EXISTINGuseAudio == "YES" ]; then
            # copy from backup to new install
            cp -R ${backup_dir}/shared/audiofolders/* "$DIRaudioFolders/"
        fi

        # GPIO: use existing file
        if [ $EXISTINGuseGpio == "YES" ]; then
            # copy from backup to new install
            cp ${backup_dir}/scripts/gpio-buttons.py ${jukebox_dir}/scripts/gpio-buttons.py
        fi

        # Sound effects: use existing startup / shutdown sounds
        if [ $EXISTINGuseSounds == "YES" ]; then
            # copy from backup to new install
            cp ${backup_dir}/shared/startupsound.mp3 ${jukebox_dir}/shared/startupsound.mp3
            cp ${backup_dir}/shared/shutdownsound.mp3 ${jukebox_dir}/shared/shutdownsound.mp3
        fi

    fi

    # / EXISTING ASSETS TO USE FROM EXISTING INSTALL
    ################################################
}


folder_access() {
    local jukebox_dir="$1"
    local user_group="$2"
    local mod="$3"

    #####################################################
    # Folders and Access Settings

    echo "Setting owner and permissions for directories..."

    # create playlists folder
    mkdir -p ${jukebox_dir}/playlists
    sudo chown -R ${user_group} ${jukebox_dir}/playlists
    sudo chmod -R ${mod} ${jukebox_dir}/playlists

    # make sure the shared folder is accessible by the web server
    sudo chown -R ${user_group} ${jukebox_dir}/shared
    sudo chmod -R ${mod} ${jukebox_dir}/shared

    # make sure the htdocs folder can be changed by the web server
    sudo chown -R ${user_group} ${jukebox_dir}/htdocs
    sudo chmod -R ${mod} ${jukebox_dir}/htdocs

    sudo chown -R ${user_group} ${jukebox_dir}/settings
    sudo chmod -R ${mod} ${jukebox_dir}/settings

    # audio folders might be somewhere else, so treat them separately
    sudo chown ${user_group} "${DIRaudioFolders}"
    sudo chmod ${mod} "${DIRaudioFolders}"

    # make sure bash scripts have the right settings
    sudo chown ${user_group} ${jukebox_dir}/scripts/*.sh
    sudo chmod +x ${jukebox_dir}/scripts/*.sh
    sudo chown ${user_group} ${jukebox_dir}/scripts/*.py
    sudo chmod +x ${jukebox_dir}/scripts/*.py

    # set audio volume to 100%
    # see: https://github.com/MiczFlor/RPi-Jukebox-RFID/issues/54
    sudo amixer cset numid=1 100%

    # delete the global.conf file, in case somebody manually copied stuff back and forth
    # this will be created the first time the Phoniebox is put to use by web app or RFID
    GLOBAL_CONF=${jukebox_dir}/settings/global.conf
    if [ -f $GLOBAL_CONF ]; then
        echo "global.conf needs to be deleted."
        rm $GLOBAL_CONF
    fi

    # / Access settings
    #####################################################
}

finish_installation() {
    local jukebox_dir="$1"
    echo "
#
# INSTALLATION FINISHED
#
#####################################################
"

    #####################################################
    # Register external device(s)

    echo "If you are using an USB RFID reader, connect it to your RPi."
    echo "(In case your RFID reader required soldering, consult the manual.)"
    # Use -e to display response of user in the logfile
    read -e -r -p "Have you connected your USB Reader? [Y/n] " response
    case "$response" in
        [nN][oO]|[nN])
            ;;
        *)
            cd ${jukebox_dir}/scripts/ || exit
            python3 RegisterDevice.py
            sudo chown pi:www-data ${jukebox_dir}/scripts/deviceName.txt
            sudo chmod 644 ${jukebox_dir}/scripts/deviceName.txt
            ;;
    esac

    echo
    echo "DONE. Let the sounds begin."
    echo "Find more information and documentation on the github account:"
    echo "https://github.com/MiczFlor/RPi-Jukebox-RFID/wiki/"

    echo "Reboot is needed to activate all settings"
    # Use -e to display response of user in the logfile
    read -e -r -p "Would you like to reboot now? [Y/n] " response
    case "$response" in
        [nN][oO]|[nN])
        # Close logging
        log_close
            ;;
        *)
        # Close logging
        log_close
            sudo shutdown -r now
            ;;
    esac
}

########
# Main #
########
main() {
    welcome
    reset_install_config_file
    config_wifi
    check_existing "${JUKEBOX_HOME_DIR}" "${JUKEBOX_BACKUP_DIR}"
    config_audio_interface
    config_spotify
    config_mpd
    config_audio_folder "${JUKEBOX_HOME_DIR}"
    main_install "${JUKEBOX_HOME_DIR}"
    wifi_settings "${JUKEBOX_HOME_DIR}/misc/sampleconfigs" "/etc/dhcpcd.conf" "/etc/wpa_supplicant/wpa_supplicant.conf"
    existing_assets "${JUKEBOX_HOME_DIR}" "${JUKEBOX_BACKUP_DIR}"
    folder_access "${JUKEBOX_HOME_DIR}" "pi:www-data" 775
    finish_installation "${JUKEBOX_HOME_DIR}"
}

start=`date +%s`

main

end=`date +%s`
runtime=$((end-start))
((m=(${runtime}%3600)/60))
((s=${runtime}%60))
echo "Done (in ${m}m ${s}s)."

#####################################################
# notes for things to do

# Soundcard
# PCM is currently set
# This needs to be done for mpd and in settings folder

#Ask ssh password

# get existing install
# new config should be done with sed using existing conf and user input

# CLEANUP
## remove dir BACKUP (possibly not, because we do this at the beginning after user confirms for latest config)
