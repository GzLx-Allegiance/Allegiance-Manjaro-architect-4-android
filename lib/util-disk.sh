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

# Unmount partitions.
umount_partitions() {
    MOUNTED=""
    MOUNTED=$(mount | grep "${MOUNTPOINT}" | awk '{print $3}' | sort -r)
    swapoff -a

    for i in ${MOUNTED[@]}; do
        umount $i >/dev/null 2>$ERR
        check_for_error "unmount $i" $?
 #       local err=$(umount $i >/dev/null 2>$ERR)
 #       (( err !=0 )) && check_for_error "$FUNCNAME $i" $err
    done
}

# This function does not assume that the formatted device is the Root installation device as
# more than one device may be formatted. Root is set in the mount_partitions function.
select_device() {
    DEVICE=""
    devices_list=$(lsblk -lno NAME,SIZE,TYPE | grep 'disk' | awk '{print "/dev/" $1 " " $2}' | sort -u);

    for i in ${devices_list[@]}; do
        DEVICE="${DEVICE} ${i}"
    done

    DIALOG " $_DevSelTitle " --menu "\n$_DevSelBody\n " 20 60 4 ${DEVICE} 2>${ANSWER} || return 1
    DEVICE=$(cat ${ANSWER})
}

create_partitions() {
    # Partitioning Menu
    DIALOG " $_PrepPartDisk " --menu "\n$_PartToolBody\n " 0 0 7 \
      "$_PartOptWipe" "BIOS & UEFI" \
      "$_PartOptAuto" "BIOS & UEFI" \
      "cfdisk" "BIOS" \
      "cgdisk" "UEFI" \
      "fdisk"  "BIOS & UEFI" \
      "gdisk"  "UEFI" \
      "parted" "BIOS & UEFI" 2>${ANSWER} || return 0

    clear
    # If something selected
    if [[ $(cat ${ANSWER}) != "" ]]; then
        if ([[ $(cat ${ANSWER}) != "$_PartOptWipe" ]] && [[ $(cat ${ANSWER}) != "$_PartOptAuto" ]]); then
            $(cat ${ANSWER}) ${DEVICE}
        else
            [[ $(cat ${ANSWER}) == "$_PartOptWipe" ]] && secure_wipe && create_partitions
            [[ $(cat ${ANSWER}) == "$_PartOptAuto" ]] && auto_partition
        fi
    fi
}

# Securely destroy all data on a given device.
secure_wipe() {
    # Warn the user. If they proceed, wipe the selected device.
    DIALOG " $_PartOptWipe " --yesno "\n$_AutoPartWipeBody1 ${DEVICE} $_AutoPartWipeBody2\n " 0 0
    if [[ $? -eq 0 ]]; then
        # Install wipe where not already installed. Much faster than dd
        inst_needed wipe

        wipe -Ifre ${DEVICE} 2>$ERR
        check_for_error "wipe ${DEVICE}" $?

        # Alternate dd command - requires pv to be installed
        #dd if=/dev/zero | pv | dd of=${DEVICE} iflag=nocache oflag=direct bs=4096 2>$ERR
    fi
}

# BIOS and UEFI
auto_partition() {
    # Provide warning to user
    DIALOG " $_PrepPartDisk " --yesno "\n$_AutoPartBody1 $DEVICE $_AutoPartBody2 $_AutoPartBody3\n " 0 0

    if [[ $? -eq 0 ]]; then
        # Find existing partitions (if any) to remove
        parted -s ${DEVICE} print | awk '/^ / {print $1}' > /tmp/.del_parts

        for del_part in $(tac /tmp/.del_parts); do
            parted -s ${DEVICE} rm ${del_part} 2>$ERR
            check_for_error "rm ${del_part} on ${DEVICE}" $?
        done

        # Identify the partition table
        part_table=$(parted -s ${DEVICE} print | grep -i 'partition table' | awk '{print $3}' >/dev/null 2>&1)
        check_for_error "${DEVICE} is $part_table"

        # Create partition table if one does not already exist
        if [[ $SYSTEM == "BIOS" ]] && [[ $part_table != "msdos" ]] ; then 
            parted -s ${DEVICE} mklabel msdos 2>$ERR
            check_for_error "${DEVICE} mklabel msdos" $?
        fi
        if [[ $SYSTEM == "UEFI" ]] && [[ $part_table != "gpt" ]] ; then 
            parted -s ${DEVICE} mklabel gpt 2>$ERR
            check_for_error "${DEVICE} mklabel gpt" $?
        fi

        # Create partitions (same basic partitioning scheme for BIOS and UEFI)
        if [[ $SYSTEM == "BIOS" ]]; then
            parted -s ${DEVICE} mkpart primary ext3 1MiB 513MiB 2>$ERR
            check_for_error "create ext3 513MiB on ${DEVICE}" $?
        else
            parted -s ${DEVICE} mkpart ESP fat32 1MiB 513MiB 2>$ERR
            check_for_error "create ESP on ${DEVICE}" $?
        fi

        parted -s ${DEVICE} set 1 boot on 2>$ERR
        check_for_error "set boot flag for ${DEVICE}" $?
        parted -s ${DEVICE} mkpart primary ext3 513MiB 100% 2>$ERR
        check_for_error "create ext3 100% on ${DEVICE}" $?

        # Show created partitions
        lsblk ${DEVICE} -o NAME,TYPE,FSTYPE,SIZE > /tmp/.devlist
        DIALOG "" --textbox /tmp/.devlist 0 0
    fi
}
    
# Finds all available partitions according to type(s) specified and generates a list
# of them. This also includes partitions on different devices.
find_partitions() {
    PARTITIONS=""
    NUMBER_PARTITIONS=0
    # get the list of partitions and also include the zvols since it is common to mount filesystems directly on them.  It should be safe to include them here since they present as block devices.
    partition_list=$(lsblk -lno NAME,SIZE,TYPE | grep $INCLUDE_PART | sed 's/part$/\/dev\//g' | sed 's/lvm$\|crypt$/\/dev\/mapper\//g' | \
    awk '{print $3$1 " " $2}' | awk '!/mapper/{a[++i]=$0;next}1;END{while(x<length(a))print a[++x]}' ; zfs list -Ht volume -o name,volsize 2>/dev/null | awk '{printf "/dev/zvol/%s %s\n", $1, $2}')

    # create a raid partition list
    old_ifs="$IFS"
    IFS=$'\n'
    raid_partitions=($(lsblk -lno NAME,SIZE,TYPE | grep raid | awk '{print $1,$2}' | uniq))
    IFS="$old_ifs"

    # add raid partitions to partition_list
    for i in "${raid_partitions[@]}"
    do
        partition_list="${partition_list} /dev/md/${i}"
    done
    
    for i in ${partition_list}; do
        PARTITIONS="${PARTITIONS} ${i}"
        NUMBER_PARTITIONS=$(( NUMBER_PARTITIONS + 1 ))
    done

    # Double-partitions will be counted due to counting sizes, so fix
    NUMBER_PARTITIONS=$(( NUMBER_PARTITIONS / 2 ))

    check_for_error "--------- [lsblk] ------------"
    local parts=($PARTITIONS)
    for i in ${!parts[@]}; do
        (( $i % 2 == 0 )) || continue
        local j=$((i+1))
        check_for_error "${parts[i]} ${parts[j]}"
    done    

    #for test delete /dev:sda8
    #delete_partition_in_list "/dev/sda8"

    # Deal with partitioning schemes appropriate to mounting, lvm, and/or luks.
    case $INCLUDE_PART in
        'part\|lvm\|crypt')
            # Deal with incorrect partitioning for main mounting function
            if ([[ $SYSTEM == "UEFI" ]] && [[ $NUMBER_PARTITIONS -lt 2 ]]) || ([[ $SYSTEM == "BIOS" ]] && [[ $NUMBER_PARTITIONS -eq 0 ]]); then
                DIALOG " $_ErrTitle " --msgbox "\n$_PartErrBody\n " 0 0
                create_partitions
            fi
            ;;
        'part\|crypt')
            # Ensure there is at least one partition for LVM
            if [[ $NUMBER_PARTITIONS -eq 0 ]]; then
                DIALOG " $_ErrTitle " --msgbox "\n$_LvmPartErrBody\n " 0 0
                create_partitions
            fi
            ;;
        'part\|lvm') # Ensure there are at least two partitions for LUKS
            if [[ $NUMBER_PARTITIONS -lt 2 ]]; then
                DIALOG " $_ErrTitle " --msgbox "\n$_LuksPartErrBody\n " 0 0
                create_partitions
            fi
            ;;
    esac    
}

