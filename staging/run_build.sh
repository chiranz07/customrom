#!/usr/bin/env bash
# Infinity-X shiba build. Run detached; logs to build.log.
# NOTE: do NOT use `set -u` — AOSP build/envsetup.sh relies on unset vars.
cd /home/chiranz/infinityx || exit 99

# Strip the harness grep/find shell-function wrappers that break AOSP lunch.
unset -f grep find 2>/dev/null || true

source build/envsetup.sh
unset -f grep find 2>/dev/null || true   # re-strip in case envsetup re-sourced a profile

# ccache (helps subsequent retries; cold cache is cheap to set up)
export USE_CCACHE=1
export CCACHE_DIR=/home/chiranz/infinityx/.ccache
ccache -M 50G >/dev/null 2>&1 || true

# Build flags
export INFINITY_MAINTAINER=chiranz
export WITH_GAPPS=false

lunch infinity_shiba-userdebug || { echo "LUNCH FAILED"; echo "BUILD DONE rc=90"; exit 90; }
echo "=== BUILD START  product=$TARGET_PRODUCT variant=$TARGET_BUILD_VARIANT device=$TARGET_DEVICE ==="

m bacon -j96
rc=$?

echo "=== BUILD DONE rc=$rc ==="
if [ $rc -eq 0 ]; then
  echo "=== output zip(s): ==="
  find out/target/product -maxdepth 2 -name "*.zip" -newermt "-6 hours" 2>/dev/null
fi
echo "BUILD_FINAL_RC=$rc"
