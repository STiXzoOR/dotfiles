Icons=(
  "/System/Applications/Launchpad.app"
  "/Applications/Brave Browser.app"
  "/Applications/Google Chrome.app"
  "/Applications/Slack.app"
  "/Applications/Spark.app"
  "/System/Applications/Calendar.app"
  "/Applications/Notion.app"
  "/System/Applications/Notes.app"
  "/Applications/WebStorm.app"
  "/Applications/Warp.app"
  "/System/Applications/System Preferences.app"
)

dockutil --no-restart --remove all

for icon in "${Icons[@]}"; do
  dockutil --no-restart --add "$icon"
done

dockutil --no-restart --add '~/Downloads' --view fan --display stack

killall "Dock" >/dev/null 2>&1
