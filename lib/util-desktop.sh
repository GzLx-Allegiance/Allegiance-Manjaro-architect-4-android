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

setup_graphics_card() {
    DIALOG " $_GCDetBody " --radiolist "\n$_UseSpaceBar\n " 0 0 12 \
      $(mhwd -l | awk '/ video-/{print $1}' | awk '$0=$0" - off"' | sort | uniq)  2>/tmp/.driver || return 0

    if [[ $(cat /tmp/.driver) != "" ]]; then
        clear
        mhwd --pmcachedir "$cachepath" --pmroot $MOUNTPOINT -f -i pci $(cat /tmp/.driver) 2>$ERR
        check_for_error "install $(cat /tmp/.driver)" $?
        touch /mnt/.video_installed

        GRAPHIC_CARD=$(lspci | grep -i "vga" | sed 's/.*://' | sed 's/(.*//' | sed 's/^[ \t]*//')

        # All non-NVIDIA cards / virtualisation
        if [[ $(echo $GRAPHIC_CARD | grep -i 'intel\|lenovo') != "" ]]; then
            install_intel
        elif [[ $(echo $GRAPHIC_CARD | grep -i 'ati') != "" ]]; then
            install_ati
        elif [[ $(cat /tmp/.driver) == "video-nouveau" ]]; then
            sed -i 's/MODULES=""/MODULES="nouveau"/' ${MOUNTPOINT}/etc/mkinitcpio.conf
        fi
    else
        DIALOG " $_ErrTitle " --msgbox "\n$_WarnInstGr\n " 0 0
        check_for_error "No video-driver selected."
    fi
}

setup_network_drivers() {
    DIALOG " $_InstNWDrv " --menu "\n " 0 0 3 \
          "1" "$_InstFree" \
          "2" "$_InstProp" \
          "3" "$_SelNWDrv" 2>${ANSWER} || return 0

    case $(cat ${ANSWER}) in
        "1") clear
            arch_chroot "mhwd -a pci free 0200" 2>$ERR
            check_for_error "$FUNCNAME free" $?
            ;;
        "2") clear
            arch_chroot "mhwd -a pci nonfree 0200" 2>$ERR
            check_for_error "$FUNCNAME nonfree" $?
            ;;
        "3") if [[ $(mhwd -l | awk '/ network-/' | wc -l) -eq 0 ]]; then 
                DIALOG " $_InstNWDrv " --msgbox "\n$_InfoNWKernel\n " 0 0
            else
                DIALOG " $_InstGrDrv " --checklist "\n$_UseSpaceBar\n " 0 0 12 \
                  $(mhwd -l | awk '/ network-/{print $1}' |awk '$0=$0" - off"')  2> /tmp/.network_driver || return 0

                if [[ $(cat /tmp/.driver) != "" ]]; then
                    clear
                    arch_chroot "mhwd -f -i pci $(cat /tmp/.network_driver)" 2>$ERR
                    check_for_error "install $(cat /tmp/.network_driver)" $? || return 1
                else
                    DIALOG " $_ErrTitle " --msgbox "\nNo network driver selected\n " 0 0
                    check_for_error "No network-driver selected."
                fi
            fi
            ;;
    esac
}

install_network_drivers() {
    if [[ $(mhwd -l | awk '/network-/' | wc -l) -gt 0 ]]; then 
        for driver in $(mhwd -l | awk '/^network-/{print $1}'); do
            arch_chroot "mhwd -f -i pci ${driver}" 2>$ERR
            check_for_error "install ${driver}" $?
        done
    else
        echo "No special network drivers installed because no need detected."
    fi
}

