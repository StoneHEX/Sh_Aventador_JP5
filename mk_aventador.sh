#!/bin/bash

HERE=`pwd`
set_commonvars()
{
	LOGDIR=${HERE}/Logs
	[ ! -d ${LOGDIR} ] && mkdir ${LOGDIR} 
	DTB_DIR=${BOARD}_dtb
	[ ! -d ${DTB_DIR} ] && mkdir ${DTB_DIR} 
	. ./aventador_common.config
}

set_nanovars()
{
	. ./aventador-nano.config
}

set_xaviervars()
{
	. ./aventador-xavier.config
}


exit_error()
{
	echo "Error on step $1"
	exit -1
}

usage()
{
        echo "Usage: $0 -o [<kernel> <modules> <dtbs> <all> <cleanup>] -b [<nano> <xavier>]" 1>&2;
        exit 1;
}


check_for_sources()
{
	cd ${HERE}
	if [ ! -d ${SH_SOURCES} ]; then
		git clone  ${SH_GIT_SOURCES}
	fi
	if [ ! -d ${CROSS_COMPILER} ]; then
		if [ ! -f aarch64--glibc--stable-final.tar.gz ]; then
			echo "Please download the compiler from https://developer.nvidia.com/embedded/jetson-linux, look for \"Bootlin Toolchain gcc 9.3 \""
			exit 0
		fi
		echo -n "Extrating ${CROSS_COMPILER_ARCHIVE}..."
		mkdir ${CROSS_COMPILER}
		tar -xf ${CROSS_COMPILER_ARCHIVE} -C ${CROSS_COMPILER}
		echo " Done"
	fi
}

set_environment_vars()
{
	echo "KERNEL_SOURCES=${HERE}/${SH_SOURCES}" > ${BOARD}.env
	echo "TOOLCHAIN_PREFIX=${TOOLCHAIN_PREFIX}" >> ${BOARD}.env
	echo "PROCESSORS=16" >> ${BOARD}.env
	echo "TEGRA_KERNEL_OUT=${TEGRA_KERNEL_OUT}" >> ${BOARD}.env
	echo "JETPACK=${JETPACK}" >> ${BOARD}.env
	echo "JETPACK_ROOTFS=${JETPACK_ROOTFS}" >> ${BOARD}.env
	echo "DTB_FILE=${DTB_FILE}" >> ${BOARD}.env
	echo "DTB_FULL_PATH=${HERE}/${DTB_DIR}/${DTB_FILE}" >> ${BOARD}.env
	echo "DTSI_FOLDER=${HERE}/dtsi/${BOARD}">> ${BOARD}.env
	echo "SOURCE_PINMUX=${SOURCE_PINMUX}"  >> ${BOARD}.env
	echo "SOURCE_GPIO=${SOURCE_GPIO}"  >> ${BOARD}.env
	echo "SOURCE_PADV=${SOURCE_PADV}"  >> ${BOARD}.env
	. ./${BOARD}.env
}

setup_nano_dtbs()
{
	cd ${HERE}
	if [ ! -d nano_dtb ]; then
		mkdir nano_dtb
	fi
	cp ${DTSI_FOLDER}/${SOURCE_PINMUX} ${HERE}/${SH_SOURCES}/hardware/nvidia/platform/t210/porg/kernel-dts/porg-platforms/tegra210-aventador-0000-pinmux-p3448-0002-b00.dtsi
	cp ${DTSI_FOLDER}/${SOURCE_GPIO} ${HERE}/${SH_SOURCES}/hardware/nvidia/platform/t210/porg/kernel-dts/porg-platforms/tegra210-aventador-0000-gpio-p3448-0002-b00.dtsi
}

