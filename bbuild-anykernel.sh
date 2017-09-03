#!/bin/bash

# KAWORI Kernel Universal Build Script
#
# Version 1.3, 11.10.2016
#
# (C) Lord Boeffla (aka andip71) Aviraxp

#######################################
# Parameters to be configured manually
#######################################

KAWORI_VERSION="TEST"

TOOLCHAIN="/home/wanghan/gcc/bin/aarch64-linux-android-"
ARCHITECTURE=arm64
COMPILER_FLAGS_KERNEL=""
COMPILER_FLAGS_MODULE=""

KERNEL_IMAGE="Image.gz-dtb"
COMPILE_DTB="n"
DTBTOOL=""
DTBTOOL_CMD=""
MODULES_IN_SYSTEM="y"
OUTPUT_FOLDER=""

DEFCONFIG="kawori_defconfig"
DEFCONFIG_VARIANT=""

KERNEL_NAME="Kawori-Kernel"

FINISH_MAIL_TO=""

SMB_SHARE_KERNEL=""
SMB_FOLDER_KERNEL=""
SMB_AUTH_KERNEL=""

SMB_SHARE_BACKUP=""
SMB_FOLDER_BACKUP=""
SMB_AUTH_BACKUP=""

NUM_CPUS=""   # number of cpu cores used for build (leave empty for auto detection)

#######################################
# automatic parameters, do not touch !
#######################################

COLOR_RED="\033[0;31m"
COLOR_GREEN="\033[1;32m"
COLOR_NEUTRAL="\033[0m"

SOURCE_PATH=$PWD
cd ..
ROOT_PATH=$PWD
ROOT_DIR_NAME=`basename "$PWD"`
cd $SOURCE_PATH

BUILD_PATH="$ROOT_PATH/build"
REPACK_PATH="$ROOT_PATH/repack"

KAWORI_DATE=$(date +%Y%m%d)
GIT_BRANCH=`git symbolic-ref --short HEAD`

if [ -z "$NUM_CPUS" ]; then
	NUM_CPUS=`grep -c ^processor /proc/cpuinfo`
fi

# overwrite settings with repo specific custom file, if it exists
if [ -f $ROOT_PATH/x-settings.sh ]; then
	. $ROOT_PATH/x-settings.sh
fi

# overwrite settings with user specific custom file, if it exists
if [ -f ~/x-settings.sh ]; then
	. ~/x-settings.sh
fi

KAWORI_FILENAME="${KERNEL_NAME,,}-$KAWORI_VERSION"

# set environment
export ARCH=$ARCHITECTURE
export CROSS_COMPILE="${CCACHE} $TOOLCHAIN"


#####################
# internal functions
#####################