## List partitions to be hidden from the mounting menu
list_mounted() {
    lsblk -l | awk '$7 ~ /mnt/ {print $1}' > /tmp/.mounted
    check_for_error "already mounted: $(cat /tmp/.mounted)"
    echo /dev/* /dev/mapper/* | xargs -n1 2>/dev/null | grep -f /tmp/.mounted
}

list_containing_crypt() {
    blkid | awk '/TYPE="crypto_LUKS"/{print $1}' | sed 's/.$//'
}

list_non_crypt() {
    blkid | awk '!/TYPE="crypto_LUKS"/{print $1}' | sed 's/.$//'
}

# delete partition in list $PARTITIONS
# param: partition to delete
delete_partition_in_list() {
    [ -z "$1" ] && return 127
    local parts=($PARTITIONS)
    for i in ${!parts[@]}; do
        (( $i % 2 == 0 )) || continue
        if [[ "${parts[i]}" = "$1" ]]; then
            local j=$((i+1))
            unset parts[$j]
            unset parts[$i]
            check_for_error "in partitions delete item $1 no: $i / $j"
            PARTITIONS="${parts[*]}"
            check_for_error "partitions: $PARTITIONS"
            NUMBER_PARTITIONS=$(( "${#parts[*]}" / 2 ))
            return 0
        fi
    done
    return 0
}

# Revised to deal with partion sizes now being displayed to the user
confirm_mount() {
    if [[ $(mount | grep $1) ]]; then
        DIALOG " $_MntStatusTitle " --infobox "\n$_MntStatusSucc\n " 0 0
        sleep 2
        PARTITIONS=$(echo $PARTITIONS | sed "s~${PARTITION} [0-9]*[G-M]~~" | sed "s~${PARTITION} [0-9]*\.[0-9]*[G-M]~~" | sed s~${PARTITION}$' -'~~)
        NUMBER_PARTITIONS=$(( NUMBER_PARTITIONS - 1 ))
    else
        DIALOG " $_MntStatusTitle " --infobox "\n$_MntStatusFail\n " 0 0
        sleep 2
        return 1
    fi
}

# Set static list of filesystems rather than on-the-fly. Partially as most require additional flags, and
# partially because some don't seem to be viable.
# Set static list of filesystems rather than on-the-fly.
select_filesystem() {
    # prep variables
    fs_opts=""
    CHK_NUM=0

    # zfs legacy filesystems can't be formatted, always have a zfs filesystem and store their mount options in metadata
    [[ $(zfs_list_datasets legacy | grep "^${PARTITION}$") ]] && return

    DIALOG " $_FSTitle " --menu "\n$_FSBody\n " 0 0 10 \
      "$_FSSkip" "-" \
      "btrfs" "mkfs.btrfs -f" \
      "ext3" "mkfs.ext3 -q" \
      "ext4" "mkfs.ext4 -q" \
      "jfs" "mkfs.jfs -q" \
      "nilfs2" "mkfs.nilfs2 -fq" \
      "ntfs" "mkfs.ntfs -q" \
      "reiserfs" "mkfs.reiserfs -q" \
      "vfat" "mkfs.vfat -F32" \
      "xfs" "mkfs.xfs -f" 2>${ANSWER} || return 1
        
    case $(cat ${ANSWER}) in
        "$_FSSkip") FILESYSTEM="$_FSSkip"
            ;;
        "btrfs") FILESYSTEM="mkfs.btrfs -f"
            CHK_NUM=16
            fs_opts="autodefrag compress=zlib compress=lzo compress=zstd compress=no compress-force=zlib compress-force=lzo compress-force=zstd discard \
            noacl noatime nodatasum nospace_cache recovery skip_balance space_cache nossd ssd ssd_spread commit=120"
            modprobe btrfs
            ;;
        "ext2") FILESYSTEM="mkfs.ext2 -q"
            ;;
        "ext3") FILESYSTEM="mkfs.ext3 -q"
            ;;
        "ext4") FILESYSTEM="mkfs.ext4 -q"
            CHK_NUM=8
            fs_opts="data=journal data=writeback dealloc discard noacl noatime nobarrier nodelalloc"
            ;;
        "f2fs") FILESYSTEM="mkfs.f2fs -q"
            fs_opts="data_flush disable_roll_forward disable_ext_identify discard fastboot flush_merge \
            inline_xattr inline_data inline_dentry no_heap noacl nobarrier noextent_cache noinline_data norecovery"
            CHK_NUM=16
            modprobe f2fs
            ;;
        "jfs") FILESYSTEM="mkfs.jfs -q"
            CHK_NUM=4
            fs_opts="discard errors=continue errors=panic nointegrity"
            ;;
        "nilfs2") FILESYSTEM="mkfs.nilfs2 -fq"
            CHK_NUM=7
            fs_opts="discard nobarrier errors=continue errors=panic order=relaxed order=strict norecovery"
            ;;
        "ntfs") FILESYSTEM="mkfs.ntfs -q"
            ;;
        "reiserfs") FILESYSTEM="mkfs.reiserfs -q"
            CHK_NUM=5
            fs_opts="acl nolog notail replayonly user_xattr"
            ;;
        "vfat") FILESYSTEM="mkfs.vfat -F32"
            ;;
        "xfs") FILESYSTEM="mkfs.xfs -f"
            CHK_NUM=9
            fs_opts="discard filestreams ikeep largeio noalign nobarrier norecovery noquota wsync"
            ;;
        *)  return 1
            ;;
    esac

    # Warn about formatting!
    if [[ $FILESYSTEM != $_FSSkip ]]; then
        DIALOG " $_FSTitle " --yesno "\n$_FSMount $FILESYSTEM\n\n! $_FSWarn1 $PARTITION $_FSWarn2 !\n " 0 0
        if (( $? != 1 )); then
            ${FILESYSTEM} ${PARTITION} >/dev/null 2>$ERR
            check_for_error "mount ${PARTITION} as ${FILESYSTEM}." $? || return 1
            ini "mount.${PARTITION}" $(echo "${FILESYSTEM:5}|cut -d' ' -f1")
        fi
    fi
}

# This subfunction allows for special mounting options to be applied for relevant fs's.
# Seperate subfunction for neatness.
mount_opts() {
    FS_OPTS=""

    for i in ${fs_opts}; do
        FS_OPTS="${FS_OPTS} ${i} - off"
    done
    echo ${FS_OPTS} > /tmp/.fs_options

    format_name=$(echo ${PARTITION} | rev | cut -d/ -f1 | rev)
    format_device=$(lsblk -i | tac | sed -r 's/^[^[:alnum:]]+//' | sed -n -e "/$format_name/,/disk/p" | awk '/disk/ {print $1}')   
    
    if [[ "$(cat /sys/block/${format_device}/queue/rotational)" == 1 ]]; then
        sed -i 's/autodefrag - off/autodefrag - on/' /tmp/.fs_options
        sed -i 's/compress=zlip - off/compress=zlip - on/' /tmp/.fs_options
        sed -i 's/nossd - off/nossd - on/' /tmp/.fs_options    
    else
        sed -i 's/compress=lzo - off/compress=lzo - on/' /tmp/.fs_options
        sed -i 's/ space_cache - off/ space_cache - on/' /tmp/.fs_options
        sed -i 's/commit=120 - off/commit=120 - on/' /tmp/.fs_options
        sed -i 's/ ssd - off/ ssd - on/' /tmp/.fs_options
        
    fi
        sed -i 's/noatime - off/noatime - on/' /tmp/.fs_options
        
    FS_OPTS=$(cat /tmp/.fs_options)

    DIALOG " $(echo $FILESYSTEM | sed "s/.*\.//g;s/-.*//g") " --checklist "\n$_btrfsMntBody\n " 0 0 \
      $CHK_NUM $FS_OPTS 2>${MOUNT_OPTS}

    # Now clean up the file
    sed -i 's/ /,/g' ${MOUNT_OPTS}
    sed -i '$s/,$//' ${MOUNT_OPTS}

    # If mount options selected, confirm choice
    if [[ $(cat ${MOUNT_OPTS}) != "" ]]; then
        DIALOG " $_MntStatusTitle " --yesno "\n${_btrfsMntConfBody}$(cat ${MOUNT_OPTS})\n " 10 75
        [[ $? -eq 1 ]] && echo "" > ${MOUNT_OPTS}
    fi
}

mount_current_partition() {
    # Make the mount directory
    mkdir -p ${MOUNTPOINT}${MOUNT} 2>$ERR
    check_for_error "create mountpoint ${MOUNTPOINT}${MOUNT}" "$?"

    echo "" > ${MOUNT_OPTS}
    # Get mounting options for appropriate filesystems
    [[ $fs_opts != "" ]] && mount_opts

    # Check for zfs, use special mounting options if selected, else standard mount
    if [[ $(zfs_list_datasets legacy | grep "^${PARTITION}$") ]]; then
        check_for_error "mount ${PARTITION}"
        mount -t zfs ${PARTITION} ${MOUNTPOINT}${MOUNT} 2>>$LOGFILE
    elif [[ $(cat ${MOUNT_OPTS}) != "" ]]; then
        check_for_error "mount ${PARTITION} $(cat ${MOUNT_OPTS})"
        mount -o $(cat ${MOUNT_OPTS}) ${PARTITION} ${MOUNTPOINT}${MOUNT} 2>>$LOGFILE
    else
        check_for_error "mount ${PARTITION}"
        mount ${PARTITION} ${MOUNTPOINT}${MOUNT} 2>>$LOGFILE
    fi
    confirm_mount ${MOUNTPOINT}${MOUNT}

    # Identify if mounted partition is type "crypt" (LUKS on LVM, or LUKS alone)
    if [[ $(lsblk -lno TYPE ${PARTITION} | grep "crypt") != "" ]]; then
        # cryptname for bootloader configuration either way
        LUKS=1
        LUKS_NAME=$(echo ${PARTITION} | sed "s~^/dev/mapper/~~g")

        # Check if LUKS on LVM (parent = lvm /dev/mapper/...)
        cryptparts=$(lsblk -lno NAME,FSTYPE,TYPE | grep "lvm" | grep -i "crypto_luks" | uniq | awk '{print "/dev/mapper/"$1}')
        for i in ${cryptparts}; do
            if [[ $(lsblk -lno NAME ${i} | grep $LUKS_NAME) != "" ]]; then
                LUKS_DEV="$LUKS_DEV cryptdevice=${i}:$LUKS_NAME"
                LVM=1
                return 0;
            fi
        done

        # Check if LVM on LUKS
        cryptparts=$(lsblk -lno NAME,FSTYPE,TYPE | grep " crypt$" | grep -i "LVM2_member" | uniq | awk '{print "/dev/mapper/"$1}')
        for i in ${cryptparts}; do
            if [[ $(lsblk -lno NAME ${i} | grep $LUKS_NAME) != "" ]]; then
                LUKS_DEV="$LUKS_DEV cryptdevice=${i}:$LUKS_NAME"
                LVM=1
                return 0;
            fi
        done

        # Check if LUKS alone (parent = part /dev/...)
        cryptparts=$(lsblk -lno NAME,FSTYPE,TYPE | grep "part" | grep -i "crypto_luks" | uniq | awk '{print "/dev/"$1}')
        for i in ${cryptparts}; do
            if [[ $(lsblk -lno NAME ${i} | grep $LUKS_NAME) != "" ]]; then
                LUKS_UUID=$(lsblk -lno UUID,TYPE,FSTYPE ${i} | grep "part" | grep -i "crypto_luks" | awk '{print $1}')
                LUKS_DEV="$LUKS_DEV cryptdevice=UUID=$LUKS_UUID:$LUKS_NAME"
                return 0;
            fi
        done

        # If LVM logical volume....
    elif [[ $(lsblk -lno TYPE ${PARTITION} | grep "lvm") != "" ]]; then
        LVM=1

        # First get crypt name (code above would get lv name)
        cryptparts=$(lsblk -lno NAME,TYPE,FSTYPE | grep "crypt" | grep -i "lvm2_member" | uniq | awk '{print "/dev/mapper/"$1}')
        for i in ${cryptparts}; do
            if [[ $(lsblk -lno NAME ${i} | grep $(echo $PARTITION | sed "s~^/dev/mapper/~~g")) != "" ]]; then
                LUKS_NAME=$(echo ${i} | sed s~/dev/mapper/~~g)
                return 0;
            fi
        done

        # Now get the device (/dev/...) for the crypt name
        cryptparts=$(lsblk -lno NAME,FSTYPE,TYPE | grep "part" | grep -i "crypto_luks" | uniq | awk '{print "/dev/"$1}')
        for i in ${cryptparts}; do
            if [[ $(lsblk -lno NAME ${i} | grep $LUKS_NAME) != "" ]]; then
                # Create UUID for comparison
                LUKS_UUID=$(lsblk -lno UUID,TYPE,FSTYPE ${i} | grep "part" | grep -i "crypto_luks" | awk '{print $1}')

                # Check if not already added as a LUKS DEVICE (i.e. multiple LVs on one crypt). If not, add.
                if [[ $(echo $LUKS_DEV | grep $LUKS_UUID) == "" ]]; then
                    LUKS_DEV="$LUKS_DEV cryptdevice=UUID=$LUKS_UUID:$LUKS_NAME"
                    LUKS=1
                fi

                return 0;
            fi
        done
    fi
}

