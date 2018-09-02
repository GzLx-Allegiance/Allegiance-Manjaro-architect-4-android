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

import /usr/lib/manjaro-architect/util-desktop.sh 

main_menu() {
    declare -i loopmenu=1
    while ((loopmenu)); do
        if [[ $HIGHLIGHT != 6 ]]; then
           HIGHLIGHT=$(( HIGHLIGHT + 1 ))
        fi

        DIALOG " $_MMTitle " --default-item ${HIGHLIGHT} \
          --menu "\n$_MMNewBody\n " 20 60 6 \
          "1" "$_PrepMenuTitle|>" \
          "2" "$_InstDsMenuTitle|>" \
          "3" "$_InstCrMenuTitle|>" \
          "4" "$_InstCsMenuTitle|>" \
          "5" "$_SysRescTitle|>" \
          "6" "$_Done" 2>${ANSWER}
        HIGHLIGHT=$(cat ${ANSWER})

        case $(cat ${ANSWER}) in
            "1") prep_menu
                ;;
            "2") check_mount && install_desktop_system_menu
                ;;
            "3") check_mount && install_core_menu
                ;;
            "4") check_mount && install_custom_menu
                ;;
            "5") system_rescue_menu
                ;;
             *) loopmenu=0
                exit_done
                ;;
        esac
    done
}


install_core_menu() {
    local PARENT="$FUNCNAME"
    declare -i loopmenu=1
    while ((loopmenu)); do
        submenu 8
        DIALOG " $_InstCrMenuTitle " --default-item ${HIGHLIGHT_SUB} --menu "\n$_MMBody\n$_InstCrMenuBody\n " 0 0 8 \
          "1" "$_InstBse" \
          "2" "$_InstBootldr|>" \
          "3" "$_ConfBseMenuTitle|>" \
          "4" "$_InstMulCust" \
          "5" "$_TweaksMenuTitle|>" \
          "6" "$_SeeConfOptTitle|>" \
          "7" "$_ChrootTitle" \
          "8" "$_Back" 2>${ANSWER}
        HIGHLIGHT_SUB=$(cat ${ANSWER})

        case $(cat ${ANSWER}) in
            "1") check_mount && install_base && setup_network_drivers
                 ;;
            "2") check_base && install_bootloader
                 ;;
            "3") check_base && config_cli_base_menu
                 ;;
            "4") install_cust_pkgs
                 ;;
            "5") check_base && tweaks_menu
                ;;
            "6") check_base && {
                    type edit_configs &>/dev/null || import ${LIBDIR}/util-config.sh
                    edit_configs
                    }
                ;;
            "7") check_base && chroot_interactive
                ;;
            *) loopmenu=0
                return 0
                 ;;
        esac
    done
}

install_desktop_system_menu() {
    local PARENT="$FUNCNAME"
    declare -i loopmenu=1
    while ((loopmenu)); do
        submenu 7
        DIALOG " $_InstDsMenuTitle " --default-item ${HIGHLIGHT_SUB} --menu "\n$_MMBody\n$_InstDsMenuBody\n " 22 60 7 \
          "1" "$_InstDEStable|>" \
          "2" "$_InstBootldr|>" \
          "3" "$_ConfBseMenuTitle|>" \
          "4" "$_TweaksMenuTitle|>" \
          "5" "$_SeeConfOptTitle|>" \
          "6" "$_ChrootTitle" \
          "7" "$_Back" 2>${ANSWER}
        HIGHLIGHT_SUB=$(cat ${ANSWER})

        case $(cat ${ANSWER}) in
            "1") check_mount && install_desktop
                 ;;
            "2") check_base && install_bootloader
                 ;;
            "3") check_base && config_base_menu
                 ;;
            "4") check_base && tweaks_menu
                ;;
            "5") check_base && {
                    type edit_configs &>/dev/null || import ${LIBDIR}/util-config.sh
                    edit_configs
                    }
                ;;
            "6") check_base && chroot_interactive
                ;;
            *) loopmenu=0
                return 0
                 ;;
        esac
    done
}

