# !/bin/bash
#
# Architect Installation Framework (2016-2017)
#
# Written by Carl Duff and @mandog for Archlinux
# Heavily modified and re-written by @Chrysostomus to install Manjaro instead
# Contributors: @papajoker, @oberon and the Manjaro-Community.
#
# This program is free software, provided under the GNU General Public License
# as published by the Free Software Foundation. So feel free to copy, distribute,
# or modify it as you wish.

advanced_menu() {
    declare -i loopmenu=1
    while ((loopmenu)); do
        submenu 7
        DIALOG " $_InstAdvBase " --default-item ${HIGHLIGHT_SUB} \
          --menu "\n " 0 0 7 \
          "1" "$_InstDEGit" \
          "2" "$_InstDE|>" \
          "3" "$_InstDrvTitle|>" \
          "4" "$_SecMenuTitle|>" \
          "5" "Chroot into installation" \
          "6" "$_InstMulCust" \
          "7" "$_Back" 2>${ANSWER} || return 0
        HIGHLIGHT_SUB=$(cat ${ANSWER})

        case $(cat ${ANSWER}) in
            "1") check_base && install_manjaro_de_wm_git
                ;;
            "2") check_base && install_vanilla_de_wm
                ;;
            "3") check_base && install_drivers_menu
                ;;
            "4") check_base && security_menu
                ;;
            "5") check_base && chroot_interactive
                ;;
            "6") install_cust_pkgs
                ;;
            *) loopmenu=0
                return 0
                ;;
        esac
    done
}

install_cust_pkgs() {
    echo "" > ${PACKAGES}
    pacman -Ssq | fzf -m -e --header="$_AddPkgs" --prompt="$_AddPkgsPrmpt > " --reverse >${PACKAGES} || return 0

    clear
    # If at least one package, install.
    if [[ $(cat ${PACKAGES}) != "" ]]; then
            if $hostcache; then
              basestrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>$ERR
            else
              basestrap -c ${MOUNTPOINT} $(cat ${PACKAGES}) 2>$ERR
            fi
            check_for_error "$FUNCNAME $(cat ${PACKAGES})" "$?"
    fi
}

rm_pgs(){
  manjaro-chroot /mnt "pacman -Qq" | fzf -m -e --header="$_RmPkgsMsg" --prompt="$_RmPkgsPrmpt > " --reverse > /tmp/.to_be_removed || return 0

    if [[ $(cat /tmp/.to_be_removed) != "" ]]; then
            arch_chroot "pacman -Rsn $(cat /tmp/.to_be_removed)" 2>$ERR
            check_for_error "$FUNCNAME $(cat /tmp/.to_be_removed)" "$?"
    fi
}

chroot_interactive() {

DIALOG " $_EnterChroot " --infobox "$_ChrootReturn" 0 0 
echo ""
echo ""
arch_chroot bash
}

install_manjaro_de_wm_git() {
    if check_desktop; then
        PROFILES="$DATADIR/profiles"
        # Only show this information box once
        if [[ $SHOW_ONCE -eq 0 ]]; then
            DIALOG " $_InstDETitle " --msgbox "\n$_InstPBody\n " 0 0
            SHOW_ONCE=1
        fi
        clear
        # install git if not already installed
        inst_needed git
        # download manjaro-tools.-isoprofiles git repo
        if [[ -e $PROFILES ]]; then
            git -C $PROFILES pull 2>$ERR
            check_for_error "pull profiles repo" $?
        else
            git clone -b manjaro-architect --depth 1 https://gitlab.manjaro.org/profiles-and-settings/iso-profiles.git $PROFILES 2>$ERR
            check_for_error "clone profiles repo" $?
        fi

        install_manjaro_de_wm
    fi
}

