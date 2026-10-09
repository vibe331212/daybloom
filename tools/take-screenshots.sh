#!/bin/zsh
# Takes the App Store screenshots in the iPhone 18 Pro Max simulator (1320x2868, Apple's 6.9-inch size).
# Needs: a Debug build installed in the simulator, signed in as the App Review demo account.
# Usage: tools/take-screenshots.sh [simulator-udid]
set -euo pipefail
U="${1:-1FC8EDF6-83B5-4FE3-B436-6744A0E0D362}"
APP=com.vibe331212.daybloom
OUT="$(cd "$(dirname "$0")/.." && pwd)/appstore/screenshots"
mkdir -p "$OUT"
xcrun simctl status_bar "$U" override --time "$(date +%-I:%M)" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

# Every shot starts the app fresh, waits until it's online, then sets up one screen.
READY='const wait=ms=>new Promise(r=>setTimeout(r,ms)); for(let i=0;i<60&&!Cloud.on;i++) await wait(200); await refreshChats(); await wait(800); window.scrollTo(0,0);'
DAYS='const nextDay=wd=>{ const d=new Date(); d.setHours(0,0,0,0); d.setDate(d.getDate()+((wd-d.getDay()+7)%7)); return d; };'

shot() {
  local name="$1" settle="$2" js="$3"
  xcrun simctl launch --terminate-running-process "$U" "$APP" -DaybloomDebugJS "$READY $DAYS $js return 'ok';" >/dev/null
  sleep "$settle"
  xcrun simctl status_bar "$U" override --time "$(date +%-I:%M)"   # match the app's own clock
  xcrun simctl io "$U" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1
  # App Store Connect rejects images with a transparency layer, so flatten each one
  local tmp="$(mktemp -t shot).jpg"; sips -s format jpeg -s formatOptions 100 "$OUT/$name.png" --out "$tmp" >/dev/null && sips -s format png "$tmp" --out "$OUT/$name.png" >/dev/null && rm -f "$tmp"
  echo "took $name"
}

shot 01-calendar 9 "applyTheme('royal'); document.querySelector('[data-view=calendar]').click(); selected=nextDay(2); viewY=selected.getFullYear(); viewM=selected.getMonth(); renderAll();"
shot 02-chat 11 "applyTheme('royal'); document.querySelector('[data-view=friends]').click(); await openChat(Chat.list.find(c=>!c.is_group).id);"
shot 03-friends 10 "applyTheme('royal'); document.querySelector('[data-view=friends]').click(); await wait(1500); window.scrollTo(0,0);"
shot 04-clock 9 "applyTheme('ocean'); World.list=[{city:'Tokyo',country:'Japan',zone:'Asia/Tokyo'},{city:'London',country:'United Kingdom',zone:'Europe/London'},{city:'Sydney',country:'Australia',zone:'Australia/Sydney'}]; saveWorld(); renderWorld(); document.querySelector('[data-view=clock]').click(); document.querySelector('#clockSeg [data-mode=clock]').click();"
shot 05-nature 10 "applyTheme('nature'); document.querySelector('[data-view=calendar]').click(); selected=nextDay(4); viewY=selected.getFullYear(); viewM=selected.getMonth(); renderAll();"
shot 06-group 11 "applyTheme('aurora'); document.querySelector('[data-view=friends]').click(); await openChat(Chat.list.find(c=>c.is_group).id);"
shot 07-modes 9 "applyTheme('sunset'); document.querySelector('[data-view=settings]').click(); await wait(300); const h=[...document.querySelectorAll('#view-settings h3')].find(x=>x.textContent==='Modes'); window.scrollTo(0,h.getBoundingClientRect().top+window.scrollY-70);"
shot 08-timer 11 "applyTheme('midnight'); document.querySelector('[data-view=clock]').click(); document.querySelector('#clockSeg [data-mode=timer]').click(); Native.send=()=>{}; document.querySelector('#presets [data-m=\"15\"]').click(); document.getElementById('tStart').click(); await wait(2500);"

# Put the app back to its normal look and stop the test timer
xcrun simctl launch --terminate-running-process "$U" "$APP" -DaybloomDebugJS "$READY applyTheme('royal'); document.getElementById('tReset').click(); document.querySelector('[data-view=calendar]').click(); return 'ok';" >/dev/null
sleep 6
echo "Screenshots saved in $OUT"