install_custom_menu() {
    local PARENT="$FUNCNAME"
    declare -i loopmenu=1
    while ((loopmenu)); do
        submenu 9
        DIALOG " $_InstCsMenuTitle " --default-item ${HIGHLIGHT_SUB} --menu "\n$_InstCsMenuBody\n " 22 60 9 \
          "1" "$_InstBse" \
          "2" "$_InstDE|>" \
          "3" "$_InstBootldr|>" \
          "4" "$_ConfBseMenuTitle|>" \
          "5" "$_InstMulCust" \
          "6" "$_TweaksMenuTitle|>" \
          "7" "$_SeeConfOptTitle" \
          "8" "$_ChrootTitle" \
          "9" "$_Back" 2>${ANSWER}
        HIGHLIGHT_SUB=$(cat ${ANSWER})

        case $(cat ${ANSWER}) in
            "1") check_mount && install_base && install_drivers_menu
                 ;;
            "2") check_base && install_vanilla_de_wm
                 ;;
            "3") check_base && install_bootloader
                 ;;
            "4") check_base && config_base_menu
                 ;;
            "5") install_cust_pkgs
                 ;;
            "6") check_base && tweaks_menu
                ;;
            "7") check_base && {
                    type edit_configs &>/dev/null || import ${LIBDIR}/util-config.sh
                    edit_configs
                    }
                ;;
            "8") check_base && chroot_interactive
                ;;
            *) loopmenu=0
                return 0
                 ;;
        esac
    done
}

system_rescue_menu() {
    local PARENT="$FUNCNAME"
    declare -i loopmenu=1
    while ((loopmenu)); do
        submenu 8
        DIALOG " $_SysRescTitle " --default-item ${HIGHLIGHT_SUB} --menu "\n$_SysRescBody\n " 24 60 10 \
          "1" "$_InstDrvTitle|>" \
          "2" "$_InstBootldr|>" \
          "3" "$_ConfBseMenuTitle" \
          "4" "$_InstMulCust" \
          "5" "$_RmPkgs" \
          "6" "$_SeeConfOptTitle|>" \
          "7" "$_ChrootTitle" \
          "8" "$_DataRecMenu|>" \
          "9" "$_LogMenu|>" \
          "10" "$_Back" 2>${ANSWER}
        HIGHLIGHT_SUB=$(cat ${ANSWER})

        case $(cat ${ANSWER}) in
            "1") check_mount && check_base && install_drivers_menu
                 ;;
            "2") check_mount && check_base && install_bootloader
                 ;;
            "3") check_mount && check_base && config_base_menu
                 ;;
            "4") check_mount && install_cust_pkgs
                 ;;
            "5") check_mount && check_base && rm_pgs
                 ;;
            "6") check_mount && check_base && {
                    type edit_configs &>/dev/null || import ${LIBDIR}/util-config.sh
                    edit_configs
                    }
                ;;
            "7") check_mount && check_base && chroot_interactive
                ;;
            "8") recovery_menu
                ;;
            "9") check_mount && check_base && logs_menu
                ;;
            *) loopmenu=0
                return 0
                 ;;
        esac
    done
}

# Preparation
prep_menu() {
    local PARENT="$FUNCNAME"
    declare -i loopmenu=1
    while ((loopmenu)); do
        submenu 9
        DIALOG " $_PrepMenuTitle " --default-item ${HIGHLIGHT_SUB} --menu "\n$_PrepMenuBody\n " 20 60 10 \
          "1" "$_VCKeymapTitle" \
          "2" "$_DevShowOpt" \
          "3" "$_PrepPartDisk|>" \
          "4" "$_PrepLUKS|>" \
          "5" "$_PrepLVM $_PrepLVM2|>" \
          "6" "$_PrepMntPart" \
          "7" "$_PrepMirror|>" \
          "8" "$_PrepPacKey" \
          "9" "$_HostCache" \
          "10" "$_Back" 2>${ANSWER}
        HIGHLIGHT_SUB=$(cat ${ANSWER})

        case $(cat ${ANSWER}) in
            "1") select_keymap
                 set_keymap
                 ;;
            "2") show_devices
                 ;;
            "3") umount_partitions
                 select_device && create_partitions
                 ;;
            "4") luks_menu
                 ;;
            "5") lvm_menu
                 ;;
            "6") mount_partitions
                 ;;
            "7") configure_mirrorlist
                 ;;
            "8") clear
                 (
                    ctrlc(){
                      return 0
                    }
                    trap ctrlc SIGINT
                    trap ctrlc SIGTERM
                    pacman-key --init;pacman-key --populate archlinux manjaro;pacman-key --refresh-keys;
                    check_for_error 'refresh pacman-keys'
                  )
                 ;;
            "9") set_cache
                 ;;
            *) loopmenu=0
                return 0
                 ;;
        esac
    done
}

