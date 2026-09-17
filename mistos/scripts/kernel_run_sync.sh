#!/usr/bin/env bash
cd /home/chiranz814/kernel || exit 99
MAX=10
n=0
while :; do
  n=$((n+1))
  echo "================ KERNEL SYNC ATTEMPT $n/$MAX  $(date) ================"
  repo sync -c --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync -j16
  rc=$?
  if [ $rc -eq 0 ]; then
    echo "================ KERNEL SYNC COMPLETE (attempt $n) ================"
    break
  fi
  if [ $n -ge $MAX ]; then
    echo "================ KERNEL SYNC GAVE UP after $n attempts (rc=$rc) ================"
    break
  fi
  echo "---- attempt $n failed (rc=$rc); resuming in 30s ----"
  sleep 30
done
echo "KERNEL_SYNC_FINAL_RC=$rc"
