#!/usr/bin/env bash
# Resilient repo sync for Infinity-X / shiba. Resumable; retries on transient failures.
set -u
cd /home/chiranz/infinityx || exit 99

MAX=8
n=0
while :; do
  n=$((n+1))
  echo "================ SYNC ATTEMPT $n/$MAX  ================"
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
echo "FINAL_RC=$rc"