# Base Installation
install_base_menu() {
    local PARENT="$FUNCNAME"
    declare -i loopmenu=1
    while ((loopmenu)); do
        submenu 6
        DIALOG " $_InstBsMenuTitle " --default-item ${HIGHLIGHT_SUB} --menu "\n$_InstBseMenuBody\n " 0 0 6 \
          "1" "$_PrepMirror|>" \
          "2" "$_PrepPacKey" \
          "3" "$_InstBse" \
          "4" "$_InstDEStable|>" \
          "5" "$_InstBootldr" \
          "6" "$_Back" 2>${ANSWER}
        HIGHLIGHT_SUB=$(cat ${ANSWER})

        case $(cat ${ANSWER}) in
            "1") configure_mirrorlist
                 ;;
            "2") clear
                 (
                    ctrlc(){
                      return 0
                    }
                    trap ctrlc SIGINT
                    trap ctrlc SIGTERM
                    pacman-key --init;pacman-key --populate archlinux manjaro;pacman-key --refresh-keys;
                    check_for_error 'refresh pacman-keys'
                  )
                 ;;
            "3") install_base
                 ;;
            "4") check_base && install_manjaro_de_wm_pkg
                    local err=$?
                    if [[ $err > 0 ]]; then
                        DIALOG " $_InstBseTitle " --msgbox "\n$_InstFail\n " 0 0;
                        if [[ $err == 255 ]]; then
                            cat /tmp/basestrap.log
                            read -n1 -s
                        fi
                    fi
                 ;;
            "5") install_bootloader
                 ;;
            *) loopmenu=0
                return 0
                 ;;
        esac
    done
}

# Base Configuration
config_base_menu() {
    local PARENT="$FUNCNAME"
    declare -i loopmenu=1
    while ((loopmenu)); do
        ssubmenu 8
        DIALOG " $_ConfBseMenuTitle " --default-item ${HIGHLIGHT_SSUB} --menu "\n$_ConfBseBody\n " 0 0 8 \
          "1" "$_ConfBseFstab" \
          "2" "$_ConfBseHost" \
          "3" "$_ConfBseSysLoc" \
          "4" "$_PrepKBLayout" \
          "5" "$_ConfBseTimeHC" \
          "6" "$_ConfUsrRoot" \
          "7" "$_ConfUsrNew" \
          "8" "$_Back" 2>${ANSWER}
        HIGHLIGHT_SSUB=$(cat ${ANSWER})

        case $(cat ${ANSWER}) in
            "1") generate_fstab
                ;;
            "2") set_hostname
                ;;
            "3") set_locale
                ;;
            "4") set_xkbmap
                ;;
            "5") set_timezone && set_hw_clock
                ;;
            "6") set_root_password
                ;;
            "7") create_new_user
                ;;
            *) loopmenu=0
                return 0
                ;;
        esac
    done
}

# Base Configuration
config_cli_base_menu() {
    local PARENT="$FUNCNAME"
    declare -i loopmenu=1
    while ((loopmenu)); do
        ssubmenu 7
        DIALOG " $_ConfBseMenuTitle " --default-item ${HIGHLIGHT_SSUB} --menu "\n$_ConfBseBody\n " 22 60 7 \
          "1" "$_ConfBseFstab" \
          "2" "$_ConfBseHost" \
          "3" "$_ConfBseSysLoc" \
          "4" "$_ConfBseTimeHC" \
          "5" "$_ConfUsrRoot" \
          "6" "$_ConfUsrNew" \
          "7" "$_Back" 2>${ANSWER}
        HIGHLIGHT_SSUB=$(cat ${ANSWER})

        case $(cat ${ANSWER}) in
            "1") generate_fstab
                ;;
            "2") set_hostname
                ;;
            "3") set_locale
                ;;
            "4") set_timezone && set_hw_clock
                ;;
            "5") set_root_password
                ;;
            "6") create_new_user
                ;;
            *) loopmenu=0
                return 0
                ;;
        esac
    done
}

install_drivers_menu() {
    local PARENT="$FUNCNAME"
    declare -i loopmenu=1
    while ((loopmenu)); do
        ssubmenu 3
        DIALOG " $_InstDrvTitle " --default-item ${HIGHLIGHT_SUB} --menu "\n " 0 0 3 \
          "1" "$_InstGrMenuDD|>" \
          "2" "$_InstNWDrv|>" \
          "3" "$_Back" 2>${ANSWER}
        HIGHLIGHT_SSUB=$(cat ${ANSWER})

        case $(cat ${ANSWER}) in
            "1") install_graphics_menu
                ;;
            "2") setup_network_drivers || DIALOG " $_InstBseTitle " --infobox "\n$_InstFail\n " 0 0
                ;;
            *) loopmenu=0
                return 0
                ;;
        esac
    done
}

