#!/bin/bash
Z=~/mistos/out/target/product/shiba/MistOS-5.0-Alpha-17.0-MINI-20260917-1804-shiba-UNOFFICIAL.zip
B=chiranz@frs.sourceforge.net:/home/frs/project/chiranz/shiba
O="-o BatchMode=yes -o ServerAliveInterval=30"
I=/tmp/claude-4392/imgs/shiba1804; rm -rf $I; mkdir -p $I
unzip -o -q -j "$Z" payload.bin -d $I && ~/mistos/out/host/linux-x86/bin/ota_extractor -payload $I/payload.bin -output_dir $I -partitions boot,vendor_boot,vendor_kernel_boot,dtbo >/dev/null 2>&1; rm -f $I/payload.bin
{
scp $O "$Z" $B/ && echo "zip ok" && sftp -o BatchMode=yes -b - chiranz@frs.sourceforge.net <<'SFTP'
rm /home/frs/project/chiranz/shiba/MistOS-5.0-Alpha-17.0-MINI-20260917-1723-shiba-UNOFFICIAL.zip
SFTP
scp $O $I/boot.img $I/vendor_boot.img $I/vendor_kernel_boot.img $I/dtbo.img $B/img/ && echo "imgs ok"
} > /tmp/claude-4392/sf_up_1804.log 2>&1
echo "rc=$?" > /tmp/claude-4392/sf_up_1804.status
