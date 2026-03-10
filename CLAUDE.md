# Nudge

SwiftUI menubar app that detects distracting websites and prompts mindful check-ins via Claude API.

## Claude Code Config

```yaml
deployCommand: /usr/bin/arch -arm64 /bin/bash -lc 'cd /Users/jasonbenn/code/nudge && swift build --arch arm64 -c release' && launchctl bootout gui/$(id -u) /Users/jasonbenn/code/nudge/LaunchAgents/com.jasonbenn.nudge.plist; launchctl bootstrap gui/$(id -u) /Users/jasonbenn/code/nudge/LaunchAgents/com.jasonbenn.nudge.plist
```

## Build & Deploy

```bash
# Build (release — NSHostingView layout is 2-3x faster in release vs debug on macOS Tahoe)
/usr/bin/arch -arm64 /bin/bash -lc 'cd /Users/jasonbenn/code/nudge && swift build --arch arm64 -c release'

# Reload the launchctl agent (stops old, starts new)
launchctl bootout gui/$(id -u) /Users/jasonbenn/code/nudge/LaunchAgents/com.jasonbenn.nudge.plist
launchctl bootstrap gui/$(id -u) /Users/jasonbenn/code/nudge/LaunchAgents/com.jasonbenn.nudge.plist

# Logs
tail -f /tmp/nudge.stdout.log
tail -f /tmp/nudge.stderr.log
```
