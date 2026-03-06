# Nudge

SwiftUI menubar app that detects distracting websites and prompts mindful check-ins via Claude API.

## Claude Code Config

```yaml
deployCommand: swift build && launchctl bootout gui/$(id -u) /Users/jasonbenn/code/nudge/LaunchAgents/com.jasonbenn.nudge.plist; launchctl bootstrap gui/$(id -u) /Users/jasonbenn/code/nudge/LaunchAgents/com.jasonbenn.nudge.plist
```

## Build & Deploy

```bash
# Build
swift build

# Reload the launchctl agent (stops old, starts new)
launchctl bootout gui/$(id -u) /Users/jasonbenn/code/nudge/LaunchAgents/com.jasonbenn.nudge.plist
launchctl bootstrap gui/$(id -u) /Users/jasonbenn/code/nudge/LaunchAgents/com.jasonbenn.nudge.plist

# Logs
tail -f /tmp/nudge.stdout.log
tail -f /tmp/nudge.stderr.log
```
