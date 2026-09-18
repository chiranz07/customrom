#!/bin/bash
cd /home/chiranz814/voltage || exit 1
JOBS="${1:-96}"; DEV="${2:-shiba}"; LUNCH="${3:-voltage_shiba-cp2a-userdebug}"; TARGET="${4:-bacon}"
MAX_ATTEMPTS=50; ATTEMPT=0
while [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; do
    ATTEMPT=$((ATTEMPT + 1))
    LOGFILE=/home/chiranz814/voltage_${DEV}_attempt${ATTEMPT}.log
    echo "=== [$(date)] Attempt $ATTEMPT dev=$DEV lunch=$LUNCH target=$TARGET (jobs=$JOBS) -> $LOGFILE ==="
    for i in $(seq 1 30); do AVAIL_MB=$(free -m | awk '/^Mem:/{print $7}'); [ "$AVAIL_MB" -gt 8000 ] && break; echo "  memory tight (${AVAIL_MB}MB), waiting..."; sleep 20; done
    if [ "$ATTEMPT" -eq 1 ]; then CLEAN="m installclean >/dev/null 2>&1;"; else CLEAN=""; fi
    bash -c "source build/envsetup.sh > /home/chiranz814/voltage_${DEV}_envsetup_attempt${ATTEMPT}.log 2>&1 && lunch $LUNCH > /home/chiranz814/voltage_${DEV}_lunch_attempt${ATTEMPT}.log 2>&1 && $CLEAN m $TARGET -j${JOBS}" > "$LOGFILE" 2>&1
    RC=$?; echo "=== [$(date)] Attempt $ATTEMPT exited rc=$RC ===" >> "$LOGFILE"
    if [ "$RC" -eq 0 ]; then echo "BUILD_SUCCEEDED attempt=$ATTEMPT" > /home/chiranz814/voltage_${DEV}_build_final_status.txt; exit 0; fi
    if grep -qiE "^error|error:|Error:" /home/chiranz814/voltage_${DEV}_lunch_attempt${ATTEMPT}.log 2>/dev/null; then echo "LUNCH_FAILURE attempt=$ATTEMPT logfile=/home/chiranz814/voltage_${DEV}_lunch_attempt${ATTEMPT}.log" > /home/chiranz814/voltage_${DEV}_build_final_status.txt; exit 2
    elif grep -qE "ninja failed with: signal: (killed|terminated)" "$LOGFILE"; then echo "  ninja killed -- retrying."
    elif grep -qE "^FAILED:" "$LOGFILE"; then echo "REAL_BUILD_FAILURE attempt=$ATTEMPT logfile=$LOGFILE" > /home/chiranz814/voltage_${DEV}_build_final_status.txt; exit 2
    else echo "  no FAILED: marker -- premature kill, retrying."; fi
    sleep 15
done
echo "MAX_ATTEMPTS_EXCEEDED" > /home/chiranz814/voltage_${DEV}_build_final_status.txt; exit 3
