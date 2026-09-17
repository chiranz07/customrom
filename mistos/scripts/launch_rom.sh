#!/bin/bash
cd ~/mistos || exit 1
rm -f ~/mist_build_final_status.txt ~/mistb_attempt*.log ~/envsetup_attempt*.log ~/lunch_attempt*.log
nohup setsid bash ~/mist_build_supervisor.sh 96 > ~/mist_build_supervisor.out 2>&1 < /dev/null &
disown
sleep 3
echo "supervisor running: $(ps aux | grep -c '[m]ist_build_sup')"