install_vanilla_de_wm() {
    local PARENT="$FUNCNAME"
    declare -i loopmenu=1
    while ((loopmenu)); do
        ssubmenu 7
        DIALOG " $_InstGrMenuTitle " --default-item ${HIGHLIGHT_SSUB} \
          --menu "\n$_InstGrMenuBody\n " 0 0 6 \
          "1" "$_InstGrMenuDS" \
          "2" "$_InstGrDE" \
          "3" "$_InstGrMenuDM" \
          "4" "$_InstNMMenuTitle|>" \
          "5" "$_InstMultMenuTitle|>" \
          "6" "$_Back" 2>${ANSWER}
        HIGHLIGHT_SSUB=$(cat ${ANSWER})

        case $(cat ${ANSWER}) in
            "1") install_xorg_input
                 ;;
            "2") install_de_wm
                 ;;
            "3") install_dm
                 ;;
            "4") install_network_menu
                 ;;
            "5") install_multimedia_menu
                 ;;
            *) loopmenu=0
                return 0
                 ;;
        esac 
    done
}

# Install xorg and input drivers. Also copy the xkbmap configuration file created earlier to the installed system
install_xorg_input() {
    echo "" > ${PACKAGES}

    DIALOG " $_InstGrMenuDS " --checklist "\n$_InstGrMenuDSBody\n\n$_UseSpaceBar\n " 0 0 11 \
      "wayland" "-" off \
      "xorg-server" "-" on \
      "xorg-server-common" "-" off \
      "xorg-xinit" "-" on \
      "xorg-server-xwayland" "-" off \
      "xf86-input-evdev" "-" off \
      "xf86-input-libinput" "-" on \
      "xf86-input-synaptics" "-" off 2>${PACKAGES}

    clear
    # If at least one package, install.
    if [[ $(cat ${PACKAGES}) != "" ]]; then
        basestrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>$ERR
        check_for_error "$FUNCNAME" $?
    fi

    # now copy across .xinitrc for all user accounts
    user_list=$(ls ${MOUNTPOINT}/home/ | sed "s/lost+found//")
    for i in ${user_list}; do
        [[ -e ${MOUNTPOINT}/home/$i/.xinitrc ]] || cp -f ${MOUNTPOINT}/etc/X11/xinit/xinitrc ${MOUNTPOINT}/home/$i/.xinitrc
        arch_chroot "chown -R ${i}:${i} /home/${i}"
    done

    HIGHLIGHT_SUB=1
}

install_de_wm() {
    # Only show this information box once
    if [[ $SHOW_ONCE -eq 0 ]]; then
        DIALOG " $_InstDETitle " --msgbox "\n$_DEInfoBody\n " 0 0
        SHOW_ONCE=1
    fi

    # DE/WM Menu
    DIALOG " $_InstDETitle " --checklist "\n$_InstDEBody\n\n$_UseSpaceBar\n " 0 0 13 \
      "awesome + vicious" "-" off \
      "budgie-desktop" "-" off \
      "cinnamon" "-" off \
      "deepin" "-" off \
      "deepin-extra" "-" off \
      "enlightenment + terminology" "-" off \
      "fluxbox + fbnews" "-" off \
      "gnome" "-" off \
      "gnome-extra" "-" off \
      "gnome-shell" "-" off \
      "i3-wm + i3lock + i3status" "-" off \
      "icewm + icewm-themes" "-" off \
      "jwm" "-" off \
      "kde-applications" "-" off \
      "lxde" "-" off \
      "lxqt + oxygen-icons" "-" off \
      "mate" "-" off \
      "mate-extra" "-" off \
      "mate-extra-gtk3" "-" off \
      "mate-gtk3" "-" off \
      "openbox + openbox-themes" "-" off \
      "pekwm + pekwm-themes" "-" off \
      "plasma" "-" off \
      "plasma-desktop" "-" off \
      "windowmaker" "-" off \
      "xfce4" "-" off \
      "xfce4-goodies" "-" off 2>${PACKAGES}

    # If something has been selected, install
    if [[ $(cat ${PACKAGES}) != "" ]]; then
        clear
        sed -i 's/+\|\"//g' ${PACKAGES}
        if $hostcache; then
          basestrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>$ERR
        else
          basestrap -c ${MOUNTPOINT} $(cat ${PACKAGES}) 2>$ERR
        fi
        check_for_error "${FUNCNAME}: ${PACKAGES}" "$?"

        # Clear the packages file for installation of "common" packages
        echo "" > ${PACKAGES}

        # Offer to install various "common" packages.
        DIALOG " $_InstComTitle " --checklist "\n$_InstComBody\n\n$_UseSpaceBar\n " 0 50 14 \
          "bash-completion" "-" on \
          "gamin" "-" on \
          "gksu" "-" on \
          "gnome-icon-theme" "-" on \
          "gnome-keyring" "-" on \
          "gvfs" "-" on \
          "gvfs-afc" "-" on \
          "gvfs-smb" "-" on \
          "polkit" "-" on \
          "poppler" "-" on \
          "python2-xdg" "-" on \
          "ntfs-3g" "-" on \
          "ttf-dejavu" "-" on \
          "xdg-user-dirs" "-" on \
          "xdg-utils" "-" on \
          "xterm" "-" on 2>${PACKAGES}

        # If at least one package, install.
        if [[ $(cat ${PACKAGES}) != "" ]]; then
            clear
            
            if $hostcache; then
              basestrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>$ERR
            else
              basestrap -c ${MOUNTPOINT} $(cat ${PACKAGES}) 2>$ERR
            fi
            check_for_error "basestrap ${MOUNTPOINT} $(cat ${PACKAGES})" "$?"
        fi
    fi
}