step0_copy_code()
{
	echo -e $COLOR_GREEN"\n0 - copy code\n"$COLOR_NEUTRAL

	# remove old build folder and create empty one
	rm -r -f $BUILD_PATH
	mkdir $BUILD_PATH

	# copy code from source folder to build folder
	# (usage of * prevents .git folder to be copied)
	cp -r $SOURCE_PATH/* $BUILD_PATH

	# Replace version information in mkcompile_h with the one from x-settings.sh
	sed "s/\`echo \$LINUX_COMPILE_BY | \$UTS_TRUNCATE\`/$KERNEL_NAME-$KAWORI_VERSION-$KAWORI_DATE/g" -i $BUILD_PATH/scripts/mkcompile_h
	sed "s/\`echo \$LINUX_COMPILE_HOST | \$UTS_TRUNCATE\`/aviraxp/g" -i $BUILD_PATH/scripts/mkcompile_h
}

step1_make_clean()
{
	echo -e $COLOR_GREEN"\n1 - make clean\n"$COLOR_NEUTRAL

	# jump to build path and make clean
	cd $BUILD_PATH
	make clean
}

step2_make_config()
{
	echo -e $COLOR_GREEN"\n2 - make config\n"$COLOR_NEUTRAL
	echo

	# build make string depending on if we need to compile to an output folder
	# and if we need to have a defconfig variant
	MAKESTRING="arch=$ARCHITECTURE $DEFCONFIG"

	if [ ! -z "$OUTPUT_FOLDER" ]; then
		rm -rf $BUILD_PATH/output
		mkdir $BUILD_PATH/output
		MAKESTRING="O=$OUTPUT_FOLDER $MAKESTRING"
	fi

	if [ ! -z "$DEFCONFIG_VARIANT" ]; then
		MAKESTRING="$MAKESTRING VARIANT_DEFCONFIG=$DEFCONFIG_VARIANT"
	fi

	# jump to build path and make config
	cd $BUILD_PATH
	echo "Makestring: $MAKESTRING"
	make $MAKESTRING
}

step3_compile()
{
	echo -e $COLOR_GREEN"\n3 - compile\n"$COLOR_NEUTRAL

	TIMESTAMP1=$(date +%s)

	# jump to build path
	cd $BUILD_PATH

	# compile source
	if [ -z "$OUTPUT_FOLDER" ]; then
		make -j$NUM_CPUS CFLAGS_KERNEL="$COMPILER_FLAGS_KERNEL" CFLAGS_MODULE="$COMPILER_FLAGS_MODULE" 2>&1 |tee ../compile.log
	else
		make -j$NUM_CPUS O=$OUTPUT_FOLDER CFLAGS_KERNEL="$COMPILER_FLAGS_KERNEL" CFLAGS_MODULE="$COMPILER_FLAGS_MODULE" 2>&1 |tee ../compile.log
	fi

	# compile dtb if required
	if [ "y" == "$COMPILE_DTB" ]; then
		echo -e ">>> compiling DTB\n"
		echo

		# Compile dtb (device tree blob) file
		if [ -f $BUILD_PATH/$OUTPUT_FOLDER/arch/$ARCHITECTURE/boot/dt.img ]; then
			rm $BUILD_PATH/$OUTPUT_FOLDER/arch/$ARCHITECTURE/boot/dt.img
		fi

		chmod 777 tools_kawori/$DTBTOOL
		tools_kawori/$DTBTOOL $DTBTOOL_CMD -o $BUILD_PATH/$OUTPUT_FOLDER/arch/$ARCHITECTURE/boot/dt.img -s 2048 -p $BUILD_PATH/$OUTPUT_FOLDER/scripts/dtc/ $BUILD_PATH/$OUTPUT_FOLDER/arch/$ARCHITECTURE/boot/
	fi

	TIMESTAMP2=$(date +%s)

	# Log compile time (screen output)
	echo "compile time:" $(($TIMESTAMP2 - $TIMESTAMP1)) "seconds"
	echo "Kernel image size (bytes):"
	stat -c%s $BUILD_PATH/$OUTPUT_FOLDER/arch/$ARCHITECTURE/boot/$KERNEL_IMAGE

	# Log compile time and parameters (log file output)
	echo -e "\n***************************************************" >> ../compile.log
	echo -e "\ncompile time:" $(($TIMESTAMP2 - $TIMESTAMP1)) "seconds" >> ../compile.log
	echo "Kernel image size (bytes):" >> ../compile.log
	stat -c%s $BUILD_PATH/$OUTPUT_FOLDER/arch/$ARCHITECTURE/boot/$KERNEL_IMAGE >> ../compile.log

	echo -e "\n***************************************************" >> ../compile.log
	echo -e "\nroot path:" $ROOT_PATH >> ../compile.log
	echo "toolchain compile:" >> ../compile.log
	grep "^CROSS_COMPILE" $BUILD_PATH/Makefile >> ../compile.log
	echo "toolchain stripping:" $TOOLCHAIN >> ../compile.log
}

step4_prepare_anykernel()
{
	echo -e $COLOR_GREEN"\n4 - prepare anykernel\n"$COLOR_NEUTRAL

	# Cleanup folder if still existing
	echo -e ">>> cleanup repack folder\n"
	{
		rm -r -f $REPACK_PATH
		mkdir -p $REPACK_PATH
	} 2>/dev/null

	# copy anykernel template over
	cd $REPACK_PATH
	cp -R $BUILD_PATH/anykernel/* .

	# delete placeholder files
	find . -name placeholder -delete

	# copy kernel image
	cp $BUILD_PATH/$OUTPUT_FOLDER/arch/$ARCHITECTURE/boot/$KERNEL_IMAGE $REPACK_PATH/zImage

	{
		# copy dtb (if we have one)
		if [ "y" == "$COMPILE_DTB" ]; then
			cp $BUILD_PATH/$OUTPUT_FOLDER/arch/$ARCHITECTURE/boot/dt.img $REPACK_PATH/dtb
		fi

		# copy modules to either modules folder (CM and derivates) or directly in ramdisk (Samsung stock)
		if [ "y" == "$MODULES_IN_SYSTEM" ]; then
			MODULES_PATH=$REPACK_PATH/modules
		else
			MODULES_PATH=$REPACK_PATH/ramdisk/lib/modules
		fi

		mkdir -p $MODULES_PATH

		# copy generated modules
		find $BUILD_PATH -name '*.ko' -exec cp -av {} $MODULES_PATH \;

		# copy static modules and rename from ko_ to ko, only if there are some
		if [ "$(ls -A $BUILD_PATH/modules_KAWORI)" ]; then
			cp $BUILD_PATH/modules_KAWORI/* $MODULES_PATH
			cd $MODULES_PATH
			for i in *.ko_; do mv $i ${i%ko_}ko; echo Static module: ${i%ko_}ko; done
		fi

		# set module permissions
		chmod 644 $MODULES_PATH/*

		# strip modules
		echo -e ">>> strip modules\n"
		${TOOLCHAIN}strip --strip-unneeded $MODULES_PATH/*

	} 2>/dev/null

	# replace variables in anykernel script
	cd $REPACK_PATH
	KERNELNAME="Flashing $KERNEL_NAME $KAWORI_VERSION"
	sed -i "s;###kernelname###;${KERNELNAME};" META-INF/com/google/android/update-binary;
	COPYRIGHT="(c) Lord Boeffla (aka andip71), Aviraxp, $(date +%Y.%m.%d-%H:%M:%S)"
	sed -i "s;###copyright###;${COPYRIGHT};" META-INF/com/google/android/update-binary;
}

step5_create_anykernel_zip()
{
	echo -e $COLOR_GREEN"\n5 - create anykernel zip\n"$COLOR_NEUTRAL

	# Creating recovery flashable zip
	echo -e ">>> create flashable zip\n"

	# create zip file
	cd $REPACK_PATH
	zip -r9 $KAWORI_FILENAME.recovery.zip * -x $KAWORI_FILENAME.recovery.zip

	# sign recovery zip if there are keys available
	if [ -f "$BUILD_PATH/tools_KAWORI/testkey.x509.pem" ]; then
		echo -e ">>> signing recovery zip\n"
		java -jar $BUILD_PATH/tools_KAWORI/signapk.jar -w $BUILD_PATH/tools_KAWORI/testkey.x509.pem $BUILD_PATH/tools_KAWORI/testkey.pk8 $KAWORI_FILENAME.recovery.zip $KAWORI_FILENAME.recovery.zip_signed
		cp $KAWORI_FILENAME.recovery.zip_signed $KAWORI_FILENAME.recovery.zip
		rm $KAWORI_FILENAME.recovery.zip_signed
	fi

	md5sum $KAWORI_FILENAME.recovery.zip > $KAWORI_FILENAME.recovery.zip.md5

	# Creating additional files for load&flash
	echo -e ">>> create load&flash files\n"

	cp $KAWORI_FILENAME.recovery.zip cm-kernel.zip
	md5sum cm-kernel.zip > checksum
}

step7_analyse_log()
{
	echo -e $COLOR_GREEN"\n7 - analyse log\n"$COLOR_NEUTRAL

	# Check compile result and patch file success
	echo -e "\n***************************************************"
	echo -e "Check for compile errors:"

	cd $ROOT_PATH
	echo -e $COLOR_RED
	grep " error" compile.log
	grep "forbidden warning" compile.log
	echo -e $COLOR_NEUTRAL

	echo -e "***************************************************"
}

step8_transfer_kernel()
{
	echo -e $COLOR_GREEN"\n8 - transfer kernel\n"$COLOR_NEUTRAL

	# transfer only if SMB share configured
	if [ ! -z "$SMB_SHARE_KERNEL" ]; then
		smbclient $SMB_SHARE_KERNEL -U $SMB_AUTH_KERNEL -c "mkdir $SMB_FOLDER_KERNEL\\$KAWORI_VERSION"
		smbclient $SMB_SHARE_KERNEL -U $SMB_AUTH_KERNEL -c "put $REPACK_PATH/$KAWORI_FILENAME.recovery.zip $SMB_FOLDER_KERNEL\\$KAWORI_VERSION\\$KAWORI_FILENAME.recovery.zip"
		smbclient $SMB_SHARE_KERNEL -U $SMB_AUTH_KERNEL -c "put $REPACK_PATH/$KAWORI_FILENAME.recovery.zip.md5 $SMB_FOLDER_KERNEL\\$KAWORI_VERSION\\$KAWORI_FILENAME.recovery.zip.md5"
		smbclient $SMB_SHARE_KERNEL -U $SMB_AUTH_KERNEL -c "put $REPACK_PATH/checksum $SMB_FOLDER_KERNEL\\$KAWORI_VERSION\\checksum"
		smbclient $SMB_SHARE_KERNEL -U $SMB_AUTH_KERNEL -c "put $REPACK_PATH/cm-kernel.zip $SMB_FOLDER_KERNEL\\$KAWORI_VERSION\\cm-kernel.zip"
		return
	fi

	# transfer only if ssh ftp configured
	if [ ! -z "$SSH_FTP_REMOTE" ]; then
		rm -rf ~/bbuild_transfer
		mkdir ~/bbuild_transfer
		echo "$SSH_FTP_PW" | sshfs "$SSH_FTP_REMOTE" ~/bbuild_transfer -p "$SSH_FTP_PORT" -o password_stdin
		mkdir -p ~/bbuild_transfer/$KAWORI_VERSION

		cp $REPACK_PATH/$KAWORI_FILENAME.recovery.zip ~/bbuild_transfer/$KAWORI_VERSION
		cp $REPACK_PATH/$KAWORI_FILENAME.recovery.zip.md5 ~/bbuild_transfer/$KAWORI_VERSION
		cp $REPACK_PATH/checksum ~/bbuild_transfer/$KAWORI_VERSION
		cp $REPACK_PATH/cm-kernel.zip ~/bbuild_transfer/$KAWORI_VERSION

		sync
		sleep 1
		fusermount -u ~/bbuild_transfer
		rm -rf ~/bbuild_transfer
		return
	fi

	echo -e "No kernel smb share or ssh ftp configured, not transfering files.\n"
}

step9_send_finished_mail()
{
	echo -e $COLOR_GREEN"\n9 - send finish mail\n"$COLOR_NEUTRAL

	# send a mail to inform about finished compilation
	if [ -z "$FINISH_MAIL_TO" ]; then
		echo -e "No mail address configured, not sending mail.\n"	
	else
		cat $ROOT_PATH/compile.log | /usr/bin/mailx -s "Compilation for $KERNEL_NAME $KAWORI_VERSION finished!!!" $FINISH_MAIL_TO
	fi
}

stepR_rewrite_config()
{
	echo -e $COLOR_GREEN"\nr - rewrite config\n"$COLOR_NEUTRAL

	# copy defconfig, run make oldconfig and copy it back
	cd $SOURCE_PATH
	cp arch/$ARCHITECTURE/configs/$DEFCONFIG .config
	make oldconfig
	cp .config arch/$ARCHITECTURE/configs/$DEFCONFIG
	make mrproper

	# commit change
	git add arch/$ARCHITECTURE/configs/$DEFCONFIG
	git commit
}

stepC_cleanup()
{
	echo -e $COLOR_GREEN"\nc - cleanup\n"$COLOR_NEUTRAL

	# remove old build and repack folders, remove any logs
	{
		rm -r -f $BUILD_PATH
		rm -r -f $REPACK_PATH
		rm $ROOT_PATH/*.log
	} 2>/dev/null
}

stepB_backup()
{
	echo -e $COLOR_GREEN"\nb - backup\n"$COLOR_NEUTRAL

	# Create a tar backup in parent folder, gzip it and copy to verlies
	BACKUP_FILE="$ROOT_DIR_NAME""_$(date +"%Y-%m-%d_%H-%M").tar.gz"

	cd $ROOT_PATH
	tar cvfz $BACKUP_FILE source x-settings.sh
	cd $SOURCE_PATH

	# transfer backup only if smbshare configured
	if [ -z "$SMB_SHARE_BACKUP" ]; then
		echo -e "No backup smb share configured, not transfering backup.\n"
	else
		# copy backup to a SMB network storage and delete backup afterwards
		smbclient $SMB_SHARE_BACKUP -U $SMB_AUTH_BACKUP -c "put $ROOT_PATH/$BACKUP_FILE $SMB_FOLDER_BACKUP\\$BACKUP_FILE"
		rm $ROOT_PATH/$BACKUP_FILE
	fi
}

display_help()
{
	echo
	echo
	echo "Function menu (anykernel version)"
	echo "======================================================================"
	echo
	echo "0  = copy code         |  5  = create anykernel"
	echo "1  = make clean        |  "
	echo "2  = make config       |  7  = analyse log"
	echo "3  = compile           |  8  = transfer kernel"
	echo "4  = prepare anykernel |  9  = send finish mail"
	echo
	echo "rel = all, execute steps 0-9 - without CCACHE  |  r = rewrite config"
	echo "a   = all, execute steps 0-9                   |  c = cleanup"
	echo "u   = upd, execute steps 3-9                   |  b = backup"
	echo "ur  = upd, execute steps 5-9                   |"
	echo
	echo "======================================================================"
	echo
	echo "Parameters:"
	echo
	echo "  KAWORI version: $KAWORI_VERSION"
	echo "  KAWORI date:    $KAWORI_DATE"
	echo "  Kernel name:     $KERNEL_NAME"
	echo "  Git branch:      $GIT_BRANCH"
	echo "  CPU Cores:       $NUM_CPUS"
	echo
	echo "  Toolchain:       $TOOLCHAIN"
	echo "  Root path:       $ROOT_PATH"
	echo "  Root dir:        $ROOT_DIR_NAME"
	echo "  Source path:     $SOURCE_PATH"
	echo "  Build path:      $BUILD_PATH"
	echo "  Repack path:     $REPACK_PATH"
	echo "  Kernel Filename: $KAWORI_FILENAME"
	echo
	echo "======================================================================"
}


################
# main function
################

unset CCACHE_DISABLE

case "$1" in
	rel)
		export CCACHE_DISABLE=1
		step0_copy_code
		step1_make_clean
		step2_make_config
		step3_compile
		step4_prepare_anykernel
		step5_create_anykernel_zip
		step7_analyse_log
		step8_transfer_kernel
		step9_send_finished_mail
		;;
	a)
		step0_copy_code
		step1_make_clean
		step2_make_config
		step3_compile
		step4_prepare_anykernel
		step5_create_anykernel_zip
		step7_analyse_log
		step8_transfer_kernel
		step9_send_finished_mail
		;;
	u)
		step3_compile
		step4_prepare_anykernel
		step5_create_anykernel_zip
		step7_analyse_log
		step8_transfer_kernel
		step9_send_finished_mail
		;;
	ur)
		step5_create_anykernel_zip
		step7_analyse_log
		step8_transfer_kernel
		step9_send_finished_mail
		;;
	0)
		step0_copy_code
		;;
	1)
		step1_make_clean
		;;
	2)
		step2_make_config
		;;
	3)
		step3_compile
		;;
	4)
		step4_prepare_anykernel
		;;
	5)
		step5_create_anykernel_zip
		;;
	6)
		# do nothing
		;;
	7)
		step7_analyse_log
		;;
	8)
		step8_transfer_kernel
		;;
	9)
		step9_send_finished_mail
		;;
	b)
		stepB_backup
		;;
	c)
		stepC_cleanup
		;;
	r)
		stepR_rewrite_config
		;;

	*)
		display_help
		;;
esac
