#!/bin/bash

# arguments: $RELEASE $LINUXFAMILY $BOARD $BUILD_DESKTOP
#
# This is the image customization script

# NOTE: It is copied to /tmp directory inside the image
# and executed there inside chroot environment
# so don't reference any files that are not already installed

# NOTE: If you want to transfer files between chroot and host
# userpatches/overlay directory on host is bind-mounted to /tmp/overlay in chroot

RELEASE=$1
LINUXFAMILY=$2
BOARD=$3
BUILD_DESKTOP=$4

Main() {
	case $RELEASE in
		jessie)
			# your code here
			UserModify
			InstallMachineKit
			CheckCPUFreq
			;;
		xenial)
			# your code here
			UserModify
			InstallMachineKit
			CheckCPUFreq
			;;
		stretch)
			# your code here
			UserModify
			InstallMachineKit
			CheckCPUFreq
			;;
		bionic)
			# your code here
			UserModify
			#InstallMachineKit
			CheckCPUFreq
			;;
	esac
	case $BOARD in
	    orangepipc|orangepione)
			InstallARiscFW_H3
			;;
	esac
} # Main

InstallMachineKit() {
	export LANG=C LC_ALL=C
# LC_ALL="en_US.UTF-8"
	mount --bind /dev/null /proc/mdstat

	case ${RELEASE} in
		jessie)

			apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 43DDF224
			sh -c "echo 'deb http://deb.machinekit.io/debian jessie main' > /etc/apt/sources.list.d/machinekit.list"
			apt-get update
			apt-get --yes --force-yes install machinekit-rt-preempt
			;;
		stretch)

			apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 43DDF224
			sh -c "echo 'deb http://deb.machinekit.io/debian stretch main' > /etc/apt/sources.list.d/machinekit.list"
			apt-get update
			apt-get --yes install machinekit-rt-preempt
			;;

		xenial)
			;;
		bionic)
			;;
	esac
#	# clean up and force password change on first boot
	umount /proc/mdstat
	chage -d 0 root
}