setup_xavier_dtbs()
{
	cd ${HERE}
	if [ ! -d xavier_dtb ]; then
		mkdir xavier_dtb
	fi
	cp ${DTSI_FOLDER}/${SOURCE_PINMUX} ${PINMUX_EXE_XAVIER}/.
	cp ${DTSI_FOLDER}/${SOURCE_GPIO} ${PINMUX_EXE_XAVIER}/.
	cp ${DTSI_FOLDER}/${SOURCE_PADV} ${PINMUX_EXE_XAVIER}/.
	cd ${PINMUX_EXE_XAVIER}
	echo "Running pimnux from ${SOURCE_PINMUX} and ${SOURCE_GPIO}"

	python pinmux-dts2cfg.py \
		--pinmux                                        \
		addr_info.txt gpio_addr_info.txt por_val.txt    \
		${SOURCE_PINMUX}                                \
		${SOURCE_GPIO}                                  \
		1.0                                             \
	> ${JETPACK}/bootloader/t186ref/BCT/tegra19x-mb1-pinmux-p3668-a01.cfg

	echo "Running padvoltage from ${SOURCE_PADV}"
	python pinmux-dts2cfg.py --pad pad_info.txt ${SOURCE_PADV}  1.0 > ${JETPACK}/bootloader/t186ref/BCT/tegra19x-mb1-padvoltage-p3668-a01.cfg
	cd ${HERE}
}

build()
{
	setup_${BOARD}_dtbs
	cd ${KERNEL_SOURCES}
	#STEPS="tegra_defconfig zImage modules dtbs modules_install"
	for i in ${STEPS}; do
		echo "Running $i"
		echo $TEGRA_KERNEL_OUT
		echo $JETPACK_ROOTFS
		if [ "$i" == "modules_install" ]; then
			sudo make -C kernel/kernel-4.9/ ARCH=arm64 O=$TEGRA_KERNEL_OUT LOCALVERSION=-tegra INSTALL_MOD_PATH=$JETPACK_ROOTFS CROSS_COMPILE=${TOOLCHAIN_PREFIX} -j${PROCESSORS} --output-sync=target $i > ${LOGDIR}/log.$i 2>&1
		else
			make -C kernel/kernel-4.9/ ARCH=arm64 O=$TEGRA_KERNEL_OUT LOCALVERSION=-tegra CROSS_COMPILE=${TOOLCHAIN_PREFIX} -j${PROCESSORS} --output-sync=target $i > ${LOGDIR}/log.$i 2>&1
		fi
		if [ ! "$?" == 0 ]; then
			exit_error $i
		fi
	done
	cd ${HERE}
}

copy_results()
{
	cd ${JETPACK}
	# Copy device tree generated
	echo "Copying ${DTB_FILE} to ${BOARD} sdk"
	cp ${TEGRA_KERNEL_OUT}/arch/arm64/boot/Image kernel/
	cp ${TEGRA_KERNEL_OUT}/arch/arm64/boot/dts/${DTB_FILE} kernel/dtb/
	echo "Copying to ${BOARD}_dtb folder"
	cp ${TEGRA_KERNEL_OUT}/arch/arm64/boot/dts/${DTB_FILE} ${DTB_FULL_PATH}
}

# MAIN
while getopts ":b::o:" opts; do
        case "${opts}" in
                o)
                        OPTIONS="1"
                        case "${OPTARG}" in
                                kernel)
                                        STEPS="tegra_defconfig zImage"
                                        ;;
                                modules)
                                        STEPS="tegra_defconfig modules modules_install"
                                        ;;
                                dtbs)
                                        STEPS="tegra_defconfig dtbs"
                                        ;;
                                all)
                                        STEPS="tegra_defconfig zImage modules dtbs modules_install"
                                        ;;
                                cleanup)
                                        STEPS="distclean mrproper"
                                        ;;
                                *)
                                        echo "Invalid ops ${OPTARG}"
                                        usage
                                        ;;
                        esac
                        ;;
		b)
			BOARD=${OPTARG}
			case "${BOARD}" in
				nano)
					set_commonvars
					set_nanovars
					;;
				xavier)
					set_commonvars
					set_xaviervars
					;;
				*)
					usage
					;;
			esac
                        ;;
		*)
                        usage
                        ;;
        esac
done
if [ -z "${OPTIONS}" ]; then
    usage
fi
if [ -z "${BOARD}" ]; then
    usage
fi

echo "Running on ${BOARD}"
check_for_sources
exit
set_environment_vars
build
copy_results

