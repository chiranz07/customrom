#!/bin/bash
# Self-relaunching supervisor for `mist b` on a heavily loaded shared server.
# Distinguishes real compile failures (stop, let a human/agent fix) from
# the build getting killed by system-wide memory pressure (retry).

cd ~/mistos || exit 1
JOBS="${1:-96}"
MAX_ATTEMPTS=50
ATTEMPT=0

while [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; do
    ATTEMPT=$((ATTEMPT + 1))
    LOGFILE=~/mistb_attempt${ATTEMPT}.log
    echo "=== [$(date)] Attempt $ATTEMPT (jobs=$JOBS) -> $LOGFILE ==="

    # Wait for a bit of breathing room before launching if memory is critical.
    for i in $(seq 1 30); do
        AVAIL_MB=$(free -m | awk '/^Mem:/{print $7}')
        if [ "$AVAIL_MB" -gt 8000 ]; then
            break
        fi
        echo "  memory tight (${AVAIL_MB}MB available), waiting..."
        sleep 20
    done

    bash -c "source build/envsetup.sh > ~/envsetup_attempt${ATTEMPT}.log 2>&1 && lunch mist_shiba-aosp_current-userdebug > ~/lunch_attempt${ATTEMPT}.log 2>&1 && mist b -j${JOBS}" > "$LOGFILE" 2>&1
    RC=$?
    echo "=== [$(date)] Attempt $ATTEMPT exited rc=$RC ===" >> "$LOGFILE"

    if [ "$RC" -eq 0 ]; then
        echo "BUILD_SUCCEEDED attempt=$ATTEMPT" > ~/mist_build_final_status.txt
        exit 0
    fi

    # ninja itself getting SIGKILLed (OOM) makes whatever action was still
    # in-flight print "FAILED: ... / error: action cancelled when ninja
    # exited" -- that FAILED: line is a symptom of the kill, not a real
    # compile error. Check for the kill signature FIRST.
    if grep -qE "ninja failed with: signal: (killed|terminated)" "$LOGFILE"; then
        echo "  ninja was killed (signal) -- premature kill (OOM/system pressure), not a real build error. Retrying."
    elif grep -q "^FAILED:" "$LOGFILE"; then
        echo "REAL_BUILD_FAILURE attempt=$ATTEMPT logfile=$LOGFILE" > ~/mist_build_final_status.txt
        exit 2
    else
        echo "  No FAILED: marker found -- looks like a premature kill (OOM/system pressure), not a real build error. Retrying."
    fi
    sleep 15
done

echo "MAX_ATTEMPTS_EXCEEDED" > ~/mist_build_final_status.txt
exit 3