UserModify() {
	# detect desktop
	desktop_nodm=$(dpkg-query -W -f='${db:Status-Abbrev}\n' nodm 2>/dev/null)
	desktop_lightdm=$(dpkg-query -W -f='${db:Status-Abbrev}\n' lightdm 2>/dev/null)

	if [ -n "$desktop_nodm" ]; then DESKTOPDETECT="nodm"; fi
	if [ -n "$desktop_lightdm" ]; then DESKTOPDETECT="lightdm"; fi
### add user `cnc'
	username=cnc
	RealUserName="$(echo "$username" | tr '[:upper:]' '[:lower:]' | tr -d -c '[:alnum:]')"
	[ -z "$RealUserName" ] && return
	echo "Trying to add user $RealUserName"
	useradd -U -m $RealUserName -s '/bin/bash' || return
	for additionalgroup in sudo netdev audio video dialout plugdev bluetooth systemd-journal ssh; do
		usermod -aG ${additionalgroup} ${RealUserName} 2>/dev/null
	done
#	cp -rf /etc/skel/* /home/$RealUserName
	cp -rf /tmp/overlay/democnc/* /home/$RealUserName
	if [ -d /home/$RealUserName/machinekit/configs ] ; then ln -sf /home/$RealUserName/machinekit/configs /home/$RealUserName/Desktop/configs; fi
	chown -R $RealUserName:$RealUserName /home/$RealUserName
	# fix for gksu in Xenial
	touch /home/$RealUserName/.Xauthority
	chown $RealUserName:$RealUserName /home/$RealUserName/.Xauthority
	RealName="$(awk -F":" "/^${RealUserName}:/ {print \$5}" </etc/passwd | cut -d',' -f1)"
	[ -z "$RealName" ] && RealName=$RealUserName
	echo -e "\nDear ${RealName}, your account ${RealUserName} has been created and is sudo enabled."
	echo -e "Please use this account for your daily work from now on.\n"
#	rm -f /root/.not_logged_in_yet
	# set up profile sync daemon on desktop systems
	which psd >/dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo -e "${RealUserName} ALL=(ALL) NOPASSWD: /usr/bin/psd-overlay-helper" >> /etc/sudoers
		touch /home/${RealUserName}/.activate_psd
		chown $RealUserName:$RealUserName /home/${RealUserName}/.activate_psd
	fi
	echo root:${BOARD} | chpasswd
	echo cnc:cnc | chpasswd

	# check for H3/legacy kernel to promote h3disp utility
	if [ -f /boot/script.bin ]; then tmp=$(bin2fex </boot/script.bin 2>/dev/null | grep -w "hdmi_used = 1"); fi
	if [ "$LINUXFAMILY" = "sun8i" ] && [ "$BRANCH" = "default" ] && [ -n "$tmp" ]; then
		setterm -default
		echo -e "\nYour display settings are currently 720p (1280x720). To change this use the"
		echo -e "h3disp utility. Do you want to change display settings now? [nY] \c"
		read -n1 ConfigureDisplay
		if [ "$ConfigureDisplay" != "n" ] && [ "$ConfigureDisplay" != "N" ]; then
			echo -e "\n" ; h3disp
		else
			echo -e "\n"
		fi
	fi
	# check whether desktop environment has to be considered
	if [ "$DESKTOPDETECT" = nodm ] && [ -n "$RealName" ] ; then
		# enable splash
		# [[ -f /etc/systemd/system/desktop-splash.service ]] && systemctl --no-reload enable desktop-splash.service >/dev/null 2>&1 && service desktop-splash restart
		sed -i "s/NODM_USER=\(.*\)/NODM_USER=${RealUserName}/" /etc/default/nodm
		sed -i "s/NODM_ENABLED=\(.*\)/NODM_ENABLED=true/g" /etc/default/nodm
		if [[ -f /var/run/resize2fs-reboot ]]; then
			# Let the user reboot now otherwise start desktop environment
			printf "\n\n\e[0;91mWarning: a reboot is needed to finish resizing the filesystem \x1B[0m \n"
			printf "\e[0;91mPlease reboot the system now \x1B[0m \n\n"
		elif [ -z "$ConfigureDisplay" ] || [ "$ConfigureDisplay" = "n" ] || [ "$ConfigureDisplay" = "N" ]; then
			echo -e "\n\e[1m\e[39mNow starting desktop environment...\x1B[0m\n"
			sleep 3
			service nodm stop
			sleep 1
			service nodm start
		fi
	elif [ "$DESKTOPDETECT" = lightdm ] && [ -n "$RealName" ] ; then
			ln -sf /lib/systemd/system/lightdm.service /etc/systemd/system/display-manager.service
		if [[ -f /var/run/resize2fs-reboot ]]; then
			# Let the user reboot now otherwise start desktop environment
			printf "\n\n\e[0;91mWarning: a reboot is needed to finish resizing the filesystem \x1B[0m \n"
			printf "\e[0;91mPlease reboot the system now \x1B[0m \n\n"
		elif [ -z "$ConfigureDisplay" ] || [ "$ConfigureDisplay" = "n" ] || [ "$ConfigureDisplay" = "N" ]; then
			echo -e "\n\e[1m\e[39mNow starting desktop environment...\x1B[0m\n"
			sleep 1
			service lightdm start 2>/dev/null
			# logout if logged at console
			[[ -n $(who -la | grep root | grep tty1) ]] && exit 1
		fi
	else
		# Display reboot recommendation if necessary
		if [[ -f /var/run/resize2fs-reboot ]]; then
			printf "\n\n\e[0;91mWarning: a reboot is needed to finish resizing the filesystem \x1B[0m \n"
			printf "\e[0;91mPlease reboot the system now \x1B[0m \n\n"
		fi
	fi
# fi
	rm -f /root/.not_logged_in_yet
}

CheckCPUFreq(){
    [[ -f /lib/systemd/system/ondemand.service ]] && systemctl disable ondemand
}

InstallARiscFW_H3(){
	cp -rf /tmp/overlay/h3_arisc_fw/* /boot
}

Main "$@"
