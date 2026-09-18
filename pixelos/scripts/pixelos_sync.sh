#!/bin/bash
cd ~/pixelos || exit 1
export GIT_LFS_SKIP_SMUDGE=0
echo "=== init $(date)"
repo init -u https://github.com/PixelOS-AOSP/android_manifest.git -b seventeen --git-lfs --depth=1 --no-repo-verify </dev/null || { echo INIT_FAILED; exit 1; }
echo "=== sync $(date)"
for i in 1 2 3 4; do
  repo sync -c --no-clone-bundle --no-tags -j24 --optimized-fetch --prune --force-sync </dev/null && { echo "SYNC_OK $(date)"; exit 0; }
  echo "=== sync retry $i failed $(date)"; sleep 30
done
echo SYNC_FAILED; exit 1
