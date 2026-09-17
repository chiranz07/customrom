#!/bin/bash
cd ~/mistos || exit 1
rm -f ~/mist_build_final_status_husky.txt ~/mistb_husky_attempt*.log ~/envsetup_husky_attempt*.log ~/lunch_husky_attempt*.log
nohup setsid bash ~/mist_build_supervisor_husky.sh 96 > ~/mist_build_supervisor_husky.out 2>&1 < /dev/null &
disown
sleep 3
echo "husky supervisor running: $(ps aux | grep -c '[m]ist_build_supervisor_husky')"