# Display Manager
install_dm() {
    if [[ $DM_ENABLED -eq 0 ]]; then
        # Prep variables
        echo "" > ${PACKAGES}
        dm_list="gdm lxdm lightdm sddm"
        DM_LIST=""
        DM_INST=""

        # Generate list of DMs installed with DEs, and a list for selection menu
        for i in ${dm_list}; do
            [[ -e ${MOUNTPOINT}/usr/bin/${i} ]] && DM_INST="${DM_INST} ${i}" && check_for_error "${i} already installed."
            DM_LIST="${DM_LIST} ${i} -"
        done

        DIALOG " $_DmChTitle " --menu "\n$_AlreadyInst$DM_INST\n\n$_DmChBody\n " 0 0 4 \
          ${DM_LIST} 2>${PACKAGES}
        clear
        # If a selection has been made, act
        if [[ $(cat ${PACKAGES}) != "" ]]; then
            # check if selected dm already installed. If so, enable and break loop.
            for i in ${DM_INST}; do
                if [[ $(cat ${PACKAGES}) == ${i} ]]; then
                    enable_dm
                    break;
                fi
            done

            # If no match found, install and enable DM
            if [[ $DM_ENABLED -eq 0 ]]; then
                # Where lightdm selected, add gtk greeter package
                sed -i 's/lightdm/lightdm lightdm-gtk-greeter/' ${PACKAGES}
                if [[ -e /mnt/.openrc ]]; then
                    echo "$(cat ${PACKAGES}) displaymanager-openrc" >${PACKAGES}
                fi
                basestrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>$ERR
                check_for_error "install ${PACKAGES}" $?

                # Where lightdm selected, now remove the greeter package
                sed -i 's/lightdm-gtk-greeter//' ${PACKAGES}
                enable_dm
            fi
        fi
    fi

    # Show after successfully installing or where attempting to repeat when already completed.
    [[ $DM_ENABLED -eq 1 ]] && DIALOG " $_DmChTitle " --msgbox "\n$_DmDoneBody\n " 0 0
}

enable_dm() {
    if [[ -e /mnt/.openrc ]]; then
        sed -i "s/$(grep "DISPLAYMANAGER=" /mnt/etc/conf.d/xdm)/DISPLAYMANAGER=\"$(cat ${PACKAGES})\"/g" /mnt/etc/conf.d/xdm
        arch_chroot "rc-update add xdm default" 2>$ERR
        check_for_error "add default xdm" "$?"
        DM=$(cat ${PACKAGES})
        DM_ENABLED=1
    else 
        # enable display manager for systemd
        arch_chroot "systemctl enable $(cat ${PACKAGES})" 2>$ERR
        check_for_error "enable $(cat ${PACKAGES})" "$?"
        DM=$(cat ${PACKAGES})
        DM_ENABLED=1
    fi
}

