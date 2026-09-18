#!/bin/bash
# Self-relaunching supervisor for the PixelOS shiba build (shared, overloaded server).
cd ~/pixelos || exit 1
JOBS="${1:-96}"
MAX_ATTEMPTS=50
ATTEMPT=0
while [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; do
    ATTEMPT=$((ATTEMPT + 1))
    LOGFILE=~/pixelos_attempt${ATTEMPT}.log
    echo "=== [$(date)] Attempt $ATTEMPT (jobs=$JOBS) -> $LOGFILE ==="
    for i in $(seq 1 30); do
        AVAIL_MB=$(free -m | awk '/^Mem:/{print $7}')
        [ "$AVAIL_MB" -gt 8000 ] && break
        echo "  memory tight (${AVAIL_MB}MB available), waiting..."; sleep 20
    done
    bash -c "source build/envsetup.sh > ~/pixelos_envsetup_attempt${ATTEMPT}.log 2>&1 && lunch lineage_shiba-cp2a-userdebug > ~/pixelos_lunch_attempt${ATTEMPT}.log 2>&1 && m pixelos -j${JOBS}" > "$LOGFILE" 2>&1
    RC=$?
    echo "=== [$(date)] Attempt $ATTEMPT exited rc=$RC ===" >> "$LOGFILE"
    if [ "$RC" -eq 0 ]; then echo "BUILD_SUCCEEDED attempt=$ATTEMPT" > ~/pixelos_build_final_status.txt; exit 0; fi
    if grep -qE "ninja failed with: signal: (killed|terminated)" "$LOGFILE"; then
        echo "  ninja killed by signal -- retrying."
    elif grep -q "^FAILED:" "$LOGFILE"; then
        echo "REAL_BUILD_FAILURE attempt=$ATTEMPT logfile=$LOGFILE" > ~/pixelos_build_final_status.txt; exit 2
    else
        echo "  no FAILED: marker -- premature kill, retrying."
    fi
    sleep 15
done
echo "MAX_ATTEMPTS_EXCEEDED" > ~/pixelos_build_final_status.txt; exit 3
