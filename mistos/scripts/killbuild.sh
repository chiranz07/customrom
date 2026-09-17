#!/bin/bash
for p in $(pgrep -f "mist_build_supervisor.sh"); do kill -9 "$p" 2>/dev/null; done
for n in soong_ui ninja ckati soong_build; do pkill -9 -x $n 2>/dev/null; done
sleep 2
echo "supervisor: $(pgrep -fc mist_build_supervisor.sh)  soong_ui: $(pgrep -xc soong_ui)  ninja: $(pgrep -xc ninja)  ckati: $(pgrep -xc ckati)"
fuser ~/mistos/out/.lock 2>/dev/null && echo "LOCK STILL HELD" || echo "lock free"
rm -f ~/mist_build_final_status.txt
