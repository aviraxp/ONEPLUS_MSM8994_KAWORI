# AnyKernel2 Script
#
# Original and credits: osm0sis @ xda-developers
#
# Modified by Lord Boeffla, 30.06.2016

############### AnyKernel setup start ############### 

# EDIFY properties
do.devicecheck=1
do.initd=0
do.modules=1
do.cleanup=1
device.name1=OnePlus2
device.name2=oneplus2
device.name3=
device.name4=
device.name5=
device.name6=
device.name7=
device.name8=
device.name9=
device.name10=
device.name11=
device.name12=
device.name13=
device.name14=
device.name15=

# shell variables
block=/dev/block/bootdevice/by-name/boot;
add_seandroidenforce=0
supersu_exclusions=""

############### AnyKernel setup end ############### 


## internal functions

# ui_print <text>
ui_print()
{
	echo -e "ui_print $1\nui_print" > $OUTFD;
}

# contains <string> <substring>
contains()
{
	test "${1#*$2}" != "$1" && return 0 || return 1;
}

# dump boot and extract ramdisk
dump_boot()
{
	dd if=$block of=/tmp/anykernel/boot.img;

	$bin/unpackbootimg -i /tmp/anykernel/boot.img -o $split_img;
	if [ $? != 0 ]; then
		ui_print " ";
		ui_print "Dumping/splitting image failed. Aborting...";
		exit 1;
	fi;

	mv -f $ramdisk /tmp/anykernel/rdtmp;
	mkdir -p $ramdisk;
	cd $ramdisk;
	gunzip -c $split_img/boot.img-ramdisk.gz | cpio -i;

	if [ $? != 0 -o -z "$(ls $ramdisk)" ]; then
		ui_print " ";
		ui_print "Unpacking ramdisk failed. Aborting...";
		exit 1;
	fi;

	if [ -d $ramdisk/su ]; then
			ui_print "  SuperSu systemless detected...";
			ui_print " ";

			SAVE_IFS=$IFS;
			IFS=";"
			for filename in $supersu_exclusions; do 
				rm -f /tmp/anykernel/rdtmp/$filename
			done
			IFS=$SAVE_IFS;
	fi;

	cp -af /tmp/anykernel/rdtmp/* $ramdisk;
}

# repack ramdisk then build and write image
write_boot()
{
	cd $split_img;
	cmdline=`cat *-cmdline`;
	board=`cat *-board`;
	base=`cat *-base`;
	pagesize=`cat *-pagesize`;
	kerneloff=`cat *-kerneloff`;
	ramdiskoff=`cat *-ramdiskoff`;
	tagsoff=`cat *-tagsoff`;

	if [ -f *-second ]; then
		second=`ls *-second`;
		second="--second $split_img/$second";
		secondoff=`cat *-secondoff`;
		secondoff="--second_offset $secondoff";
	fi;

	if [ -f /tmp/anykernel/zImage ]; then
		kernel=/tmp/anykernel/zImage;
	else
		kernel=`ls *-zImage`;
		kernel=$split_img/$kernel;
	fi;

	if [ -f /tmp/anykernel/dtb ]; then
		dtb="--dt /tmp/anykernel/dtb";
	elif [ -f *-dtb ]; then
		dtb=`ls *-dtb`;
		dtb="--dt $split_img/$dtb";
	fi;

	if [ -f "$bin/mkbootfs" ]; then
		$bin/mkbootfs /tmp/anykernel/ramdisk | gzip > /tmp/anykernel/ramdisk-new.cpio.gz;
	else
		cd $ramdisk;
		find . | cpio -H newc -o | gzip > /tmp/anykernel/ramdisk-new.cpio.gz;
	fi;

	if [ $? != 0 ]; then
		ui_print " ";
		ui_print "Repacking ramdisk failed. Aborting...";
		exit 1;
	fi;

	$bin/mkbootimg --kernel $kernel --ramdisk /tmp/anykernel/ramdisk-new.cpio.gz $second --cmdline "$cmdline" --board "$board" --base $base --pagesize $pagesize --kernel_offset $kerneloff --ramdisk_offset $ramdiskoff $secondoff --tags_offset $tagsoff $dtb --output /tmp/anykernel/boot-new.img;

	if [ $? != 0 ]; then
		ui_print " ";
		ui_print "Repacking image failed. Aborting...";
		exit 1;
	elif [ `wc -c < /tmp/anykernel/boot-new.img` -gt `wc -c < /tmp/anykernel/boot.img` ]; then
		ui_print " ";
		ui_print "New image larger than boot partition. Aborting...";
		exit 1;
	fi;

	if [ -f "/data/custom_boot_image_patch.sh" ]; then
		ash /data/custom_boot_image_patch.sh /tmp/anykernel/boot-new.img;
		if [ $? != 0 ]; then
			ui_print " ";
			ui_print "User script execution failed. Aborting...";
			exit 1;
		fi;
	fi;

	if [ $add_seandroidenforce == "1" ]; then
		echo -n "SEANDROIDENFORCE" >> /tmp/anykernel/boot-new.img
	fi

	dd if=/tmp/anykernel/boot-new.img of=$block;
}

# backup_file <file>
backup_file()
{ 
	cp $1 $1~;
}

# replace_string <file> <if search string> <original string> <replacement string>
replace_string()
{
	if [ -z "$(grep "$2" $1)" ]; then
		sed -i "s;${3};${4};" $1;
	fi;
}

# replace_section <file> <begin search string> <end search string> <replacement string>
replace_section()
{
	S1=$(echo ${2} | sed 's/\//\\\//g'); # escape forward slashes
	S2=$(echo ${3} | sed 's/\//\\\//g'); # escape forward slashes
	line=`grep -n "$2" $1 | head -n1 | cut -d: -f1`;
	sed -i "/${S1}/,/${S2}/d" $1;
	sed -i "${line}s;^;${4}\n;" $1;
}

# remove_section <file> <begin search string> <end search string>
remove_section() 
{
	S1=$(echo ${2} | sed 's/\//\\\//g'); # escape forward slashes
	S2=$(echo ${3} | sed 's/\//\\\//g'); # escape forward slashes
	sed -i "/${S1}/,/${S2}/d" $1;
}

# insert_line <file> <if search string> <before|after> <line match string> <inserted line>
insert_line() 
{
	if [ -z "$(grep "$2" $1)" ]; then
		case $3 in
			before) offset=0;;
			after) offset=1;;
		esac;

		line=$((`grep -n "$4" $1 | head -n1 | cut -d: -f1` + offset));
		sed -i "${line}s;^;${5}\n;" $1;
	fi;
}

# replace_line <file> <line replace string> <replacement line>
replace_line()
{
	if [ ! -z "$(grep "$2" $1)" ]; then
		line=`grep -n "$2" $1 | head -n1 | cut -d: -f1`;
		sed -i "${line}s;.*;${3};" $1;
	fi;
}

# remove_line <file> <line match string>
remove_line()
{
	if [ ! -z "$(grep "$2" $1)" ]; then
		line=`grep -n "$2" $1 | head -n1 | cut -d: -f1`;
		sed -i "${line}d" $1;
	fi;
}

# prepend_file <file> <if search string> <patch file>
prepend_file()
{
	if [ -z "$(grep "$2" $1)" ]; then
		echo "$(cat $patch/$3 $1)" > $1;
	fi;
}

# insert_file <file> <if search string> <before|after> <line match string> <patch file>
insert_file()
{
	if [ -z "$(grep "$2" $1)" ]; then
		case $3 in
			before) offset=0;;
			after) offset=1;;
		esac;

		line=$((`grep -n "$4" $1 | head -n1 | cut -d: -f1` + offset));
		sed -i "${line}s;^;\n;" $1;
		sed -i "$((line - 1))r $patch/$5" $1;
	fi;
}

# append_file <file> <if search string> <patch file>
append_file()
{
	if [ -z "$(grep "$2" $1)" ]; then
		echo -ne "\n" >> $1;
		cat $patch/$3 >> $1;
		echo -ne "\n" >> $1;
	fi;
}

# replace_file <file> <permissions> <patch file>
replace_file()
{
	cp -pf $patch/$3 $1;
	chmod $2 $1;
}

# patch_fstab <fstab file> <mount match name> <fs match type> <block|mount|fstype|options|flags> <original string> <replacement string>
patch_fstab()
{
	entry=$(grep "$2" $1 | grep "$3");

	if [ -z "$(echo "$entry" | grep "$6")" ]; then
		case $4 in
			block) part=$(echo "$entry" | awk '{ print $1 }');;
			mount) part=$(echo "$entry" | awk '{ print $2 }');;
			fstype) part=$(echo "$entry" | awk '{ print $3 }');;
			options) part=$(echo "$entry" | awk '{ print $4 }');;
			flags) part=$(echo "$entry" | awk '{ print $5 }');;
		esac;

		newentry=$(echo "$entry" | sed "s;${part};${6};");
		sed -i "s;${entry};${newentry};" $1;
	fi;
}

# comment_line <file> <search string>
comment_line()
{
	S1=$(echo ${2} | sed 's/\//\\\//g'); # escape forward slashes
	sed -i "/${S1}/ s/^#*/#/" $1;
}

# comment_line <file> <begin search string> <end search string>
comment_section()
{
	S1=$(echo ${2} | sed 's/\//\\\//g'); # escape forward slashes
	S2=$(echo ${3} | sed 's/\//\\\//g'); # escape forward slashes
	sed -i "/${S1}/,/${S2}/ s/^#*/#/" $1;
}

## end methods


## start of main script

# set up extracted files and directories
ramdisk=/tmp/anykernel/ramdisk;
bin=/tmp/anykernel/tools;
split_img=/tmp/anykernel/split_img;
patch=/tmp/anykernel/patch;

chmod -R 755 $bin;
mkdir -p $ramdisk $split_img;

OUTFD=/proc/self/fd/$1;

# dump current kernel
dump_boot;

############### Ramdisk customization start ###############

# ramdisk changes

############### Ramdisk customization end ###############

# write new kernel
write_boot;
