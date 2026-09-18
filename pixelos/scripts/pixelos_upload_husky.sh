#!/bin/bash
cd ~/pixelos/out/target/product/husky || exit 1
Z=$(ls PixelOS_husky-17.0-*.zip | head -1); [ -n "$Z" ] || { echo NO_ZIP; exit 1; }
cat > /tmp/claude-4392/sf_px_husky.batch <<B
-mkdir /home/frs/project/chiranz/pixelos
-mkdir /home/frs/project/chiranz/pixelos/husky
-mkdir /home/frs/project/chiranz/pixelos/husky/img
cd /home/frs/project/chiranz/pixelos/husky
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
for i in 1 2 3; do sftp -o StrictHostKeyChecking=accept-new -b /tmp/claude-4392/sf_px_husky.batch chiranz@frs.sourceforge.net && { echo "UPLOAD_OK $(date)"; exit 0; }; echo "upload retry $i"; sleep 30; done
echo UPLOAD_FAILED