install_graphics_menu() {
    DIALOG " $_InstGrMenuDD " --menu "\n " 0 0 4 \
      "1" "$_InstFree" \
      "2" "$_InstProp" \
      "3" "$_SelDDrv" \
      "4" "$_InstAllDrv" 2>${ANSWER} || return 0

    case $(cat ${ANSWER}) in
        "1") clear
            mhwd --pmcachedir "$cachepath" --pmroot $MOUNTPOINT -a pci free 0300 2>$ERR
            check_for_error "$_InstFree" $?
            touch /mnt/.video_installed
            ;;
        "2") clear
            mhwd --pmcachedir "$cachepath" --pmroot $MOUNTPOINT -a pci nonfree 0300 2>$ERR
            check_for_error "$_InstProp" $?
            touch /mnt/.video_installed
            ;;
        "3") setup_graphics_card
            ;;
        "4") install_all_drivers
            check_for_error "$_InstAllDrv" $?
            touch /mnt/.video_installed
            ;;
    esac
}

tweaks_menu() {
    local PARENT="$FUNCNAME"
    declare -i loopmenu=1
    while ((loopmenu)); do
        submenu 7
        DIALOG " $_TweaksMenuTitle " --default-item ${HIGHLIGHT_SUB} --menu "\n$_TweaksBody " 0 0 5 \
          "1" "$_AutologEnable" \
          "2" "$_HibrnEnable" \
          "3" "$_PerfMenu|>" \
          "4" "$_SecMenuTitle|>" \
          "5" "$_Back" 2>${ANSWER}
        HIGHLIGHT_SUB=$(cat ${ANSWER})

        case $(cat ${ANSWER}) in
            "1") enable_autologin
                 ;;
            "2") enable_hibernation
                 ;;
            "3") performance_menu
                 ;;
            "4") security_menu
                ;;
            *) loopmenu=0
                return 0
                 ;;
        esac
    done
}

performance_menu() {
    local PARENT="$FUNCNAME"
    declare -i loopmenu=1
    while ((loopmenu)); do
        submenu 3
        DIALOG " $_PerfMenu " --default-item ${HIGHLIGHT_SUB} --menu "\n$_PerfBody\n " 0 0 4 \
          "1" "$_SetSchd" \
          "2" "$_SetSwap" \
          "3" "Preload" \
          "4" "$_Back" 2>${ANSWER}
        HIGHLIGHT_SUB=$(cat ${ANSWER})

        case $(cat ${ANSWER}) in
            "1") set_schedulers
                 ;;
            "2") set_swappiness
                 ;;
            "3") preloader
                 ;;
            *) loopmenu=0
                return 0
                 ;;
        esac
    done
}

recovery_menu() {
    local PARENT="$FUNCNAME"
    declare -i loopmenu=1
    while ((loopmenu)); do
        submenu 3
        DIALOG " $_DataRecMenu " --default-item ${HIGHLIGHT_SUB} --menu "\n$_DataRecBody\n " 0 0 3 \
          "1" "Clonezilla" \
          "2" "Photorec" \
          "3" "$_Back" 2>${ANSWER}
        HIGHLIGHT_SUB=$(cat ${ANSWER})

        case $(cat ${ANSWER}) in
            "1") if which clonezilla &>/dev/null; then
                    clonezilla
                 else
                    pacman -S clonezilla && clonezilla
                 fi
                 ;;
            "2") if which photorec &>/dev/null; then
                    photorec
                 else
                    pacman -S photorec && photorec
                 fi
                 ;;
            *) loopmenu=0
                return 0
                 ;;
        esac
    done
}

logs_menu() {
    local PARENT="$FUNCNAME"
    declare -i loopmenu=1
    while ((loopmenu)); do
        submenu 3
        DIALOG " $_LogMenu " --default-item ${HIGHLIGHT_SUB} --menu "\n$_LogBody\n " 0 0 5 \
          "1" "Dmesg" \
          "2" "Pacman log" \
          "3" "Xorg log" \
          "4" "Journalctl" \
          "5" "$_Back" 2>${ANSWER}
        HIGHLIGHT_SUB=$(cat ${ANSWER})

        case $(cat ${ANSWER}) in
            "1") arch_chroot "dmesg" | fzf --reverse --header="Exit by pressing esc" --prompt="Type to filter log entries > "
                 ;;
            "2") fzf --reverse --header="Exit by pressing esc" --prompt="Type to filter log entries > " < /mnt/var/log/pacman.log
                 ;;
            "3") fzf --reverse --header="Exit by pressing esc" --prompt="Type to filter log entries > " < /mnt/var/log/Xorg.0.log
                 ;;
            "4") arch_chroot "journalctl" | fzf --reverse --header="Exit by pressing esc" --prompt="Type to filter log entries > "
                 ;;
            *) loopmenu=0
                return 0
                 ;;
        esac
    done
}