install_network_menu() {
    declare -i loopmenu=1
    while ((loopmenu)); do
        local PARENT="$FUNCNAME"
        
        submenu 5
        DIALOG " $_InstNMMenuTitle " --default-item ${HIGHLIGHT_SUB} --menu "\n$_InstNMMenuBody\n " 0 0 5 \
          "1" "$_SeeWirelessDev" \
          "2" "$_InstNMMenuPkg" \
          "3" "$_InstNMMenuNM" \
          "4" "$_InstNMMenuCups" \
          "5" "$_Back" 2>${ANSWER}

        case $(cat ${ANSWER}) in
            "1") # Identify the Wireless Device
                lspci -k | grep -i -A 2 "network controller" > /tmp/.wireless
                if [[ $(cat /tmp/.wireless) != "" ]]; then
                    DIALOG " $_WirelessShowTitle " --textbox /tmp/.wireless 0 0
                else
                    DIALOG " $_WirelessShowTitle " --msgbox "\n$_WirelessErrBody\n " 7 30
                fi
                ;;
            "2") install_wireless_packages
                ;;
            "3") install_nm
                ;;
            "4") install_cups
                ;;
            *) loopmenu=0
                return 0
                ;;
        esac
    done
}

# ntp not exactly wireless, but this menu is the best fit.
install_wireless_packages() {
    WIRELESS_PACKAGES=""
    wireless_pkgs="dialog iw rp-pppoe wireless_tools wpa_actiond"

    for i in ${wireless_pkgs}; do
        WIRELESS_PACKAGES="${WIRELESS_PACKAGES} ${i} - on"
    done

    # If no wireless, uncheck wireless pkgs
    [[ $(lspci | grep -i "Network Controller") == "" ]] && WIRELESS_PACKAGES=$(echo $WIRELESS_PACKAGES | sed "s/ on/ off/g")

    DIALOG " $_InstNMMenuPkg " --checklist "\n$_InstNMMenuPkgBody\n\n$_UseSpaceBar\n " 0 0 13 \
      $WIRELESS_PACKAGES \
      "ufw" "-" off \
      "gufw" "-" off \
      "ntp" "-" off \
      "b43-fwcutter" "Broadcom 802.11b/g/n" off \
      "bluez-firmware" "Broadcom BCM203x / STLC2300 Bluetooth" off \
      "ipw2100-fw" "Intel PRO/Wireless 2100" off \
      "ipw2200-fw" "Intel PRO/Wireless 2200" off \
      "zd1211-firmware" "ZyDAS ZD1211(b) 802.11a/b/g USB WLAN" off 2>${PACKAGES}

    if [[ $(cat ${PACKAGES}) != "" ]]; then
        clear
        basestrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>$ERR
        check_for_error "$FUNCNAME" $?
    fi
}

# Network Manager
install_nm() {
    if [[ $NM_ENABLED -eq 0 ]]; then
        # Prep variables
        echo "" > ${PACKAGES}
        nm_list="connman CLI dhcpcd CLI netctl CLI NetworkManager GUI wicd GUI"
        NM_LIST=""
        NM_INST=""

        # Generate list of DMs installed with DEs, and a list for selection menu
        for i in ${nm_list}; do
            [[ -e ${MOUNTPOINT}/usr/bin/${i} ]] && NM_INST="${NM_INST} ${i}" && check_for_error "${i} already installed."
            NM_LIST="${NM_LIST} ${i}"
        done

        # Remove netctl from selectable list as it is a PITA to configure via arch_chroot
        NM_LIST=$(echo $NM_LIST | sed "s/netctl CLI//")

        DIALOG " $_InstNMTitle " --menu "\n$_AlreadyInst $NM_INST\n$_InstNMBody\n " 0 0 4 \
          ${NM_LIST} 2> ${PACKAGES}
        clear

        # If a selection has been made, act
        if [[ $(cat ${PACKAGES}) != "" ]]; then
            # check if selected nm already installed. If so, enable and break loop.
            for i in ${NM_INST}; do
                [[ $(cat ${PACKAGES}) == ${i} ]] && enable_nm && break
            done

            # If no match found, install and enable NM
            if [[ $NM_ENABLED -eq 0 ]]; then
                # Where networkmanager selected, add network-manager-applet
                sed -i 's/NetworkManager/networkmanager network-manager-applet/g' ${PACKAGES}
                basestrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>$ERR
                check_for_error "$FUNCNAME" "$?"

                # Where networkmanager selected, now remove network-manager-applet
                sed -i 's/networkmanager network-manager-applet/NetworkManager/g' ${PACKAGES}
                enable_nm
            fi
        fi
    fi

    # Show after successfully installing or where attempting to repeat when already completed.
    [[ $NM_ENABLED -eq 1 ]] && DIALOG " $_InstNMTitle " --msgbox "\n$_InstNMErrBody\n " 0 0
}