make_swap() {
    # Ask user to select partition or create swapfile if swapfiles are valid for the root filesystem
    if [[ $(findmnt -ln -o FSTYPE ${MOUNTPOINT}) == "zfs" || $(findmnt -ln -o FSTYPE ${MOUNTPOINT}) == "btrfs" ]]; then
        DIALOG " $_PrepMntPart " --menu "\n$_SelSwpBody\n " 0 0 12 "$_SelSwpNone" $"-" ${PARTITIONS} 2>${ANSWER} || return 0
    else
        DIALOG " $_PrepMntPart " --menu "\n$_SelSwpBody\n " 0 0 12 "$_SelSwpNone" $"-" "$_SelSwpFile" $"-" ${PARTITIONS} 2>${ANSWER} || return 0
    fi

    if [[ $(cat ${ANSWER}) != "$_SelSwpNone" ]]; then
        PARTITION=$(cat ${ANSWER})

        if [[ $PARTITION == "$_SelSwpFile" ]]; then
            total_memory=$(grep MemTotal /proc/meminfo | awk '{print $2/1024}' | sed 's/\..*//')
            DIALOG " $_SelSwpFile " --inputbox "\nM = MB, G = GB\n " 9 30 "${total_memory}M" 2>${ANSWER} || return 0
            m_or_g=$(cat ${ANSWER})

            while [[ $(echo ${m_or_g: -1} | grep "M\|G") == "" ]]; do
                DIALOG " $_SelSwpFile " --msgbox "\n$_SelSwpFile $_ErrTitle: M = MB, G = GB\n " 0 0
                DIALOG " $_SelSwpFile " --inputbox "\nM = MB, G = GB\n " 9 30 "${total_memory}M" 2>${ANSWER} || return 0
                m_or_g=$(cat ${ANSWER})
            done

            fallocate -l ${m_or_g} ${MOUNTPOINT}/swapfile 2>$ERR
            check_for_error "Swapfile fallocate" "$?"
            chmod 600 ${MOUNTPOINT}/swapfile 2>$ERR
            check_for_error "Swapfile chmod" "$?"
            mkswap ${MOUNTPOINT}/swapfile 2>$ERR
            check_for_error "Swapfile mkswap" "$?"
            swapon ${MOUNTPOINT}/swapfile 2>$ERR
            check_for_error "Swapfile swapon" "$?"

        else # Swap Partition
            # Warn user if creating a new swap
            if [[ $(lsblk -o FSTYPE  ${PARTITION} | grep -i "swap") != "swap" ]]; then
                DIALOG " $_PrepMntPart " --yesno "\nmkswap ${PARTITION}\n " 0 0
                if [[ $? -eq 0 ]]; then
                    mkswap ${PARTITION} >/dev/null 2>$ERR
                    check_for_error "Swap partition: mkswap" "$?"
                else
                    return 0
                fi
            fi
            # Whether existing to newly created, activate swap
            swapon  ${PARTITION} >/dev/null 2>$ERR
            check_for_error "Swap partition: swapon" "$?"
            # Since a partition was used, remove that partition from the list
            PARTITIONS=$(echo $PARTITIONS | sed "s~${PARTITION} [0-9]*[G-M]~~" | sed "s~${PARTITION} [0-9]*\.[0-9]*[G-M]~~" | sed s~${PARTITION}$' -'~~)
            NUMBER_PARTITIONS=$(( NUMBER_PARTITIONS - 1 ))
        fi
    fi
    ini mount.swap "${PARTITION}"
}

raid_level_menu() {
    declare -i loopmenu=1
    while ((loopmenu)); do
        RAID_OPT=""
        DIALOG "RAID" --menu "\n$_RAIDLevelTitle\n" 20 75 6 \
	    "0" "$_RAIDLevel0" \
        "1" "$_RAIDLevel1" \
        "5" "$_RAIDLevel5" \
        "6" "$_RAIDLevel6" \
        "10" "$_RAIDLevel10" \
        "$_Back" "-" 2>${ANSWER}

        case $(cat ${ANSWER}) in
            "0") raid_array_menu 0
                ;;
            "1") raid_array_menu 1 
                ;;
            "5") raid_array_menu 5
                ;; 
            "6") raid_array_menu 6
                ;;
	        "10") raid_array_menu 10
		        ;;
            *) loopmenu=0
               return 0
                ;;
        esac
    done
}

raid_create() {

    RAID_DEVICES=${1}
    RAID_DEVICE_NUMBER=$(echo ${1} | wc -w)
    RAID_LEVEL=${2}
    RAID_DEVICE_NAME=${3}

    # creates the array
    mdadm --create --level=${RAID_LEVEL} --metadata=1.2 --raid-devices=${RAID_DEVICE_NUMBER} /dev/md/${RAID_DEVICE_NAME} ${RAID_DEVICES}  
        
    # array is disassembled and reassembled to prevent the array from being named /dev/md/md127
    # the check of /etc/mdadm.conf is preformed to prevent the user from adding duplicate entries
    if [[ $(cat /etc/mdadm.conf | grep "/dev/md/${RAID_DEVICE_NAME}" | wc -l) == 0 ]]; then
        mdadm --detail --scan | grep -e "/dev/md/${RAID_DEVICE_NAME}" -e "/dev/md/md127" >> /etc/mdadm.conf
        mdadm --stop /dev/md/${RAID_DEVICE_NAME}
        mdadm --assemble --scan
    fi
    
    DIALOG "$__ArrayCreatedTitle" --msgbox "\n$_ArrayCreatedDescription\n\nmdadm --create --level=${RAID_LEVEL} --metadata=1.2 --raid-devices=${RAID_DEVICE_NUMBER} /dev/md/${RAID_DEVICE_NAME} ${RAID_DEVICES}\n" 0 0

}

raid_get_array_name() {

    DIALOG "$_DeviceNameTitle" --inputbox "\n$_DeviceNameDescription\n\n$_DeviceNamePrefixWarning\n" 0 0 2>${ANSWER}

    raid_device_name=$(cat ${ANSWER})
    
    if [[ ${raid_device_name} != "" ]]; then
        raid_create "${1}" ${2} ${raid_device_name}
    fi
    
}

raid_array_menu() {

    # find raid partitions.
    INCLUDE_PART='part\|crypt'
    umount_partitions
    find_partitions
    
    # Amend partition(s) found for use in check list
    PARTITIONS=$(echo $PARTITIONS | sed 's/M\|G\|T/& off/g')
    RAID_LEVEL=${1}
    
    # select partitions for the array
    echo "" > $ANSWER
    while [[ $(cat ${ANSWER}) == "" ]]; do
        DIALOG "$_PartitionSelectTitle" --checklist "\n$__PartitionSelectDescription\n\n$_UseSpaceBar\n " 0 0 12 ${PARTITIONS} 2> ${ANSWER} 
    done
    
    ANSWERS=$(cat ${ANSWER})

    raid_get_array_name "${ANSWERS[@]}" ${RAID_LEVEL}
    
}

luks_menu() {
    declare -i loopmenu=1
    while ((loopmenu)); do
        LUKS_OPT=""
        DIALOG " $_PrepLUKS " --menu "\n$_LuksMenuBody\n$_LuksMenuBody2\n$_LuksMenuBody3\n " 0 0 0 \
          "$_LuksOpen" "cryptsetup open --type luks" \
          "$_LuksEncrypt" "cryptsetup -q luksFormat" \
          "$_LuksEncryptAdv" "cryptsetup -q -s -c luksFormat" \
          "Express LUKS" "cryptsetup -q -s --pbkdf-force-iterations 200000 -c luksFormat" \
          "$_Back" "-" 2>${ANSWER}

        case $(cat ${ANSWER}) in
            "$_LuksOpen") luks_open
                ;;
            "$_LuksEncrypt") luks_setup && luks_default && luks_show
                ;;
            "$_LuksEncryptAdv") luks_setup && luks_key_define && luks_show
                ;;
            "Express LUKS") luks_setup && luks_express && luks_show
                ;;
            *) loopmenu=0
               return 0
                ;;
        esac
    done
}

luks_open() {
    LUKS_ROOT_NAME=""
    INCLUDE_PART='part\|crypt\|lvm'
    umount_partitions
    find_partitions
    # Filter out partitions that don't contain crypt device
    list_non_crypt > /tmp/.ignore_part
 
    for part in $(cat /tmp/.ignore_part); do
        delete_partition_in_list $part
    done

    # stop if no encrypted partition found
    if [[ $PARTITIONS == "" ]]; then
        DIALOG " $_ErrTitle " --msgbox "\n$_LuksErr\n " 0 0
        return 1
    fi

    # Select encrypted partition to open
    DIALOG " $_LuksOpen " --menu "\n$_LuksMenuBody\n " 0 0 12 ${PARTITIONS} 2>${ANSWER} || return 0
    PARTITION=$(cat ${ANSWER})

    # Enter name of the Luks partition and get password to open it
    DIALOG " $_LuksOpen " --inputbox "\n$_LuksOpenBody\n " 0 0 "cryptroot" 2>${ANSWER} || return 0
    LUKS_ROOT_NAME=$(cat ${ANSWER})
    DIALOG " $_PrepLUKS " --clear --insecure --passwordbox "\n$_LuksPassBody\n " 0 0 2> ${ANSWER} || return 0
    PASSWD=$(cat ${ANSWER})

    # Try to open the luks partition with the credentials given. If successful show this, otherwise
    # show the error
    DIALOG " $_LuksOpen " --infobox "\n$_PlsWaitBody\n " 0 0
    echo $PASSWD | cryptsetup open --type luks ${PARTITION} ${LUKS_ROOT_NAME} 2>$ERR
    check_for_error "luks pwd ${PARTITION} ${LUKS_ROOT_NAME}" "$?"

    echo "" > /tmp/.devlist
    lsblk -o NAME,TYPE,FSTYPE,SIZE,MOUNTPOINT ${PARTITION} | grep "crypt\|NAME\|MODEL\|TYPE\|FSTYPE\|SIZE" >> /tmp/.devlist
    DIALOG " $_DevShowOpt " --textbox /tmp/.devlist 0 0
}

