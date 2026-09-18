#!/bin/bash
DEV="${1:-shiba}"; LUNCH="${2:-voltage_shiba-cp2a-userdebug}"; TARGET="${3:-voltage}"
cd ~/voltage || exit 1
rm -f ~/voltage_${DEV}_build_final_status.txt ~/voltage_${DEV}_attempt*.log ~/voltage_${DEV}_envsetup_attempt*.log ~/voltage_${DEV}_lunch_attempt*.log
nohup setsid bash ~/voltage_build_supervisor.sh 96 $DEV $LUNCH $TARGET > ~/voltage_${DEV}_build_supervisor.out 2>&1 < /dev/null &
disown; sleep 3; echo "supervisor started for $DEV ($LUNCH, m $TARGET)"