enable_nm() {
    # Add openrc support. If openrcbase was installed, the file /mnt/.openrc should exist.
    if [[ $(cat ${PACKAGES}) == "NetworkManager" ]]; then
        if [[ -e /mnt/.openrc ]]; then
            arch_chroot "rc-update add NetworkManager default" 2>$ERR
            check_for_error "add default NetworkManager." $?
        else
            arch_chroot "systemctl enable NetworkManager NetworkManager-dispatcher" >/tmp/.symlink 2>$ERR
            check_for_error "enable NetworkManager." $?
        fi
    else
        if [[ -e /mnt/.openrc ]]; then
            arch_chroot "rc-update add $(cat ${PACKAGES}) default" 2>$ERR
            check_for_error "add default $(cat ${PACKAGES})." $?
        else            
            arch_chroot "systemctl enable $(cat ${PACKAGES})" 2>$ERR
            check_for_error "enable $(cat ${PACKAGES})." $?
        fi
    fi
    NM_ENABLED=1
}

install_cups() {
    DIALOG " $_InstNMMenuCups " --checklist "\n$_InstCupsBody\n\n$_UseSpaceBar\n " 0 0 5 \
      "cups" "-" on \
      "cups-pdf" "-" off \
      "ghostscript" "-" on \
      "gsfonts" "-" on \
      "samba" "-" off 2>${PACKAGES}

    if [[ $(cat ${PACKAGES}) != "" ]]; then
        clear
        basestrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>$ERR
        check_for_error "$FUNCNAME" $?

    if [[ $(cat ${PACKAGES} | grep "cups") != "" ]]; then
        DIALOG " $_InstNMMenuCups " --yesno "\n$_InstCupsQ\n " 0 0
        if [[ $? -eq 0 ]]; then
            # Add openrc support. If openrcbase was installed, the file /mnt/.openrc should exist.
            if [[ -e /mnt/.openrc ]]; then
                arch_chroot "rc-update add cupsd default" 2>$ERR
            else
                arch_chroot "systemctl enable org.cups.cupsd.service" 2>$ERR
            fi
            check_for_error "enable cups" $?
            DIALOG " $_InstNMMenuCups " --infobox "\n$_Done!\n " 0 0
            sleep 2
            fi
        fi
    fi
}

install_multimedia_menu() {
    declare -i loopmenu=1
    while ((loopmenu)); do
        local PARENT="$FUNCNAME"

        submenu 4
        DIALOG " $_InstMultMenuTitle " --default-item ${HIGHLIGHT_SUB} --menu "\n$_InstMultMenuBody\n " 0 0 4 \
          "1" "$_InstMulSnd" \
          "2" "$_InstMulCodec" \
          "3" "$_InstMulAcc" \
          "4" "$_Back" 2>${ANSWER}

        HIGHLIGHT_SUB=$(cat ${ANSWER})
        case $(cat ${ANSWER}) in
            "1") install_alsa_pulse
                ;;
            "2") install_codecs
                ;;
            "3") install_acc_menu
                ;;
            *) loopmenu=0
                ;;
        esac
    done
}