luks_password() {
    luks_get_password
    while [[ $PASSWD != $PASSWD2 ]]; do
        DIALOG " $_ErrTitle " --msgbox "\n$_PassErrBody\n " 0 0
        luks_get_password
    done
}

luks_get_password() {
    DIALOG " $_PrepLUKS " --clear --insecure --passwordbox "\n$_LuksPassBody\n " 0 0 2> ${ANSWER} || return 0
    PASSWD=$(cat ${ANSWER})
    DIALOG " $_PrepLUKS " --clear --insecure --passwordbox "\n$_PassReEntBody\n " 0 0 2> ${ANSWER} || return 0
    PASSWD2=$(cat ${ANSWER})
}

luks_setup() {
    modprobe -a dm-mod dm_crypt
    INCLUDE_PART='part\|lvm'
    umount_partitions
    find_partitions
    # Select partition to encrypt
    DIALOG " $_LuksEncrypt " --menu "\n$_LuksCreateBody\n " 0 0 12 ${PARTITIONS} 2>${ANSWER} || return 1
    PARTITION=$(cat ${ANSWER})

    # Enter name of the Luks partition and get password to create it
    DIALOG " $_LuksEncrypt " --inputbox "\n$_LuksOpenBody\n " 0 0 "cryptroot" 2>${ANSWER} || return 1
    LUKS_ROOT_NAME=$(cat ${ANSWER})
    luks_password
}

luks_default() {
    # Encrypt selected partition or LV with credentials given
    DIALOG " $_LuksEncrypt " --infobox "\n$_PlsWaitBody\n " 0 0
    sleep 2
    echo $PASSWD | cryptsetup -q --type luks1 luksFormat ${PARTITION} 2>$ERR
    check_for_error "luksFormat ${PARTITION}" $?

    # Now open the encrypted partition or LV
    echo $PASSWD | cryptsetup open ${PARTITION} ${LUKS_ROOT_NAME} 2>$ERR
    check_for_error "open ${PARTITION} ${LUKS_ROOT_NAME}" $?
}

luks_express() {
    # Encrypt selected partition or LV with credentials given
    DIALOG " $_LuksEncrypt " --infobox "\n$_PlsWaitBody\n " 0 0
    sleep 2
    echo $PASSWD | cryptsetup -q --pbkdf-force-iterations 200000 --type luks1 luksFormat ${PARTITION} 2>$ERR
    check_for_error "luksFormat ${PARTITION}" $?

    # Now open the encrypted partition or LV
    echo $PASSWD | cryptsetup open ${PARTITION} ${LUKS_ROOT_NAME} 2>$ERR
    check_for_error "open ${PARTITION} ${LUKS_ROOT_NAME}" $?
}

luks_key_define() {
    DIALOG " $_PrepLUKS " --inputbox "\n$_LuksCipherKey\n " 0 0 "-s 512 -c aes-xts-plain64" 2>${ANSWER} || return 1

    # Encrypt selected partition or LV with credentials given
    DIALOG " $_LuksEncryptAdv " --infobox "\n$_PlsWaitBody\n " 0 0
    sleep 2

    echo $PASSWD | cryptsetup -q $(cat ${ANSWER}) luksFormat ${PARTITION} 2>$ERR
    check_for_error "encrypt ${PARTITION}" "$?"

    # Now open the encrypted partition or LV
    echo $PASSWD | cryptsetup open ${PARTITION} ${LUKS_ROOT_NAME} 2>$ERR
    check_for_error "open ${PARTITION} ${LUKS_ROOT_NAME}" "$?"
}

luks_show() {
    printf "\n${_LuksEncruptSucc}\n\n" > /tmp/.devlist
    lsblk -o NAME,TYPE,FSTYPE,SIZE ${PARTITION} | grep "part\|crypt\|NAME\|TYPE\|FSTYPE\|SIZE" >> /tmp/.devlist
    DIALOG " $_LuksEncrypt " --textbox /tmp/.devlist 0 0
}

lvm_menu() {
    declare -i loopmenu=1
    while ((loopmenu)); do
        DIALOG " $_PrepLVM $_PrepLVM2 " --infobox "\n$_PlsWaitBody\n " 0 0
        sleep 1
        lvm_detect

        DIALOG " $_PrepLVM $_PrepLVM2 " --menu "\n$_LvmMenu\n " 22 60 4 \
          "$_LvmCreateVG" "vgcreate -f, lvcreate -L -n" \
          "$_LvmDelVG" "vgremove -f" \
          "$_LvMDelAll" "lvrmeove, vgremove, pvremove -f" \
          "$_Back" "-" 2>${ANSWER}

        case $(cat ${ANSWER}) in
            "$_LvmCreateVG") lvm_create
               ;;
            "$_LvmDelVG") lvm_del_vg
               ;;
            "$_LvMDelAll") lvm_del_all
               ;;
            *) loopmenu=0
               return 0
               ;;
        esac
    done
}

lvm_detect() {
    LVM_PV=$(pvs -o pv_name --noheading 2>/dev/null)
    LVM_VG=$(vgs -o vg_name --noheading 2>/dev/null)
    LVM_LV=$(lvs -o vg_name,lv_name --noheading --separator - 2>/dev/null)

    if [[ $LVM_LV != "" ]] && [[ $LVM_VG != "" ]] && [[ $LVM_PV != "" ]]; then
        DIALOG " $_PrepLVM " --infobox "\n$_LvmDetBody\n " 0 0
        sleep 2
        modprobe dm-mod 2>$ERR
        check_for_error "modprobe dm-mod" "$?"
        vgscan >/dev/null 2>&1
        vgchange -ay >/dev/null 2>&1
    fi
}