install_intel() {
    sed -i 's/MODULES=""/MODULES="i915"/' ${MOUNTPOINT}/etc/mkinitcpio.conf

    # Intel microcode (Grub, Syslinux and systemd-boot).
    # Done as seperate if statements in case of multiple bootloaders.
    if [[ -e ${MOUNTPOINT}/boot/grub/grub.cfg ]]; then
        DIALOG " grub-mkconfig " --infobox "\n$_PlsWaitBody\n " 0 0
        sleep 1
        grub_mkconfig
    fi
    # Syslinux
    [[ -e ${MOUNTPOINT}/boot/syslinux/syslinux.cfg ]] && sed -i "s/INITRD /&..\/intel-ucode.img,/g" ${MOUNTPOINT}/boot/syslinux/syslinux.cfg

    # Systemd-boot
    if [[ -e ${MOUNTPOINT}${UEFI_MOUNT}/loader/loader.conf ]]; then
        update=$(ls ${MOUNTPOINT}${UEFI_MOUNT}/loader/entries/*.conf)
        for i in ${upgate}; do
            sed -i '/linux \//a initrd \/intel-ucode.img' ${i}
        done
    fi
}

install_all_drivers() {

    cat $PROFILES/shared/Packages-Mhwd > /tmp/.all_drivers

    # Remove any packages tagged with >openrc and remove >systemd tags
    sed -i '/>openrc/d' /tmp/.all_drivers
    sed -i 's/>systemd //g' /tmp/.all_drivers
    sed -i '/>multilib/d' /tmp/.all_drivers
    sed -i '/>nonfree_multilib/d' /tmp/.all_drivers
    sed -i '/>nonfree_default/d' /tmp/.all_drivers
    sed -i '/virtualbox/d' /tmp/.all_drivers
    grep "KERNEL-" /tmp/.all_drivers > /tmp/.kernel_dependent
    for kernel in $(cat /tmp/.chosen_kernels); do
            cat /tmp/.kernel_dependent | sed "s/KERNEL/\n$kernel/g" >> /tmp/.all_drivers
            echo "" >> /tmp/.all_drivers
    done
    sed -i '/KERNEL-/d' /tmp/.all_drivers
    if $hostcache; then
        basestrap ${MOUNTPOINT} $(cat /tmp/.all_drivers)
    else
        basestrap -c ${MOUNTPOINT} $(cat /tmp/.all_drivers)
    fi
}
install_ati() {
    sed -i 's/MODULES=""/MODULES="radeon"/' ${MOUNTPOINT}/etc/mkinitcpio.conf
}

# Set keymap for X11
set_xkbmap() {
    XKBMAP_LIST=""
    keymaps_xkb=("af al am at az ba bd be bg br bt bw by ca cd ch cm cn cz de dk ee es et eu fi fo fr\
      gb ge gh gn gr hr hu ie il in iq ir is it jp ke kg kh kr kz la lk lt lv ma md me mk ml mm mn mt mv\
      ng nl no np pc ph pk pl pt ro rs ru se si sk sn sy tg th tj tm tr tw tz ua us uz vn za")

    for i in ${keymaps_xkb}; do
        XKBMAP_LIST="${XKBMAP_LIST} ${i} -"
    done

    DIALOG " $_PrepKBLayout " --menu "\n$_XkbmapBody\n " 0 0 16 ${XKBMAP_LIST} 2>${ANSWER} || return 0
    XKBMAP=$(cat ${ANSWER} |sed 's/_.*//')
    echo -e "Section "\"InputClass"\"\nIdentifier "\"system-keyboard"\"\nMatchIsKeyboard "\"on"\"\nOption "\"XkbLayout"\" "\"${XKBMAP}"\"\nEndSection" \
      > ${MOUNTPOINT}/etc/X11/xorg.conf.d/00-keyboard.conf 2>$ERR
    check_for_error "$FUNCNAME ${XKBMAP}" "$?"
}

install_manjaro_de_wm_pkg() {
    if check_desktop; then
        PROFILES="/usr/share/manjaro-tools/iso-profiles"
        # Only show this information box once
        if [[ $SHOW_ONCE -eq 0 ]]; then
            DIALOG " $_InstDETitle " --msgbox "\n$_InstPBody\n " 0 0
            SHOW_ONCE=1
        fi
        clear
        pacman -Sy --noconfirm $p manjaro-iso-profiles-{base,official,community} 2>$ERR
        check_for_error "update profiles pkgs" $?

        install_manjaro_de_wm
    fi
}

install_manjaro_de_wm() {
    # Clear packages after installing base
    echo "" > /tmp/.desktop

    # DE/WM Menu
    DIALOG " $_InstDETitle " --radiolist "\n$_InstManDEBody\n$(evaluate_profiles)\n\n$_UseSpaceBar\n " 0 0 14 \
      $(echo $PROFILES/{manjaro,community}/* | xargs -n1 | cut -f7 -d'/' | grep -vE "netinstall|architect" | awk '$0=$0" - off"')  2> /tmp/.desktop

    # If something has been selected, install
    if [[ $(cat /tmp/.desktop) != "" ]]; then
        check_for_error "selected: [Manjaro-$(cat /tmp/.desktop)]"
        clear
        # Source the iso-profile
        profile=$(echo $PROFILES/*/$(cat /tmp/.desktop)/profile.conf)
        . $profile        
        overlay=$(echo $PROFILES/*/$(cat /tmp/.desktop)/desktop-overlay/)
        echo $displaymanager > /tmp/.display-manager

        # Parse package list based on user input and remove parts that don't belong to pacman
        pkgs_src=$(echo $PROFILES/*/$(cat /tmp/.desktop)/Packages-Desktop)
        pkgs_target=/mnt/.desktop
        echo "" > $pkgs_target
        filter_packages
        # remove already installed base pkgs and
        # basestrap the parsed package list to the new root
        check_for_error "packages to install: $(grep -vf /mnt/.base /mnt/.desktop | sort | tr '\n' ' ')"
        clear
        set -o pipefail
        if $hostcache; then
            basestrap ${MOUNTPOINT} $(cat /mnt/.desktop) 2>$ERR |& tee /tmp/basestrap.log
        else 
            basestrap -c ${MOUNTPOINT} $(cat /mnt/.desktop) 2>$ERR |& tee /tmp/basestrap.log
        fi
        local err=$?
        set +o pipefail
        check_for_error "install desktop-pkgs" $err || return $err

        # copy the profile overlay to the new root
        echo "Copying overlay files to the new root"
        cp -r "$overlay"* ${MOUNTPOINT} 2>$ERR
        check_for_error "copy overlay" "$?"

        # Copy settings to root account
        cp -ar $MOUNTPOINT/etc/skel/. $MOUNTPOINT/root/ 2>$ERR
        check_for_error "copy root config" "$?"

        # copy settings to already created users
        if [[ -e "$(echo /mnt/home/*)" ]]; then
            for home in $(echo $MOUNTPOINT/home/*); do
                cp -ar $MOUNTPOINT/etc/skel/. $home/
                user=$(echo $home | cut -d/ -f4)
                arch_chroot "chown -R ${user}:${user} /home/${user}"
            done
        fi
        # Enable services in the chosen profile
        enable_services
        install_graphics_menu
        touch /mnt/.desktop_installed
        # Stop for a moment so user can see if there were errors
        echo ""
        echo ""
        echo ""
        echo "press Enter to continue"
        read
        # Clear the packages file for installation of "common" packages
        echo "" > ${PACKAGES}

        # Offer to install various "common" packages.
        #install_extra
    fi
}
install_desktop() {
    if [[ -e /mnt/.base_installed ]]; then
        DIALOG " $_InstBseTitle " --yesno "\n$_WarnInstBase\n " 0 0 && rm /mnt/.base_installed || return 0
    fi
    # Prep variables
    touch /tmp/.git_profiles
    setup_profiles
    pkgs_src=$PROFILES/shared/Packages-Root
    pkgs_target=/mnt/.base
    BTRF_CHECK=$(echo "btrfs-progs" "" off)
    F2FS_CHECK=$(echo "f2fs-tools" "" off)
    mhwd-kernel -l | awk '/linux/ {print $2}' > /tmp/.available_kernels
    kernels=$(cat /tmp/.available_kernels)
    
    # Create the base list of packages
    echo "" > /mnt/.base

    declare -i loopmenu=1
    while ((loopmenu)); do
        # Choose kernel and possibly base-devel
        DIALOG " $_InstBseTitle " --checklist "\n$_InstStandBseBody$_UseSpaceBar\n " 0 0 12 \
          "yay + base-devel" "-" off \
          $(cat /tmp/.available_kernels | awk '$0=$0" - off"') 2>${PACKAGES} || { loopmenu=0; return 0; }
        if [[ ! $(grep "linux" ${PACKAGES}) ]]; then
            # Check if a kernel is already installed
            ls ${MOUNTPOINT}/boot/*.img >/dev/null 2>&1
            if [[ $? == 0 ]]; then
                DIALOG " Check Kernel " --msgbox "\nlinux-$(ls ${MOUNTPOINT}/boot/*.img | cut -d'-' -f2 | grep -v ucode.img | sort -u) detected \n " 0 0
                check_for_error "linux-$(ls ${MOUNTPOINT}/boot/*.img | cut -d'-' -f2) already installed"
                loopmenu=0
            else
                DIALOG " $_ErrTitle " --msgbox "\n$_ErrNoKernel\n " 0 0
            fi
        else
            cat ${PACKAGES} | sed 's/+ \|\"//g' | tr ' ' '\n' | tr '+' '\n' >> /mnt/.base
            echo " " >> /mnt/.base
            grep -f /tmp/.available_kernels /mnt/.base > /tmp/.chosen_kernels
            check_for_error "selected: $(cat ${PACKAGES})"
            loopmenu=0
        fi
    done

    local zfs_is_checked
    [[ $ZFS == 1 ]] && zfs_is_checked="on" || zfs_is_checked="off"

    # Choose wanted kernel modules
    DIALOG " $_ChsAddPkgs " --checklist "\n$_UseSpaceBar\n " 0 0 12 \
      "KERNEL-headers" "-" off \
      "KERNEL-acpi_call" "-" off \
      "KERNEL-ndiswrapper" "-" off \
      "KERNEL-broadcom-wl" "-" off \
      "KERNEL-r8168" "-" off \
      "KERNEL-rt3562sta" "-" off \
      "KERNEL-tp_smapi" "-" off \
      "KERNEL-vhba-module" "-" off \
      "KERNEL-virtualbox-guest-modules" "-" off \
      "KERNEL-virtualbox-host-modules" "-" off \
      "KERNEL-spl" "-" $zfs_is_checked \
      "KERNEL-zfs" "-" $zfs_is_checked 2>/tmp/.modules || return 0

    if [[ $(cat /tmp/.modules) != "" ]]; then
        check_for_error "modules: $(cat /tmp/.modules)"
        for kernel in $(cat ${PACKAGES} | grep -vE '(yay|base-devel)'); do
            cat /tmp/.modules | sed "s/KERNEL/\n$kernel/g" >> /mnt/.base
        done
        echo " " >> /mnt/.base
    fi

    choose_mjr_desk

    filter_packages
    # remove grub
    sed -i '/grub/d' /mnt/.base
    echo "nilfs-utils" >> /mnt/.base
    check_for_error "packages to install: $(cat /mnt/.base | sort | tr '\n' ' ')"
    clear
    set -o pipefail
    if $hostcache; then
        basestrap ${MOUNTPOINT} $(cat /mnt/.base) 2>$ERR |& tee /tmp/basestrap.log
    else
        basestrap -c ${MOUNTPOINT} $(cat /mnt/.base) 2>$ERR |& tee /tmp/basestrap.log
    fi
    
    local err=$?
    set +o pipefail
    check_for_error "install basepkgs" $err || {
        DIALOG " $_InstBseTitle " --msgbox "\n$_InstFail\n " 0 0; HIGHLIGHT_SUB=2;
        if [[ $err == 255 ]]; then
            cat /tmp/basestrap.log
            read -n1 -s # or ? exit $err
        fi
        return 1;
    }

    # copy keymap and consolefont settings to target
        echo -e "KEYMAP=$(ini linux.keymap)\nFONT=$(ini linux.font)" > ${MOUNTPOINT}/etc/vconsole.conf
        check_for_error "configure vconsole"

    # mkinitcpio handling for specific filesystems
    case $(findmnt -ln -o FSTYPE ${MOUNTPOINT}) in
        btrfs)  
            BTRFS_ROOT=1
            sed -e '/^HOOKS=/s/\ fsck//g' -e '/^MODULES=/s/"$/ btrfs"/g' -i ${MOUNTPOINT}/etc/mkinitcpio.conf
            check_for_error "root on btrfs volume. Amend mkinitcpio."
            # Adjust tlp settings to avoid filesystem corruption
            if [[ -e /mnt/etc/default/tlp ]]; then
                sed -i 's/SATA_LINKPWR_ON_BAT.*/SATA_LINKPWR_ON_BAT=max_performance/' /mnt/etc/default/tlp
            fi
            ;;
        nilfs2)
            sed -e '/^HOOKS=/s/\ fsck//g' -i ${MOUNTPOINT}/etc/mkinitcpio.conf
            check_for_error "root on nilfs2 volume. Amend mkinitcpio."
            ;;
        zfs)
            ZFS_ROOT=1
            # the order is important here so strip out what we want changed and put it back in the correct order
            sed -e '/^HOOKS=/s/\ filesystems//g' -e '/^HOOKS=/s/\ keyboard/\ keyboard\ zfs\ filesystems/g' -e '/^HOOKS=/s/\ fsck//g' -e '/^FILES=/c\FILES=("/usr/lib/libgcc_s.so.1")' -i ${MOUNTPOINT}/etc/mkinitcpio.conf
            check_for_error "root on zfs volume. Amend mkinitcpio."
            ;;
    esac

    recheck_luks
    
    # add luks and lvm hooks as needed
    ([[ $LVM -eq 1 ]] && [[ $LUKS -eq 0 ]]) && { sed -i 's/block filesystems/block lvm2 filesystems/g' ${MOUNTPOINT}/etc/mkinitcpio.conf 2>$ERR; check_for_error "add lvm2 hook" $?; }
    ([[ $LVM -eq 0 ]] && [[ $LUKS -eq 1 ]]) && { sed -i 's/block filesystems keyboard/block consolefont keymap keyboard encrypt filesystems/g' ${MOUNTPOINT}/etc/mkinitcpio.conf 2>$ERR; check_for_error "add luks hook" $?; }
    [[ $((LVM + LUKS)) -eq 2 ]] && { sed -i 's/block filesystems keyboard/block consolefont keymap keyboard encrypt lvm2 filesystems/g' ${MOUNTPOINT}/etc/mkinitcpio.conf 2>$ERR; check_for_error "add lvm/luks hooks" $?; }

    [[ $((LVM + LUKS + BTRFS_ROOT + ZFS_ROOT)) -gt 0 ]] && { arch_chroot "mkinitcpio -P" 2>$ERR; check_for_error "re-run mkinitcpio" $?; }

    # If specified, copy over the pacman.conf file to the installation
    if [[ $COPY_PACCONF -eq 1 ]]; then
        cp -f /etc/pacman.conf ${MOUNTPOINT}/etc/pacman.conf
        check_for_error "copy pacman.conf"
    fi

    # if branch was chosen, use that also in installed system. If not, use the system setting
    [[ -z $(ini branch) ]] && ini branch $(ini system.branch)
    sed -i "s/Branch =.*/Branch = $(ini branch)/;s/# //" ${MOUNTPOINT}/etc/pacman-mirrors.conf

    touch /mnt/.base_installed
    check_for_error "base installed succesfully."


    ## Setup desktop
    if [[ $(cat /tmp/.desktop) != "" ]]; then
    # copy the profile overlay to the new root
        echo "Copying overlay files to the new root"
        cp -r "$overlay"* ${MOUNTPOINT} 2>$ERR
        check_for_error "copy overlay" "$?"

        # Copy settings to root account
        cp -ar $MOUNTPOINT/etc/skel/. $MOUNTPOINT/root/ 2>$ERR
        check_for_error "copy root config" "$?"

        # copy settings to already created users
        if [[ -e "$(echo /mnt/home/*)" ]]; then
            for home in $(echo $MOUNTPOINT/home/*); do
                cp -ar $MOUNTPOINT/etc/skel/. $home/
                user=$(echo $home | cut -d/ -f4)
                arch_chroot "chown -R ${user}:${user} /home/${user}"
            done
        fi
        # Enable services in the chosen profile
        enable_services
        install_graphics_menu
        touch /mnt/.desktop_installed
        # Stop for a moment so user can see if there were errors
        echo ""
        echo ""
        echo ""
        echo "press Enter to continue"
        read
    else 
        install_network_drivers
    fi  
}

choose_mjr_desk() {
    # Clear packages after installing base
    echo "" > /tmp/.desktop

    # DE/WM Menu
    DIALOG " $_InstDETitle " --radiolist "\n$_InstManDEBody\n\n$_UseSpaceBar\n " 0 0 15 \
      $(echo $PROFILES/{manjaro,community}/* | xargs -n1 | cut -f7 -d'/' | grep -vE "netinstall|architect" | awk '$0=$0" - off"')  2> /tmp/.desktop

    # If something has been selected, install
    if [[ $(cat /tmp/.desktop) != "" ]]; then
        check_for_error "selected: [Manjaro-$(cat /tmp/.desktop)]"
        clear
        # Source the iso-profile
        profile=$(echo $PROFILES/*/$(cat /tmp/.desktop)/profile.conf)
        . $profile        
        overlay=$(echo $PROFILES/*/$(cat /tmp/.desktop)/desktop-overlay/)
        echo $displaymanager > /tmp/.display-manager

        cat $(echo $PROFILES/*/$(cat /tmp/.desktop)/Packages-Desktop) > /mnt/.desktop
		echo "" >> /mnt/.desktop
        DIALOG " $_ExtraPkgTitle " --yesno "\n$_ExtraPkgBody \n " 0 0 && \
        echo "$(pacman -Ssq) $(pacman -Sg)" | fzf -m -e --header="$_AddPkgs" --prompt="$_AddPkgsPrmpt > " --reverse >> /mnt/.desktop
    
    fi
}

set_lightdm_greeter() {
    local greeters=$(ls /mnt/usr/share/xgreeters/*greeter.desktop) name
    for g in ${greeters[@]}; do
        name=${g##*/}
        name=${name%%.*}
        case ${name} in
            lightdm-gtk-greeter)
                break
                ;;
            lightdm-*-greeter)
                sed -i -e "s/^.*greeter-session=.*/greeter-session=${name}/" /mnt/etc/lightdm/lightdm.conf
                ;;
        esac
    done
}

set_sddm_ck() {
    local halt='/usr/bin/shutdown -h -P now' \
      reboot='/usr/bin/shutdown -r now'
    sed -e "s|^.*HaltCommand=.*|HaltCommand=${halt}|" \
      -e "s|^.*RebootCommand=.*|RebootCommand=${reboot}|" \
      -e "s|^.*MinimumVT=.*|MinimumVT=7|" \
      -i "/mnt/etc/sddm.conf"
    arch_chroot "gpasswd -a sddm video" 2>$ERR
    check_for_error "$FUNCNAME" $?
}