install_alsa_pulse() {
    # Prep Variables
    echo "" > ${PACKAGES}
    ALSA=""
    PULSE_EXTRA=""
    alsa=$(pacman -Ss alsa | awk '{print $1}' | grep "/alsa-" | sed "s/extra\///g" | sort -u)
    pulse_extra=$(pacman -Ss pulseaudio- | awk '{print $1}' | sed "s/extra\///g" | grep "pulseaudio-" | sort -u)

    for i in ${alsa}; do
        ALSA="${ALSA} ${i} - off"
    done

    ALSA=$(echo $ALSA | sed "s/alsa-utils - off/alsa-utils - on/g" | sed "s/alsa-plugins - off/alsa-plugins - on/g")

    for i in ${pulse_extra}; do
        PULSE_EXTRA="${PULSE_EXTRA} ${i} - off"
    done

    DIALOG " $_InstMulSnd " --checklist "\n$_InstMulSndBody\n\n$_UseSpaceBar\n " 0 0 6 \
      $ALSA "pulseaudio" "-" off $PULSE_EXTRA \
      "paprefs" "pulseaudio GUI" off \
      "pavucontrol" "pulseaudio GUI" off \
      "ponymix" "pulseaudio CLI" off \
      "volumeicon" "ALSA GUI" off \
      "volwheel" "ASLA GUI" off 2>${PACKAGES}

    clear
    # If at least one package, install.
    if [[ $(cat ${PACKAGES}) != "" ]]; then
        basestrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>$ERR
        check_for_error "$FUNCNAME" "$?"
    fi
}

install_codecs() {
    # Prep Variables
    echo "" > ${PACKAGES}
    GSTREAMER=""
    gstreamer=$(pacman -Ss gstreamer | awk '{print $1}' | grep "/gstreamer" | sed "s/extra\///g" | sed "s/community\///g" | sort -u)
    echo $gstreamer
    for i in ${gstreamer}; do
        GSTREAMER="${GSTREAMER} ${i} - off"
    done

    DIALOG " $_InstMulCodec " --checklist "\n$_InstMulCodBody\n\n$_UseSpaceBar\n " 0 0 14 \
    $GSTREAMER "xine-lib" "-" off 2>${PACKAGES}

    clear
    # If at least one package, install.
    if [[ $(cat ${PACKAGES}) != "" ]]; then
        basestrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>$ERR
        check_for_error "$FUNCNAME" "$?"
    fi
}

# Install Accessibility Applications
install_acc_menu() {
    echo "" > ${PACKAGES}

    DIALOG " $_InstMulAcc " --checklist "\n$_InstMulAccBody\n " 0 0 15 \
      "accerciser" "-" off \
      "at-spi2-atk" "-" off \
      "at-spi2-core" "-" off \
      "brltty" "-" off \
      "caribou" "-" off \
      "dasher" "-" off \
      "espeak" "-" off \
      "espeakup" "-" off \
      "festival" "-" off \
      "java-access-bridge" "-" off \
      "java-atk-wrapper" "-" off \
      "julius" "-" off \
      "orca" "-" off \
      "qt-at-spi" "-" off \
      "speech-dispatcher" "-" off 2>${PACKAGES}

    clear
    # If something has been selected, install
    if [[ $(cat ${PACKAGES}) != "" ]]; then
        basestrap ${MOUNTPOINT} ${PACKAGES} 2>$ERR
        check_for_error "$FUNCNAME" $? || return $?
    fi
}