# Create Volume Group and Logical Volumes
lvm_create() {
    # Find LVM appropriate partitions.
    INCLUDE_PART='part\|crypt'
    umount_partitions
    find_partitions
    # Amend partition(s) found for use in check list
    PARTITIONS=$(echo $PARTITIONS | sed 's/M\|G\|T/& off/g')

    # Name the Volume Group
    DIALOG " $_LvmCreateVG " --inputbox "\n$_LvmNameVgBody\n " 0 0 2>${ANSWER} || return 0
    LVM_VG=$(cat ${ANSWER})

    # Loop while the Volume Group name starts with a "/", is blank, has spaces, or is already being used
    while [[ ${LVM_VG:0:1} == "/" ]] || [[ ${#LVM_VG} -eq 0 ]] || [[ $LVM_VG =~ \ |\' ]] || [[ $(lsblk | grep ${LVM_VG}) != "" ]]; do
        DIALOG " $_ErrTitle " --msgbox "\n$_LvmNameVgErr\n " 0 0
        DIALOG " $_LvmCreateVG " --inputbox "\n$_LvmNameVgBody\n " 0 0 "" 2>${ANSWER} || return 0
        LVM_VG=$(cat ${ANSWER})
    done

    # Select the partition(s) for the Volume Group
    echo "" > $ANSWER
    while [[ $(cat ${ANSWER}) == "" ]]; do
        DIALOG " $_LvmCreateVG " --checklist "\n$_LvmPvSelBody\n\n$_UseSpaceBar\n " 0 0 12 ${PARTITIONS} 2>${ANSWER} || return 0
    done

    VG_PARTS=$(cat ${ANSWER})

    # Once all the partitions have been selected, show user. On confirmation, use it/them in 'vgcreate' command.
    # Also determine the size of the VG, to use for creating LVs for it.
    DIALOG " $_LvmCreateVG " --yesno "\n$_LvmPvConfBody1 [${LVM_VG}] $_LvmPvConfBody2\n${VG_PARTS}\n " 0 0

    if [[ $? -eq 0 ]]; then
        DIALOG " $_LvmCreateVG " --infobox "\n$_LvmPvActBody1 [${LVM_VG}].\n$_PlsWaitBody\n " 0 0
        sleep 1
        vgcreate -f ${LVM_VG} ${VG_PARTS} >/dev/null
        check_for_error "vgcreate -f ${LVM_VG} ${VG_PARTS}"

        # Once created, get size and size type for display and later number-crunching for lv creation
        VG_SIZE=$(vgdisplay $LVM_VG | awk '/VG Size/ {print $3}' | sed -e 's/<//' | sed 's/\..*//; s/\,.*//')
        VG_SIZE_TYPE=$(vgdisplay $LVM_VG | grep 'VG Size' | awk '{print $4}')

        # Convert the VG size into GB and MB. These variables are used to keep tabs on space available and remaining
        [[ ${VG_SIZE_TYPE:0:1} == "G" ]] && LVM_VG_MB=$(( VG_SIZE * 1000 )) || LVM_VG_MB=$VG_SIZE

        DIALOG " $_LvmCreateVG " --msgbox "\n$_LvmPvDoneBody1 [${LVM_VG}] (${VG_SIZE} ${VG_SIZE_TYPE}) $_LvmPvDoneBody2.\n " 0 0 || return 0
    fi

    #
    # Once VG created, create Logical Volumes
    #

    # Specify number of Logical volumes to create.
    DIALOG " $_LvmCreateVG " --inputbox "\n$_LvmLvNumBody1 [${LVM_VG}]. $_LvmLvNumBody2\n " 0 0 2>${ANSWER}

    # repeat if answer is not a number
    while [[ $(cat ${ANSWER}) != ?(-)+([0-9]) ]]; do
        DIALOG " $_ErrTitle " --inputbox "\n$_LvmLvNumBody1 [${LVM_VG}]. $_LvmLvNumBody2\n " 0 0 2>${ANSWER}
    done

    NUMBER_LOGICAL_VOLUMES=$(cat ${ANSWER})

    # Loop while the number of LVs is greater than 1. This is because the size of the last LV is automatic.
    while [[ $NUMBER_LOGICAL_VOLUMES -gt 1 ]]; do
        DIALOG " $_LvmCreateVG (LV:$NUMBER_LOGICAL_VOLUMES) " --inputbox "\n$_LvmLvNameBody1\n " 0 0 "lvol" 2>${ANSWER} || return 0
        LVM_LV_NAME=$(cat ${ANSWER})

        # Loop if preceeded with a "/", if nothing is entered, if there is a space, or if that name already exists.
        while [[ ${LVM_LV_NAME:0:1} == "/" ]] || [[ ${#LVM_LV_NAME} -eq 0 ]] || [[ ${LVM_LV_NAME} =~ \ |\' ]] || [[ $(lsblk | grep ${LVM_LV_NAME}) != "" ]]; do
            DIALOG " $_ErrTitle " --msgbox "\n$_LvmLvNameErrBody\n " 0 0
            DIALOG " $_LvmCreateVG (LV:$NUMBER_LOGICAL_VOLUMES) " --inputbox "\n$_LvmLvNameBody1\n " 0 0 "lvol" 2>${ANSWER} || return 0
            LVM_LV_NAME=$(cat ${ANSWER})
        done

        DIALOG " $_LvmCreateVG (LV:$NUMBER_LOGICAL_VOLUMES) " --inputbox \
          "\n[${LVM_VG}]: ${VG_SIZE}${VG_SIZE_TYPE} - (${LVM_VG_MB}MB $_LvmLvSizeBody1).\n\n$_LvmLvSizeBody2\n " 0 0 "" 2>${ANSWER} || return 0
        LVM_LV_SIZE=$(cat ${ANSWER})
        check_lv_size

        # Loop while an invalid value is entered.
        while [[ $LV_SIZE_INVALID -eq 1 ]]; do
            DIALOG " $_ErrTitle " --msgbox "\n$_LvmLvSizeErrBody\n " 0 0
            DIALOG " $_LvmCreateVG (LV:$NUMBER_LOGICAL_VOLUMES) " --inputbox \
              "\n[${LVM_VG}]: ${VG_SIZE}${VG_SIZE_TYPE} - (${LVM_VG_MB}MB $_LvmLvSizeBody1).\n\n$_LvmLvSizeBody2\n " 0 0 "" 2>${ANSWER} || return 0
            LVM_LV_SIZE=$(cat ${ANSWER})
            check_lv_size
        done

        # Create the LV
        lvcreate -L ${LVM_LV_SIZE} ${LVM_VG} -n ${LVM_LV_NAME} 2>$ERR
        check_for_error "lvcreate -L ${LVM_LV_SIZE} ${LVM_VG} -n ${LVM_LV_NAME}" "$?"
        DIALOG " $_LvmCreateVG (LV:$NUMBER_LOGICAL_VOLUMES) " --msgbox "\nLV ${LVM_LV_NAME} (${LVM_LV_SIZE}) $_LvmPvDoneBody2.\n " 0 0
        NUMBER_LOGICAL_VOLUMES=$(( NUMBER_LOGICAL_VOLUMES - 1 ))
    done

    # Now the final LV. Size is automatic.
    DIALOG " $_LvmCreateVG (LV:$NUMBER_LOGICAL_VOLUMES) " --inputbox "\n$_LvmLvNameBody1 $_LvmLvNameBody2 (${LVM_VG_MB}MB).\n " 0 0 "lvol" 2>${ANSWER} || return 0
    LVM_LV_NAME=$(cat ${ANSWER})
     
    # Loop if preceeded with a "/", if nothing is entered, if there is a space, or if that name already exists.
    while [[ ${LVM_LV_NAME:0:1} == "/" ]] || [[ ${#LVM_LV_NAME} -eq 0 ]] || [[ ${LVM_LV_NAME} =~ \ |\' ]] || [[ $(lsblk | grep ${LVM_LV_NAME}) != "" ]]; do
        DIALOG " $_ErrTitle " --msgbox "\n$_LvmLvNameErrBody\n " 0 0
        DIALOG " $_LvmCreateVG (LV:$NUMBER_LOGICAL_VOLUMES) " --inputbox "\n$_LvmLvNameBody1 $_LvmLvNameBody2 (${LVM_VG_MB}MB).\n " 0 0 "lvol" 2>${ANSWER} || return 0
        LVM_LV_NAME=$(cat ${ANSWER})
    done

    # Create the final LV
    lvcreate -l +100%FREE ${LVM_VG} -n ${LVM_LV_NAME} 2>$ERR
    check_for_error "lvcreate -l +100%FREE ${LVM_VG} -n ${LVM_LV_NAME}" "$?"
    NUMBER_LOGICAL_VOLUMES=$(( NUMBER_LOGICAL_VOLUMES - 1 ))
    LVM=1
    DIALOG " $_LvmCreateVG " --yesno "\n$_LvmCompBody\n " 0 0 && show_devices || return 0
}

check_lv_size() {
    LV_SIZE_INVALID=0
    chars=0

    # Check to see if anything was actually entered and if first character is '0'
    ([[ ${#LVM_LV_SIZE} -eq 0 ]] || [[ ${LVM_LV_SIZE:0:1} -eq "0" ]]) && LV_SIZE_INVALID=1

    # If not invalid so far, check for non numberic characters other than the last character
    if [[ $LV_SIZE_INVALID -eq 0 ]]; then
        while [[ $chars -lt $(( ${#LVM_LV_SIZE} - 1 )) ]]; do
            [[ ${LVM_LV_SIZE:chars:1} != [0-9] ]] && LV_SIZE_INVALID=1 && return 0;
            chars=$(( chars + 1 ))
        done
    fi

    # If not invalid so far, check that last character is a M/m or G/g
    if [[ $LV_SIZE_INVALID -eq 0 ]]; then
        LV_SIZE_TYPE=$(echo ${LVM_LV_SIZE:$(( ${#LVM_LV_SIZE} - 1 )):1})

        case $LV_SIZE_TYPE in
            "m"|"M"|"g"|"G") LV_SIZE_INVALID=0 ;;
            *) LV_SIZE_INVALID=1 ;;
        esac

    fi

    # If not invalid so far, check whether the value is greater than or equal to the LV remaining Size.
    # If not, convert into MB for VG space remaining.
    if [[ ${LV_SIZE_INVALID} -eq 0 ]]; then
        case ${LV_SIZE_TYPE} in
            "G"|"g")
                if [[ $(( $(echo ${LVM_LV_SIZE:0:$(( ${#LVM_LV_SIZE} - 1 ))}) * 1000 )) -ge ${LVM_VG_MB} ]]; then
                    LV_SIZE_INVALID=1
                else
                    LVM_VG_MB=$(( LVM_VG_MB - $(( $(echo ${LVM_LV_SIZE:0:$(( ${#LVM_LV_SIZE} - 1 ))}) * 1000 )) ))
                fi
                ;;
            "M"|"m")
                if [[ $(echo ${LVM_LV_SIZE:0:$(( ${#LVM_LV_SIZE} - 1 ))}) -ge ${LVM_VG_MB} ]]; then
                    LV_SIZE_INVALID=1
                else
                    LVM_VG_MB=$(( LVM_VG_MB - $(echo ${LVM_LV_SIZE:0:$(( ${#LVM_LV_SIZE} - 1 ))}) ))
                fi
                ;;
            *) LV_SIZE_INVALID=1
                ;;
        esac

    fi
}

lvm_del_vg() {
    # Generate list of VGs for selection
    lvm_show_vg

    # If no VGs, no point in continuing
    if [[ $VG_LIST == "" ]]; then
        DIALOG " $_ErrTitle " --msgbox "\n$_LvmVGErr\n " 0 0
        return 0
    fi

    # Select VG
    DIALOG " $_PrepLVM " --menu "\n$_LvmSelVGBody\n " 0 0 5 ${VG_LIST} 2>${ANSWER} || return 0

    # Ask for confirmation
    DIALOG " $_LvmDelVG " --yesno "\n$_LvmDelQ\n " 0 0

    # if confirmation given, delete
    if [[ $? -eq 0 ]]; then
        vgremove -f $(cat ${ANSWER}) 2>/dev/null
        check_for_error "delete lvm-VG $(cat ${ANSWER})"
    fi
}

lvm_show_vg() {
    VG_LIST=""
    vg_list=$(lvs --noheadings | awk '{print $2}' | uniq)

    for i in ${vg_list}; do
        VG_LIST="${VG_LIST} ${i} $(vgdisplay ${i} | grep -i "vg size" | awk '{print $3$4}')"
    done
}

lvm_del_all() {
    # check if VG exist at all
    if [[ $(lvs) == "" ]]; then
        DIALOG " $_ErrTitle " --msgbox "\n$_LvmVGErr\n " 0 0
        return 0
    fi

    LVM_PV=$(pvs -o pv_name --noheading 2>/dev/null)
    LVM_VG=$(vgs -o vg_name --noheading 2>/dev/null)
    LVM_LV=$(lvs -o vg_name,lv_name --noheading --separator - 2>/dev/null)

    # Ask for confirmation
    DIALOG " $_LvmDelLV " --yesno "\n$_LvmDelQ\n " 0 0

    # if confirmation given, delete
    if [[ $? -eq 0 ]]; then
        for i in ${LVM_LV}; do
            lvremove -f /dev/mapper/${i} 2>/dev/null
            check_for_error "remove LV ${i}"
        done

        for i in ${LVM_VG}; do
            vgremove -f ${i} 2>/dev/null
            check_for_error "remove VG ${i}"
        done

        for i in ${LV_PV}; do
            pvremove -f ${i} 2>/dev/null
            check_for_error "remove LV-PV ${i}"
        done
    fi
}

# returns a list of devices containing zfs members
zfs_list_devs() {
    # get a list of devices with zpools on them
    for device in $(zpool status -PL 2>/dev/null | awk '{print $1}' | grep "^/"); do
        # add the device
        echo $device
        # now lets add any other forms of those devices
        find -L /dev/ -xtype l -samefile ${device} 2>/dev/null
    done
}

zfs_list_datasets() {
    case $1 in
        "zvol")
            zfs list -Ht volume -o name,volsize 2>/dev/null
            ;;
        "legacy")
            zfs list -Ht filesystem -o name,mountpoint 2>/dev/null | grep "^.*/.*legacy$" | awk '{print $1}'
            ;;
        *)
            zfs list -H -o name 2>/dev/null | grep "/"
    esac
}

# creates a new zpool on an existing partition
zfs_create_zpool() {
    # LVM Detection. If detected, activate.
    lvm_detect

    INCLUDE_PART='part\|lvm\|crypt'
    umount_partitions
    find_partitions

    list_mounted > /tmp/.ignore_part
    zfs_list_devs >> /tmp/.ignore_part
    list_containing_crypt >> /tmp/.ignore_part
    check_for_error "ignore crypted: $(list_containing_crypt)"

    for part in $(cat /tmp/.ignore_part); do
        delete_partition_in_list $part
    done

    # Identify the partition for the zpool
    DIALOG " $_zfsZpoolPartMenuTitle " --menu "\n$_zfsZpoolPartMenuBody\n " 0 0 12 ${PARTITIONS} 2>${ANSWER} || return 1
    PARTITION=$(cat ${ANSWER})

    # We need to get a name for the zpool
    local -i loopmenu=1
    ZFSMENUTEXT=$_zfsZpoolCBody
    while ((loopmenu)); do
        DIALOG " $_zfsZpoolCTitle " --inputbox "\n$ZFSMENUTEXT\n " 0 0 "zpmanjaro" 2>${ANSWER} || return 1
        ZFSMENUTEXT=$_zfsZpoolCBody

        # validation
        [[ ! $(cat ${ANSWER}) =~ ^[a-zA-Z][a-zA-Z0-9.:_-]*$ ]] && ZFSMENUTEXT=$_zfsZpoolCValidation1
        [[ $(cat ${ANSWER}) =~ ^(log|mirror|raidz|raidz1|raidz2|raidz3|spare).*$ ]] && ZFSMENUTEXT=$_zfsZpoolCValidation2

        [[ $ZFSMENUTEXT == $_zfsZpoolCBody ]] && loopmenu=0
    done
    ZFS_ZPOOL_NAME=$(cat ${ANSWER})

    # Find the UUID of the partition
    PARTUUID=$(lsblk -lno PATH,PARTUUID | grep "^${PARTITION}" | awk '{print $2}')

    # See if the partition has a partuuid, if not use the device name
    if [[ -n ${PARTUUID} ]]; then
        zpool create -m none ${ZFS_ZPOOL_NAME} ${PARTUUID} 2>$ERR
        check_for_error "Creating zpool ${ZFS_ZPOOL_NAME} on device ${PARTITION} using partuuid ${PARTUUID}"
    else
        zpool create -m none ${ZFS_ZPOOL_NAME} ${PARTITION} 2>$ERR
        check_for_error "Creating zpool ${ZFS_ZPOOL_NAME} on device ${PARTITION}"
    fi

    ZFS=1

    # Since zfs manages mountpoints, we export it and then import with a root of $MOUNTPOINT
    zpool export ${ZFS_ZPOOL_NAME} 2>$ERR
    zpool import -R ${MOUNTPOINT} ${ZFS_ZPOOL_NAME} 2>>$ERR
    check_for_error "Export and importing ${ZFS_POOL_NAME}"

    return 0
}

# Creates a zfs filesystem, the first parameter is the ZFS path and the second is the mount path
zfs_create_dataset() {
    local zpath=$1
    local zmount=$2

    zfs create -o mountpoint=$zmount $zpath 2>$ERR
    check_for_error "Creating zfs dataset ${zpath} with mountpoint ${zmount}"
}

# Automated configuration of zfs.  Creates a new zpool and a default set of filesystems
zfs_auto() {
    # first we need to create a zpool to hold the datasets/zvols
    zfs_create_zpool
    if [ $? != 0 ]; then
        DIALOG " $_zfsZpoolCTitle " --infobox "\n$_zfsCancelled\n " 0 0
        sleep 3
        return 0
    fi

    # next create the datasets including their parents
    zfs_create_dataset "${ZFS_ZPOOL_NAME}/data" "none" 
    zfs_create_dataset "${ZFS_ZPOOL_NAME}/ROOT" "none" 
    zfs_create_dataset "${ZFS_ZPOOL_NAME}/ROOT/manjaro" "none"
    zfs_create_dataset "${ZFS_ZPOOL_NAME}/ROOT/manjaro/root" "/"
    zfs_create_dataset "${ZFS_ZPOOL_NAME}/data/home" "/home"
    zfs_create_dataset "${ZFS_ZPOOL_NAME}/ROOT/manjaro/paccache" "/var/cache/pacman"

    # set the rootfs
    zpool set bootfs=${ZFS_ZPOOL_NAME}/ROOT/manjaro/root ${ZFS_ZPOOL_NAME} 2>$ERR
    check_for_error "Setting zfs bootfs"
    
    # provide confirmation to the user
    DIALOG " $_zfsZpoolCTitle " --infobox "\n$_zfsAutoComplete\n " 0 0
    sleep 3
}

zfs_import_pool() {
    local zplist

    local zpoolitem
    for zpoolitem in $(zpool import 2>/dev/null | grep "^[[:space:]]*pool" | awk -F : '{print $2}' | awk '{$1=$1};1'); do
        zplist="${zplist} ${zpoolitem} -"
    done

    if [[ ${zplist} ]]; then
        DIALOG " $_zfsZpoolImportMenuTitle " --menu "\n$_zfsZpoolImportMenuBody\n " 0 0 12 ${zplist} 2>${ANSWER} || return 0
        zpool import -R ${MOUNTPOINT} $(cat ${ANSWER}) 2>$ERR
        check_for_error "Import zpool $(cat ${ANSWER})"
        ZFS=1
    else
        DIALOG " $_zfsZpoolImportMenuTitle " --infobox "\n$_zfsZpoolNoPool\n " 0 0
        sleep 3
    fi
}

# return a list of imported zpools
zfs_list_pools() {
    zpool list -H 2>/dev/null | awk '{print $1}' 
}

zfs_new_ds() {
    local zplist
    local zmount=$1
    local zpoolitem

    for zpoolitem in `zfs_list_pools`; do
        zplist="${zplist} ${zpoolitem} -"
    done


    if [[ ${zplist} ]]; then
        # select a zpool
        DIALOG " $_zfsSelectZpoolMenuTitle " --menu "\n$_zfsSelectZpoolMenuBody\n " 0 0 12 ${zplist} 2>${ANSWER} || return 0
        local zpool=$(cat ${ANSWER})
    else
        # no imported zpools
        DIALOG " $_zfsSelectZpoolMenuTitle " --infobox "\n$_zfsZpoolNoPool\n " 0 0
        sleep 3
        return 0
    fi

    # enter a name for the dataset
    local -i loopmenu=1
    local zfsmenubody=$_zfsDSMenuNameBody
    while ((loopmenu)); do
        DIALOG " $_zfsDSMenuNameTitle " --inputbox "\n$zfsmenubody\n " 0 0 "" 2>${ANSWER} || return 1

        # validation
        [[ ! $(cat ${ANSWER}) =~ ^[a-zA-Z][a-zA-Z0-9.:/_-]*$ ]] && zfsmenubody=$_zfsZpoolCValidation1 || loopmenu=0
    done
    local zname=$(cat ${ANSWER})

    case $zmount in
        "legacy")
            zfs_create_dataset ${zpool}/${zname} ${zmount} 2>$ERR
            ;;
        "zvol")
            # get the size of the zvol
            loopmenu=1
            zfsmenubody=$_zfsZvolSizeMenuBody
            while ((loopmenu)); do
                DIALOG " $_zfsZvolSizeMenuTitle " --inputbox "\n$zfsmenubody\n " 0 0 "" 2>${ANSWER} || return 1

                # validation
                [[ $(cat ${ANSWER}) =~ ^[0-9]*$ ]] && loopmenu=0 || zfsmenubody=$_zfsZvolSizeMenuValidation
            done
            local zsize=$(cat ${ANSWER})

            zfs create -V ${zsize}M ${zpool}/${zname} 2>$ERR
            ;;
        *)
            # select a mount point
            loopmenu=1
            zfsmenubody=$_zfsMountMenuBody
            while ((loopmenu)); do
                DIALOG " $_zfsMountMenuTitle " --inputbox "\n$zfsmenubody\n " 0 0 "" 2>${ANSWER} || return 0
                zmount=$(cat ${ANSWER})
                zfsmenubody=$_zfsMountMenuBody

                # validation
                [[ $(findmnt -n ${MOUNTPOINT}/${zmount}) ]] && zfsmenubody=$_zfsMountMenuInUse
                [[ ! ($zmount =~ ^/ || $zmount == none) ]] && zfsmenubody=$_zfsMountMenuNotValid

                [[ $zfsmenubody == $_zfsMountMenuBody ]] && loopmenu=0
            done
            zfs_create_dataset ${zpool}/${zname} ${zmount} 2>$ERR
            ;;
    esac
    check_for_error "new zfs dataset ${zpool}/${zname} on ${zmount}"
}

zfs_destroy_dataset() {
    local zlist

    # get dataset list and format for the menu
    local zds
    for zds in $(zfs_list_datasets); do
        zlist="${zlist} ${zds} -"
    done

    # select the dataset to destroy
    if [[ ${zlist} ]]; then
        DIALOG " $_zfsDestroyMenuTitle " --menu "\n$_zfsDestroyMenuBody\n " 0 0 12 ${zlist} 2>${ANSWER} || return 0
        local zdataset=$(cat ${ANSWER})
    else
        # no available datasets
        DIALOG " $_zfsDestroyMenuTitle " --infobox "\n$_zfsDatasetNotFound\n " 0 0
        sleep 3
        return 0
    fi
    
    # better confirm this one
    DIALOG --defaultno --yesno "$_zfsDestroyMenuConfirm1 ${zdataset} $_zfsDestroyMenuConfirm2" 0 0
    if [ $? ]; then
        zfs destroy -r ${zdataset}
        check_for_error "zfs destroy ${zdataset}"
    fi
}

zfs_set_property () {
   local zlist

    # get dataset list and format for the menu
    local zds
    for zds in $(zfs_list_datasets); do
        zlist="${zlist} ${zds} -"
    done

    # select the dataset
    if [[ ${zlist} ]]; then
        DIALOG " $_zfsSetMenuTitle " --menu "\n$_zfsSetMenuBody\n " 0 0 12 ${zlist} 2>${ANSWER} || return 0
        local zdataset=$(cat ${ANSWER})
    else
        # no available datasets
        DIALOG " $_zfsSetMenuTitle " --infobox "\n$_zfsDatasetNotFound\n " 0 0
        sleep 3
        return 0
    fi
    
    # get property/value input
    local -i loopmenu=1
    zfsmenubody=$_zfsSetMenuBody
    local zsetstmt
    while ((loopmenu)); do
        DIALOG " $_zfsSetMenuTitle " --inputbox "\n$zfsmenubody\n " 0 0 "" 2>${ANSWER} || return 0
        zsetstmt=$(cat ${ANSWER})

        # validation
        [[ ! $zsetstmt =~ ^[a-zA-Z@]*=[a-zA-Z0-9@-]*$ ]] && zfsmenubody=$_zfsMountMenuNotValid || loopmenu=0
    done

    #set the property
    zfs set ${zsetstmt} ${zdataset} 2>$ERR
    check_for_error "zfs set ${zsetstmt} on ${zdataset}"
}

zfs_menu_manual() {
    local -i loopmenu=1
    while ((loopmenu)); do
        DIALOG " $_zfsManualMenuTitle " --menu "\n$_zfsManualMenuBody\n " 22 60 8 \
          "$_zfsManualMenuOptCreate" "" \
          "$_zfsManualMenuOptImport" "" \
          "$_zfsManualMenuOptNewFile" "" \
          "$_zfsManualMenuOptNewLegacy" "" \
          "$_zfsManualMenuOptNewZvol" "" \
          "$_zfsManualMenuOptSet" "" \
          "$_zfsManualMenuOptDestroy" "" \
          "$_Back" "" 2>${ANSWER}

        case $(cat ${ANSWER}) in
            "$_zfsManualMenuOptCreate") zfs_create_zpool
               ;;
            "$_zfsManualMenuOptImport") zfs_import_pool
               ;;
            "$_zfsManualMenuOptNewFile") zfs_new_ds
               ;;
            "$_zfsManualMenuOptNewLegacy") zfs_new_ds "legacy"
               ;;
            "$_zfsManualMenuOptNewZvol") zfs_new_ds "zvol"
               ;;
            "$_zfsManualMenuOptSet") zfs_set_property
               ;;
            "$_zfsManualMenuOptDestroy") zfs_destroy_dataset
               ;;
            *) loopmenu=0
               return 0
               ;;
        esac
    done
}

# The main ZFS menu
zfs_menu() {
    # check for zfs support
    modprobe zfs 2>$ERR
    if [[ $(cat $ERR) ]]; then
        DIALOG " $_zfsZpoolCTitle " --infobox "\n$_zfsNotSupported\n " 0 0
        sleep 3
        return 0
    fi

    declare -i loopmenu=1
    while ((loopmenu)); do
        DIALOG " $_PrepZFS " --menu "\n$_zfsMainMenuBody\n " 22 60 3 \
          "$_zfsMainMenuOptAutomatic" "" \
          "$_zfsMainMenuOptManual" "" \
          "$_Back" "" 2>${ANSWER}

        case $(cat ${ANSWER}) in
            "$_zfsMainMenuOptAutomatic") zfs_auto
               ;;
            "$_zfsMainMenuOptManual") zfs_menu_manual
               ;;
            *) loopmenu=0
               return 0
               ;;
        esac
    done
}

make_esp() {
    # Extra Step for VFAT UEFI Partition. This cannot be in an LVM container.
    if [[ $SYSTEM == "UEFI" ]]; then
        if DIALOG " $_PrepMntPart " --menu "\n$_SelUefiBody\n " 0 0 12 ${PARTITIONS} 2>${ANSWER}; then
            PARTITION=$(cat ${ANSWER})
            UEFI_PART=${PARTITION}

            # If it is already a fat/vfat partition...
            if [[ $(fsck -N $PARTITION | grep fat) ]]; then
                DIALOG " $_PrepMntPart " --defaultno --yesno "\n$_FormUefiBody $PARTITION $_FormUefiBody2\n " 0 0 && {
                    mkfs.vfat -F32 ${PARTITION} >/dev/null 2>$ERR
                    check_for_error "mkfs.vfat -F32 ${PARTITION}" "$?"
                } # || return 0
            else
                mkfs.vfat -F32 ${PARTITION} >/dev/null 2>$ERR
                check_for_error "mkfs.vfat -F32 ${PARTITION}" "$?"
            fi

            if [[ "$LUKS" == 0 ]]; then
                _MntUefiMessage="$_MntUefiBody"
            else
                _MntUefiMessage="$_MntUefiCrypt"
            fi
            DIALOG " $_PrepMntPart " --radiolist "\n$_MntUefiMessage\n "  0 0 2 \
            "/boot/efi" "" on \
            "/boot" "" off 2>${ANSWER}

            if [[ $(cat ${ANSWER}) != "" ]]; then
                UEFI_MOUNT=$(cat ${ANSWER})
                mkdir -p ${MOUNTPOINT}${UEFI_MOUNT} 2>$ERR
                check_for_error "create ${MOUNTPOINT}${UEFI_MOUNT}" $?
                mount ${PARTITION} ${MOUNTPOINT}${UEFI_MOUNT} 2>$ERR
                check_for_error "mount ${PARTITION} ${MOUNTPOINT}${UEFI_MOUNT}" $?
                if confirm_mount ${MOUNTPOINT}${UEFI_MOUNT}; then
                    ini mount.efi "${UEFI_MOUNT}"
                    delete_partition_in_list "$PARTITION"
                fi
            fi
        fi
    fi
}

mount_partitions() {
    # Warn users that they CAN mount partitions without formatting them!
    DIALOG " $_PrepMntPart " --msgbox "\n$_WarnMount1 '$_FSSkip' $_WarnMount2\n " 15 65

    # LVM Detection. If detected, activate.
    lvm_detect

    # Ensure partitions are unmounted (i.e. where mounted previously)
    INCLUDE_PART='part\|lvm\|crypt'
    umount_partitions

    # We need to remount the zfs filesystems that have defined mountpoints already
    zfs mount -aO 2>/dev/null

    # Get list of available partitions
    find_partitions

    # Add legacy zfs filesystems to the list - these can be mounted but not formatted
    for i in $(zfs_list_datasets "legacy"); do
        PARTITIONS="${PARTITIONS} ${i}"
        PARTITIONS="${PARTITIONS} zfs"
        NUMBER_PARTITIONS=$(( NUMBER_PARTITIONS + 1 ))
    done

    # Filter out partitions that have already been mounted and partitions that just contain crypt or zfs devices
    list_mounted > /tmp/.ignore_part
    zfs_list_devs >> /tmp/.ignore_part
    list_containing_crypt >> /tmp/.ignore_part
    check_for_error "ignore crypted: $(list_containing_crypt)"

    for part in $(cat /tmp/.ignore_part); do
        delete_partition_in_list $part
    done

    # check to see if we already have a zfs root mounted
    if [ $(findmnt -ln -o FSTYPE ${MOUNTPOINT}) == "zfs" ]; then
        DIALOG " $_PrepMntPart " --infobox "\n$_zfsFoundRoot\n " 0 0
        sleep 3
    else
        # Identify and mount root
        DIALOG " $_PrepMntPart " --menu "\n$_SelRootBody\n " 0 0 12 ${PARTITIONS} 2>${ANSWER} || return 0
        PARTITION=$(cat ${ANSWER})
        ROOT_PART=${PARTITION}
        echo ${ROOT_PART} > /tmp/.root_partitioni
        echo ${ROOT_PART} > /tmp/.root_partition
        
	# Reset the mountpoint variable, in case this is the second time through this menu and old state is still around
	MOUNT=""

	# Format with FS (or skip) -> # Make the directory and mount. Also identify LUKS and/or LVM
        select_filesystem && mount_current_partition || return 0

        ini mount.root "${PARTITION}"
        delete_partition_in_list "${ROOT_PART}"

        # Extra check if root is on LUKS or lvm
        get_cryptroot
        echo "$LUKS_DEV" > /tmp/.luks_dev
        # If the root partition is btrfs, offer to create subvolumus
        if [[ $(findmnt -no FSTYPE ${MOUNTPOINT}) == btrfs ]]; then
            # Check if there are subvolumes already on the btrfs partition
            if [[ $(btrfs subvolume list ${MOUNTPOINT} | wc -l) -gt 1 ]] && DIALOG " The volume has already subvolumes " --yesno "\nFound subvolumes $(btrfs subvolume list ${MOUNTPOUNT} | cut -d" " -f9)\n\nWould you like to mount them? \n " 0 0; then
                # Pre-existing subvolumes and user wants to mount them
                mount_existing_subvols
            else
                # No subvolumes present. Make some new ones
                DIALOG " Your root volume is formatted in btrfs " --yesno "\nWould you like to create subvolumes in it? \n " 0 0 && btrfs_subvolumes
            fi
        fi    
    fi

    # We need to remove legacy zfs partitions before make_swap since they can't hold swap
    local zlegacy
    for zlegacy in $(zfs_list_datasets "legacy"); do
        delete_partition_in_list ${zlegacy}
    done

    # Identify and create swap, if applicable
    make_swap

    # Now that swap is done we put the legacy partitions back, unless they are already mounted
    for i in $(zfs_list_datasets "legacy"); do
        PARTITIONS="${PARTITIONS} ${i}"
        PARTITIONS="${PARTITIONS} zfs"
        NUMBER_PARTITIONS=$(( NUMBER_PARTITIONS + 1 ))
    done

    for part in $(list_mounted); do
        delete_partition_in_list $part
    done


    # All other partitions
    while [[ $NUMBER_PARTITIONS > 0 ]]; do
        DIALOG " $_PrepMntPart " --menu "\n$_ExtPartBody\n " 0 0 12 "$_Done" $"-" ${PARTITIONS} 2>${ANSWER} || return 0
        PARTITION=$(cat ${ANSWER})

        if [[ $PARTITION == $_Done ]]; then
                make_esp
                get_cryptroot
                get_cryptboot
                echo "$LUKS_DEV" > /tmp/.luks_dev
                return 0;
        else
            MOUNT=""
            select_filesystem

            # Ask user for mountpoint. Don't give /boot as an example for UEFI systems!
            [[ $SYSTEM == "UEFI" ]] && MNT_EXAMPLES="/home\n/var" || MNT_EXAMPLES="/boot\n/home\n/var"
            DIALOG " $_PrepMntPart $PARTITON " --inputbox "\n$_ExtPartBody1$MNT_EXAMPLES\n " 0 0 "/" 2>${ANSWER} || return 0
            MOUNT=$(cat ${ANSWER})

            # loop while the mountpoint specified is incorrect (is only '/', is blank, or has spaces).
            while [[ ${MOUNT:0:1} != "/" ]] || [[ ${#MOUNT} -le 1 ]] || [[ $MOUNT =~ \ |\' ]]; do
                # Warn user about naming convention
                DIALOG " $_ErrTitle " --msgbox "\n$_ExtErrBody\n " 0 0
                # Ask user for mountpoint again
                DIALOG " $_PrepMntPart $PARTITON " --inputbox "\n$_ExtPartBody1$MNT_EXAMPLES\n " 0 0 "/" 2>${ANSWER} || return 0
                MOUNT=$(cat ${ANSWER})
            done

            # Create directory and mount.
            mount_current_partition
            delete_partition_in_list "$PARTITION"

            # Determine if a seperate /boot is used. 0 = no seperate boot, 1 = seperate non-lvm boot,
            # 2 = seperate lvm boot. For Grub configuration
            if  [[ $MOUNT == "/boot" ]]; then
                [[ $(lsblk -lno TYPE ${PARTITION} | grep "lvm") != "" ]] && LVM_SEP_BOOT=2 || LVM_SEP_BOOT=1
            fi
        fi
    done
}

get_cryptroot() {
        # Identify if /mnt or partition is type "crypt" (LUKS on LVM, or LUKS alone)
    if $(lsblk | sed -r 's/^[^[:alnum:]]+//' | awk '/\/mnt$/ {print $6}' | grep -q crypt) || $(lsblk -i | tac | sed -r 's/^[^[:alnum:]]+//' | sed -n -e "/\/mnt$/,/part/p" | awk '{print $6}' | grep -q crypt); then
        LUKS=1
        root_name=$(mount | awk '/\/mnt / {print $1}' | sed s~/dev/mapper/~~g | sed s~/dev/~~g)
        #Get the name of the Luks device
        if $(lsblk -i | grep -q -e "crypt /mnt"); then
            # Mountpoint is directly on the LUKS device, so LUKS deivece is the same as root name
            LUKS_ROOT_NAME="$root_name"
        else
            # Mountpoint is not directly on LUKS device, so we need to get the crypt device above the mountpoint
            LUKS_ROOT_NAME="$(lsblk -i | tac | sed -r 's/^[^[:alnum:]]+//' | sed -n -e "/\/mnt$/,/crypt/p" | awk '/crypt/ {print $1}')"
        fi
      
        # Check if LUKS on LVM  
        if [[ $(lsblk -lno NAME,FSTYPE,TYPE,MOUNTPOINT | grep "lvm" | grep "/mnt$" | grep -i "crypto_luks" | uniq | awk '{print "/dev/mapper/"$1}') != "" ]]; then
            cryptparts=$(lsblk -lno NAME,FSTYPE,TYPE,MOUNTPOINT | grep "lvm" | grep "/mnt$" | grep -i "crypto_luks" | uniq | awk '{print "/dev/mapper/"$1}')
            for i in ${cryptparts}; do
                if [[ $(lsblk -lno NAME ${i} | grep $LUKS_ROOT_NAME) != "" ]]; then
                    LUKS_DEV="cryptdevice=${i}:$LUKS_ROOT_NAME"
                    LVM=1
                fi
            done
        fi
        # Check if LVM on LUKS
        if [[ $(lsblk -lno NAME,FSTYPE,TYPE | grep " crypt$" | grep -i "LVM2_member" | uniq | awk '{print "/dev/mapper/"$1}') != "" ]]; then
            cryptparts=$(lsblk -lno NAME,FSTYPE,TYPE | grep " crypt$" | grep -i "LVM2_member" | uniq | awk '{print "/dev/mapper/"$1}')
            for i in ${cryptparts}; do
                if [[ $(lsblk -lno NAME ${i} | grep $LUKS_ROOT_NAME) != "" ]]; then
                    LUKS_UUID=$(lsblk -ino NAME,FSTYPE,TYPE,MOUNTPOINT,UUID | tac | sed -r 's/^[^[:alnum:]]+//' | sed -n -e "/\/mnt /,/part/p" | awk '/crypto_LUKS/ {print $4}')
                    LUKS_DEV="cryptdevice=UUID=$LUKS_UUID:$LUKS_ROOT_NAME"
                    LVM=1
                fi
            done
        fi
        # Check if LUKS alone
        if [[ $(lsblk -lno NAME,FSTYPE,TYPE | grep "part" | grep -i "crypto_luks" | uniq | awk '{print "/dev/"$1}') != "" ]]; then
            cryptparts=$(lsblk -lno NAME,FSTYPE,TYPE,MOUNTPOINT | grep "/mnt$" | grep "part" | grep -i "crypto_luks" | uniq | awk '{print "/dev/"$1}')
            for i in ${cryptparts}; do
                if [[ $(lsblk -lno NAME ${i} | grep $LUKS_ROOT_NAME) != "" ]]; then
                    LUKS_UUID=$(lsblk -lno UUID,TYPE,FSTYPE ${i} | grep "part" | grep -i "crypto_luks" | awk '{print $1}')
                    LUKS_DEV="cryptdevice=UUID=$LUKS_UUID:$LUKS_ROOT_NAME"
                fi
            done
        fi
        echo "$LUKS_DEV" > /tmp/.luks_dev
    fi 

}

get_cryptboot(){
    # If /boot is encrypted
    if $(lsblk | sed -r 's/^[^[:alnum:]]+//' | awk '/\/mnt\/boot$/ {print $6}' | grep -q crypt) || $(lsblk -i | tac | sed -r 's/^[^[:alnum:]]+//' | sed -n -e "/\/mnt\/boot$/,/part/p" | awk '{print $6}' | grep -q crypt); then
    
        LUKS=1
        boot_name=$(mount | awk '/\/mnt\/boot / {print $1}' | sed s~/dev/mapper/~~g | sed s~/dev/~~g)
        #Get the name of the Luks device
        if $(lsblk -i | grep -q -e "crypt /mnt"); then
            # Mountpoint is directly on the LUKS device, so LUKS deivece is the same as root name
            LUKS_BOOT_NAME="$boot_name"
            # Get UUID of the encrypted /boot
            LUKS_BOOT_UUID=$(lsblk -lno UUID,MOUNTPOINT | awk '/\mnt\/boot$/ {print $1}')
        else
            # Mountpoint is not directly on LUKS device, so we need to get the crypt device above the mountpoint
            LUKS_BOOT_NAME="$(lsblk -i | tac | sed -r 's/^[^[:alnum:]]+//' | sed -n -e "/\/mnt\/boot$/,/crypt/p" | awk '/crypt/ {print $1}')"
            # Get UUID of the encrypted /boot
            LUKS_BOOT_UUID=$(lsblk -ino NAME,FSTYPE,TYPE,MOUNTPOINT,UUID | tac | sed -r 's/^[^[:alnum:]]+//' | sed -n -e "/\/mnt\/boot /,/part/p" | awk '/crypto_LUKS/ {print $4}')
        fi

        # Check if LVM on LUKS
        if $(lsblk -lno TYPE,MOUNTPOINT | grep "/mnt/boot$" | grep -q lvm); then
            LVM=1
        fi
        # Add Cryptdevice to LUKS_DEV, if not already present (if on same LVM on LUKS as /)
        if [[ $(echo $LUKS_DEV | grep $LUKS_BOOT_UUID) == "" ]]; then
            LUKS_DEV="$LUKS_DEV cryptdevice=UUID=$LUKS_BOOT_UUID:$LUKS_BOOT_NAME"
        fi
        echo "$LUKS_DEV" > /tmp/.luks_dev
    fi

}

btrfs_subvolumes() {
    #1) save mount options and name of the root partition 
    mount | grep "on /mnt " | grep -Po '(?<=\().*(?=\))' > /tmp/.root_mount_options
    #lsblk -lno MOUNTPOINT,NAME | awk '/^\/mnt / {print $2}' > /tmp/.root_partition
    #2) choose automatic or manual mode
    DIALOG " Choose mode " --menu "\n$_Note\nAutomatic mode is designed to\nallow integration with snapper,\nnon-recursive snapshots,\nseparating system and user data\nand restoring snapshots without losing data. " 0 0 2 \
      "1" "automatic" \
      "2" "manual" 2>/tmp/.subvol_mode

    if [[ $(cat /tmp/.subvol_mode) != "" ]]; then
        if [[ $(cat /tmp/.subvol_mode) -eq 2 ]]; then
            # Create subvolumes manually
            DIALOG " Create subvolumes " --inputbox "\nInput names of the subvolumes separated by spaces. The first one will be used for mounting /." 0 0 "@ @home @cache" 2>/tmp/.subvols || return 0
            cd /mnt
            for subvol in $(cat /tmp/.subvols); do
                btrfs subvolume create $subvol
            done
            cd
            # Mount subvolumes
            umount /mnt
            # Mount the first subvolume as / 
            mount -o $(cat ${MOUNT_OPTS}),subvol="$(awk '{print $1}' /tmp/.subvols)" "$(cat /tmp/.root_partition)" /mnt
            # Remove the first subvolume from the subvolume list
            sed -i -r 's/(\s+)?\S+//1' /tmp/.subvols
            # Loop to mount all created subvolumes
            for sub in $(cat /tmp/.subvols); do
                DIALOG "Mount subvolume $sub" --inputbox "\nInput mountpoint of the subvolume $sub\nas it would appear in installed system\n(without prepending /mnt)\n." 0 0 "/home" 2>/tmp/.mountp || return 0
                mkdir -p /mnt/"$(cat /tmp/.mountp)"
                mount -o $(cat ${MOUNT_OPTS}),subvol="$sub" "$(cat /tmp/.root_partition)" /mnt"$(cat /tmp/.mountp)"
            done
        else
            DIALOG " Automatic btrfs subvolumes" --yesno "\nThis creates subvolumes @ for /,@home for /home, @cache for /var/cache. \n " 0 0 || return 0
            # Create subvolumes automatically
            cd /mnt
            btrfs subvolume create @
            btrfs subvolume create @home
            btrfs subvolume create @cache
            #btrfs subvolume create @snapshots
            cd
            # Mount subvolumes
            umount /mnt
            mount -o $(cat ${MOUNT_OPTS}),subvol=@ "$(cat /tmp/.root_partition)" /mnt
            mkdir -p /mnt/home
            mkdir -p /mnt/var/cache
            mount -o $(cat ${MOUNT_OPTS}),subvol=@home "$(cat /tmp/.root_partition)" /mnt/home
            #mount -o $(cat ${MOUNT_OPTS}),subvol=@cache "$(cat /tmp/.root_partition)" /mnt/var/cache
        fi
    else
        return 0
    fi
}

mount_existing_subvols() {
    # Set mount options
    format_name=$(echo ${PARTITION} | rev | cut -d/ -f1 | rev)
    format_device=$(lsblk -i | tac | sed -r 's/^[^[:alnum:]]+//' | sed -n -e "/$format_name/,/disk/p" | awk '/disk/ {print $1}')   
    if [[ "$(cat /sys/block/${format_device}/queue/rotational)" == 1 ]]; then
        fs_opts="autodefrag,compress=zlib,noatime,nossd,commit=120"
    else
        fs_opts="compress=lzo,noatime,space_cache,ssd,commit=120"
    fi
    btrfs subvolume list /mnt | cut -d" " -f9 > /tmp/.subvols
    umount /mnt
    # Mount subvolumes one by one
    for subvol in $(cat /tmp/.subvols); do
        # Ask for mountpoint
        DIALOG "Mount subvolume $subvol" --inputbox "\nInput mountpoint of the subvolume $subvol\nas it would appear in installed system\n(without prepending /mnt).\n" 0 0 "/" 2>/tmp/.mountp || return 0
        [[ -e "/mnt/$(cat /tmp/.mountp)" ]] || mkdir -p /mnt/"$(cat /tmp/.mountp)"
        # Mount the subvolume
        mount -o "${fs_opts},subvol=$subvol" "$(cat /tmp/.root_partition)" /mnt"$(cat /tmp/.mountp)"
    done
}
