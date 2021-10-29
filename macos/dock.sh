Icons=(
  "/Applications/Launchpad.app"
  "/Applications/Brave Browser.app"
  "/Applications/Spark.app"
  "/Applications/Transmission.app"
  "/Applications/Calendar.app"
  "/Applications/Notes.app"
  "/Applications/App Store.app"
  "/Applications/Visual Studio Code.app"
  "/Applications/iTerm2.app"
  "/Applications/System Preferences.app"
  "/Applications/Utilities/Activity Monitor.app"
)

dockutil --no-restart --remove all

for icon in "${Icons[@]}"; do
  dockutil --no-restart --add "$icon"
done

dockutil --no-restart --add '~/Downloads' --view fan --display stack

killall "Dock" >/dev/null 2>&1
