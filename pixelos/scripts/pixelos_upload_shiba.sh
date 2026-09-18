#!/bin/bash
cd ~/pixelos/out/target/product/shiba || exit 1
cat > /tmp/claude-4392/sf_px_shiba.batch <<'B'
-mkdir /home/frs/project/chiranz/pixelos
-mkdir /home/frs/project/chiranz/pixelos/shiba
-mkdir /home/frs/project/chiranz/pixelos/shiba/img
cd /home/frs/project/chiranz/pixelos/shiba
put PixelOS_shiba-17.0-20260918-0417.zip
put PixelOS_shiba-17.0-20260918-0417.zip.md5sum
cd img
put boot.img
put vendor_boot.img
put vendor_kernel_boot.img
put dtbo.img
ls -l
cd ..
ls -l
B
for i in 1 2 3; do sftp -o StrictHostKeyChecking=accept-new -b /tmp/claude-4392/sf_px_shiba.batch chiranz@frs.sourceforge.net && { echo "UPLOAD_OK $(date)"; exit 0; }; echo "upload retry $i"; sleep 30; done
echo UPLOAD_FAILED