security_menu() {
    declare -i loopmenu=1
    while ((loopmenu)); do
        local PARENT="$FUNCNAME"
        ssubmenu 4
        DIALOG " $_SecMenuTitle " --default-item ${HIGHLIGHT_SSUB} --menu "\n$_SecMenuBody\n " 0 0 4 \
          "1" "$_SecJournTitle" \
          "2" "$_SecCoreTitle" \
          "3" "$_SecKernTitle " \
          "4" "$_Back" 2>${ANSWER}
        HIGHLIGHT_SSUB=$(cat ${ANSWER})

        case $(cat ${ANSWER}) in
            # systemd-journald
            "1") DIALOG " $_SecJournTitle " --menu "\n$_SecJournBody\n " 0 0 7 \
                   "$_Edit" "/etc/systemd/journald.conf" \
                   "10M" "SystemMaxUse=10M" \
                   "20M" "SystemMaxUse=20M" \
                   "50M" "SystemMaxUse=50M" \
                   "100M" "SystemMaxUse=100M" \
                   "200M" "SystemMaxUse=200M" \
                   "$_Disable" "Storage=none" 2>${ANSWER}

                 if [[ $(cat ${ANSWER}) != "" ]]; then
                     if [[ $(cat ${ANSWER}) == "$_Disable" ]]; then
                         sed -i "s/#Storage.*\|Storage.*/Storage=none/g" ${MOUNTPOINT}/etc/systemd/journald.conf
                         sed -i "s/SystemMaxUse.*/#&/g" ${MOUNTPOINT}/etc/systemd/journald.conf
                         DIALOG " $_SecJournTitle " --infobox "\n$_Done!\n " 0 0
                         sleep 2
                     elif [[ $(cat ${ANSWER}) == "$_Edit" ]]; then
                         nano ${MOUNTPOINT}/etc/systemd/journald.conf
                     else
                         sed -i "s/#SystemMaxUse.*\|SystemMaxUse.*/SystemMaxUse=$(cat ${ANSWER})/g" ${MOUNTPOINT}/etc/systemd/journald.conf
                         sed -i "s/Storage.*/#&/g" ${MOUNTPOINT}/etc/systemd/journald.conf
                         DIALOG " $_SecJournTitle " --infobox "\n$_Done!\n " 0 0
                         sleep 2
                     fi
                 fi
                 ;;
            # core dump
            "2") DIALOG " $_SecCoreTitle " --menu "\n$_SecCoreBody\n " 0 0 2 \
                 "$_Disable" "Storage=none" \
                 "$_Edit" "/etc/systemd/coredump.conf" 2>${ANSWER}

                 if [[ $(cat ${ANSWER}) == "$_Disable" ]]; then
                     sed -i "s/#Storage.*\|Storage.*/Storage=none/g" ${MOUNTPOINT}/etc/systemd/coredump.conf
                     DIALOG " $_SecCoreTitle " --infobox "\n$_Done!\n " 0 0
                     sleep 2
                 elif [[ $(cat ${ANSWER}) == "$_Edit" ]]; then
                     nano ${MOUNTPOINT}/etc/systemd/coredump.conf
                 fi
                 ;;
            # Kernel log access
            "3") DIALOG " $_SecKernTitle " --menu "\n$_SecKernBody\n " 0 0 2 \
                 "$_Disable" "kernel.dmesg_restrict = 1" \
                 "$_Edit" "/etc/systemd/coredump.conf.d/custom.conf" 2>${ANSWER}

                  case $(cat ${ANSWER}) in
                      "$_Disable") echo "kernel.dmesg_restrict = 1" > ${MOUNTPOINT}/etc/sysctl.d/50-dmesg-restrict.conf
                                   DIALOG " $_SecKernTitle " --infobox "\n$_Done!\n " 0 0
                                   sleep 2 ;;
                      "$_Edit") [[ -e ${MOUNTPOINT}/etc/sysctl.d/50-dmesg-restrict.conf ]] && nano ${MOUNTPOINT}/etc/sysctl.d/50-dmesg-restrict.conf || \
                                  DIALOG " $_SeeConfErrTitle " --msgbox "\n$_SeeConfErrBody1\n " 0 0 ;;
                  esac
                 ;;
            *) loopmenu=0
                return 0
                 ;;
        esac
    done
}

enable_console_logging() {
  echo "ForwardToConsole=yes
TTYPath=/dev/tty12" >> /mnt/etc/systemd/jounald.conf
  sed -i '/MaxLevelConsole/ s/#//' /mnt/etc/systemd/journald.conf
}

enable_hibernation() { 
if DIALOG " Hibernation setup " --yesno "\nAre you sure you want to enable hibernation automatically? \n " 0 0; then
  if ! [[ -e /mnt/etc/fstab ]]; then
    generate_fstab
  fi
  basestrap ${MOUNTPOINT} hibernator
  arch_chroot "hibernator" 2>$ERR
  check_for_error "Running hibernator" $?
  [[ $? == 0 ]] && DIALOG " Hibernation setup " --infobox "\nHibernator was successfully run \n " 0 0
else
  return 0
fi
}

