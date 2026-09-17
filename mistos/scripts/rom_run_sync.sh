#!/usr/bin/env bash
cd /home/chiranz814/mistos || exit 99
MAX=10
n=0
while :; do
  n=$((n+1))
  echo "================ SYNC ATTEMPT $n/$MAX  $(date) ================"
  repo sync -c --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync -j16
  rc=$?
  if [ $rc -eq 0 ]; then
    echo "================ SYNC COMPLETE (attempt $n) ================"
    break
  fi
  if [ $n -ge $MAX ]; then
    echo "================ SYNC GAVE UP after $n attempts (rc=$rc) ================"
    break
  fi
  echo "---- attempt $n failed (rc=$rc); resuming in 30s ----"
  sleep 30
done
echo "SYNC_FINAL_RC=$rc"
