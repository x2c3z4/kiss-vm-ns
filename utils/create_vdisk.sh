#!/bin/bash

dd_range() {
	local if=$1
	local of=$2
	local SKIP=${3:-0}
	local SIZE=$4
	local BS=$((8 * 1024))

	[[ -z "$of" ]] && return 1

	dd if=$if bs=$BS count=1 | dd iflag=fullblock,skip_bytes ibs=$SKIP skip=1 >$of
	if [[ -z "$SIZE" ]]; then
		dd if=$if bs=$BS skip=1 >>$of
	else
		CNT=$((SIZE/BS + 1))
		dd if=$if bs=$BS skip=1 count=$CNT >>$of
		truncate --size=${SIZE} $of
	fi
}

create_vdisk() {
	local path=$1
	local size=$2
	local fstype=$3
	local imghead=img-head-$$
	local imgtail=img-tail-$$

	dd if=/dev/null of=$path bs=1${size//[0-9]/} seek=${size//[^0-9]/}
	printf "o\nn\np\n1\n\n\nw\n" | fdisk "$path"
	partprobe "$path"

	read start size < <( parted -s $path unit B print | sed 's/B//g' |
		awk -v P=1 '/^Number/{start=1;next}; start {if ($1==P) {print $2, $4}}' )
	dd if=$path of=$imghead bs=${start} count=1
	dd_range $path $imgtail $((start)) ${size}
	mkfs.$fstype $MKFS_OPT "$imgtail"
	cat $imghead $imgtail >$path
	rm -f $imghead $imgtail
}

[[ $# -lt 3 ]] && {
	cat <<-COMM
	Usage: [MKFS_OPT=xxx] $0 <image> <size> <fstype>

	Examples:
	  $0 usb.img 256M vfat
	  $0 ext4.img 4G ext4
	  MKFS_OPT="-f -i attr=2,size=512" $0 xfs.img 4G xfs
	COMM
	exit 1
}
create_vdisk "$@"