enable_autologin() {
  dm=$(file /mnt/etc/systemd/system/display-manager.service 2>/dev/null | awk -F'/' '{print $NF}' | cut -d. -f1)
  [[ -z $dm ]] && dm=xlogin
  if DIALOG " Autologin setup " --yesno "\nThis option enables autologin using $dm.\n\nProceed? \n " 0 0; then
      #detect displaymanager
      if [[ $(echo /mnt/home/* | xargs -n1 | wc -l) == 1 ]]; then
        autologin_user=$(echo /mnt/home/* | cut -d/ -f4)
      else
        autologin_user=$(echo /mnt/home/* | cut -d/ -f4 | fzf --reverse --prompt="user> " --header="Choose the user to automatically log in")
      fi
      #enable autologin
      case "$(echo $dm)" in 
        gdm)      sed -i "s/^AutomaticLogin=*/AutomaticLogin=$autologin_user/g" /mnt/etc/gdm/custom.conf
                  sed -i 's/^AutomaticLoginEnable=*/AutomaticLoginEnable=true/g' /mnt/etc/gdm/custom.conf
                  sed -i 's/^TimedLoginEnable=*/TimedLoginEnable=true/g' /mnt/etc/gdm/custom.conf
                  sed -i 's/^TimedLogin=*/TimedLoginEnable=$autologin_user/g' /mnt/etc/gdm/custom.conf
                  sed -i 's/^TimedLoginDelay=*/TimedLoginDelay=0/g' /mnt/etc/gdm/custom.conf    
            ;;
        lightdm)  sed -i "s/^#autologin-user=/autologin-user=$autologin_user/" /mnt/etc/lightdm/lightdm.conf
                  sed -i 's/^#autologin-user-timeout=0/autologin-user-timeout=0/' /mnt/etc/lightdm/lightdm.conf
                  arch_chroot "groupadd -r autologin"
                  arch_chroot "gpasswd -a $autologin_user autologin"
            ;;
        sddm)     xsession=$(echo /mnt/usr/share/xsessions/* | xargs -n1 | head -n1 | rev | cut -d'/' -f 1 | rev)
                  [[ -e /mnt/etc/sddm.conf ]] || arch_chroot "sddm --example-config > /etc/sddm.conf"
                  sed -i "s/^User=/User=$autologin_user/g" /mnt/etc/sddm.conf
                  sed -i "s~^Session=~Session=$xsession~g" /mnt/etc/sddm.conf
            ;;
        lxdm)     sed -i "s/^# autologin=dgod/autologin=$autologin_user/g" /mnt/etc/lxdm/lxdm.conf
            ;;
        *)        basestrap ${MOUNTPOINT} "xlogin"
                  arch_chroot "systemctl enable xlogin@${autologin_user}"
            ;;
      esac
fi
}

set_schedulers() {
  [[ -e /mnt/etc/udev/rules.d/60-ioscheduler.rules ]] ||  \
  echo '# set scheduler for non-rotating disks
# noop and deadline are recommended for non-rotating disks
# for rotational disks, cfq gives better performance and bfq-sq more responsive desktop environment
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="deadline"
# set scheduler for rotating disks
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq-sq"' > /mnt/etc/udev/rules.d/60-ioscheduler.rules
  nano /mnt/etc/udev/rules.d/60-ioscheduler.rules
}

set_swappiness() {
  [[ -e /mnt/etc/sysctl.d/99-sysctl.conf ]] ||  \
  echo 'vm.swappiness = 10
vm.vfs_cache_pressure = 50
#vm.dirty_ratio = 3' > /mnt/etc/sysctl.d/99-sysctl.conf
  nano /mnt/etc/sysctl.d/99-sysctl.conf
}

preloader() {
  if DIALOG " Preload setup " --yesno "\n Enabling preload loads often used applications to ram in advance in order to start them up more quickly. \n\nProceed? \n " 0 0; then
    basestrap ${MOUNTPOINT} "preload"
    arch_chroot "systemctl enable preload"
  fi

}
