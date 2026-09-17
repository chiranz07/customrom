#!/bin/bash
# Self-relaunching supervisor for the shusky kernel rebuild (KernelSU-Next+SUSFS
# wired in via blu_spark_defconfig), mirroring ~/mist_build_supervisor.sh's
# approach for the same heavily loaded shared server.

cd ~/kernel || exit 1
MAX_ATTEMPTS=20
ATTEMPT=0

while [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; do
    ATTEMPT=$((ATTEMPT + 1))
    LOGFILE=~/kernelbuild_attempt${ATTEMPT}.log
    echo "=== [$(date)] Attempt $ATTEMPT -> $LOGFILE ==="

    for i in $(seq 1 30); do
        AVAIL_MB=$(free -m | awk '/^Mem:/{print $7}')
        if [ "$AVAIL_MB" -gt 8000 ]; then
            break
        fi
        echo "  memory tight (${AVAIL_MB}MB available), waiting..."
        sleep 20
    done

    # Build the base GKI kernel from the local source tree too (not Google's
    # pinned prebuilt download) so its version matches our device kernel --
    # avoids a "KMI or sublevel mismatch" failure. Mirrors build_shusky.sh's
    # own invocation, called directly so the extra --config is unambiguous.
    ./tools/bazel run --config=stamp --config=shusky --config=use_source_tree_aosp \
        --jobs=96 //private/devices/google/shusky:zuma_shusky_dist > "$LOGFILE" 2>&1
    RC=$?
    echo "=== [$(date)] Attempt $ATTEMPT exited rc=$RC ===" >> "$LOGFILE"

    if [ "$RC" -eq 0 ]; then
        echo "KERNEL_BUILD_SUCCEEDED attempt=$ATTEMPT" > ~/kernel_build_final_status.txt
        exit 0
    fi

    if grep -qE "Killed|signal: killed|Cannot allocate memory|Bazel server .* died|OOM" "$LOGFILE"; then
        echo "  Looks like a premature kill (OOM/system pressure), not a real build error. Retrying."
    elif grep -qE "^ERROR:|error:|FAILED:" "$LOGFILE"; then
        echo "REAL_KERNEL_BUILD_FAILURE attempt=$ATTEMPT logfile=$LOGFILE" > ~/kernel_build_final_status.txt
        exit 2
    else
        echo "  No clear error signature -- treating as premature kill. Retrying."
    fi
    sleep 15
done

echo "MAX_ATTEMPTS_EXCEEDED" > ~/kernel_build_final_status.txt
exit 3
