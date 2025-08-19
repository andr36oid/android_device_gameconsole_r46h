#/bin/bash

LINEAGEVERSION=lineage-18.1
DATE=`date -u +%Y%m%d`
TIME=`date -u +%H%M`
DEVICE=r50s-android
IMGNAME=$LINEAGEVERSION-$DATE-$TIME-$DEVICE.img
IMGSIZE=3
OUTDIR=${ANDROID_PRODUCT_OUT:="../../../out/target/product/r50s"}

if [ `id -u` != 0 ]; then
	echo "Must be root to run script!"
	exit
fi

if [ -f $IMGNAME ]; then
	echo "File $IMGNAME already exists!"
else
    echo "Copying over kernel files"
    cp $OUTDIR/obj/KERNEL_OBJ/arch/arm64/boot/Image BOOT/
	cp ../common/resizing/prebuilt/Image-resizing BOOT/
	cp $OUTDIR/obj/KERNEL_OBJ/arch/arm64/boot/dts/rockchip/rk3326-$DEVICE.dtb BOOT/rk3326-r50s-android.dtb
    cp $OUTDIR/obj/KERNEL_OBJ/arch/arm64/boot/dts/rockchip/rk3326-$DEVICE.dtb BOOT/rk3326-rg351p.dtb
	echo "Creating image file $IMGNAME..."
	dd if=/dev/zero of=$IMGNAME bs=1M count=$(echo "$IMGSIZE*1024" | bc)
	sync
	echo "Creating partitions..."
	# Make the disk MBR type (msdos)
	parted $IMGNAME mktable msdos

	# Copy u-boot data (skip the first sector because it is MBR data)
	sudo dd if=bootloader/idbloader.img of=$IMGNAME conv=fsync bs=512 seek=64
	sudo dd if=bootloader/uboot.img of=$IMGNAME conv=fsync bs=512 seek=16384
	sudo dd if=bootloader/trust.img of=$IMGNAME conv=fsync bs=512 seek=24576

	# Making BOOT partitions (size 1081344 sector - 32768 sector = 1048576  sectors * 512 = 512MiB)
	parted -s $IMGNAME mkpart primary fat32 32768s 1081343s
    # Set boot flag
    parted -s $IMGNAME set 1 boot on
	# Making rootfs partitions (size 1Gi)
	parted -s $IMGNAME mkpart primary ext4 1081344s 5701008s
	parted -s $IMGNAME mkpart primary ext4 5701009s 100%
	# Verify
	parted $IMGNAME print
	sync
	LOOPDEV=`kpartx -av $IMGNAME | awk 'NR==1{ sub(/p[0-9]$/, "", $3); print $3 }'`
	sync
	if [ -z "$LOOPDEV" ]; then
		echo "Unable to find loop device!"
		kpartx -d $IMGNAME
		exit
	fi
	echo "Image mounted as $LOOPDEV"
	sleep 5
	mkfs.fat -F 32 /dev/mapper/${LOOPDEV}p1 -n BOOT
	mkfs.ext4 /dev/mapper/${LOOPDEV}p2 -L system
	mkfs.ext4 /dev/mapper/${LOOPDEV}p3 -L userdata
	echo "Copying system..."
	dd if=$OUTDIR/system.img of=/dev/mapper/${LOOPDEV}p2 bs=1M
	echo "Copying BOOT..."
	mkdir -p sdcard/BOOT
	sync
	mount /dev/mapper/${LOOPDEV}p1 sdcard/BOOT
	sync
	cp -R BOOT/* sdcard/BOOT
	sync
	umount /dev/mapper/${LOOPDEV}p1
	rm -rf sdcard
	kpartx -d $IMGNAME
	sync
	echo "Done, created $IMGNAME!"
    echo "Cleanup..."
    rm BOOT/Image*
    rm BOOT/rk3326-*.dtb
	parted -s $IMGNAME mkpart primary ext2 0% 32767s
	parted -s $IMGNAME set 4 hidden on
	parted -s $IMGNAME rm 3
	zip -r $IMGNAME.zip $IMGNAME
fi
