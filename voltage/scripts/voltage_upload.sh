#!/bin/bash
DEV="${1:-shiba}"
cd ~/voltage/out/target/product/$DEV || exit 1
Z=$(ls -t voltage-*.zip 2>/dev/null | grep -v -- "-img.zip" | head -1); [ -n "$Z" ] || { echo NO_ZIP; exit 1; }
md5sum "$Z" > "$Z.md5sum"
cat > /tmp/claude-4392/sf_voltage_$DEV.batch <<B
-mkdir /home/frs/project/chiranz/voltage
-mkdir /home/frs/project/chiranz/voltage/$DEV
-mkdir /home/frs/project/chiranz/voltage/$DEV/img
cd /home/frs/project/chiranz/voltage/$DEV
put $Z
put $Z.md5sum
cd img
put boot.img
put vendor_boot.img
put vendor_kernel_boot.img
put dtbo.img
ls -l
cd ..
ls -l
B
for i in 1 2 3; do sftp -b /tmp/claude-4392/sf_voltage_$DEV.batch chiranz@frs.sourceforge.net && { echo "UPLOAD_OK $(date)"; exit 0; }; echo "retry $i"; sleep 30; done
echo UPLOAD_FAILED
