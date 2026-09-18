#!/bin/bash
cd ~/pixelos || exit 1
rm -f ~/pixelos_build_final_status.txt ~/pixelos_attempt*.log ~/pixelos_envsetup_attempt*.log ~/pixelos_lunch_attempt*.log
nohup setsid bash ~/pixelos_build_supervisor.sh 96 > ~/pixelos_build_supervisor.out 2>&1 < /dev/null &
disown
sleep 3
echo "supervisor running: $(ps aux | grep -c '[p]ixelos_build_sup')"
