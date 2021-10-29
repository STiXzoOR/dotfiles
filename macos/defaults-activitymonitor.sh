source "$DOTFILES_DIR/scripts/echos.sh"
source "$DOTFILES_DIR/scripts/requirers.sh"

###############################################################################
bot "Activity Monitor"
###############################################################################

running "Show the main window when launching Activity Monitor"
defaults write com.apple.ActivityMonitor OpenMainWindow -bool true
ok

running "Visualize CPU usage in the Activity Monitor Dock icon"
defaults write com.apple.ActivityMonitor IconType -int 5
ok

# Show processes in Activity Monitor
# 100: All Processes
# 101: All Processes, Hierarchally
# 102: My Processes
# 103: System Processes
# 104: Other User Processes
# 105: Active Processes
# 106: Inactive Processes
# 106: Inactive Processes
# 107: Windowed Processes
running "Show all processes in Activity Monitor"
defaults write com.apple.ActivityMonitor ShowCategory -int 100
ok

running "Sort Activity Monitor results by CPU usage"
defaults write com.apple.ActivityMonitor SortColumn -string "CPUUsage"
defaults write com.apple.ActivityMonitor SortDirection -int 0
ok

running "Set columns for each tab"
defaults write com.apple.ActivityMonitor "UserColumnsPerTab v5.0" -dict \
  '0' '( Command, CPUUsage, CPUTime, Threads, PID, UID, Ports )' \
  '1' '( Command, ResidentSize, Threads, Ports, PID, UID,  )' \
  '2' '( Command, PowerScore, 12HRPower, AppSleep, UID, powerAssertion )' \
  '3' '( Command, bytesWritten, bytesRead, Architecture, PID, UID, CPUUsage )' \
  '4' '( Command, txBytes, rxBytes, PID, UID, txPackets, rxPackets, CPUUsage )'
ok

running "Sort columns in each tab"
defaults write com.apple.ActivityMonitor UserColumnSortPerTab -dict \
  '0' '{ direction = 0; sort = CPUUsage; }' \
  '1' '{ direction = 0; sort = ResidentSize; }' \
  '2' '{ direction = 0; sort = 12HRPower; }' \
  '3' '{ direction = 0; sort = bytesWritten; }' \
  '4' '{ direction = 0; sort = txBytes; }'
ok

running "Update refresh frequency (in seconds)"
# 1: Very often (1 sec)
# 2: Often (2 sec)
# 5: Normally (5 sec)
defaults write com.apple.ActivityMonitor UpdatePeriod -int 2
ok

running "Show Data in the Disk graph (instead of IO)"
defaults write com.apple.ActivityMonitor DiskGraphType -int 1
ok

running "Show Data in the Network graph (instead of packets)"
defaults write com.apple.ActivityMonitor NetworkGraphType -int 1
ok

running "Change Dock Icon"
# 0: Application Icon
# 2: Network Usage
# 3: Disk Activity
# 5: CPU Usage
# 6: CPU History
defaults write com.apple.ActivityMonitor IconType -int 3
ok

killall "Activity Monitor" >/dev/null 2>&1
