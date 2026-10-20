Title: Pomolet v1.3.0 — open-source native macOS Pomodoro app

Pomolet is a SwiftUI/AppKit Pomodoro timer focused on native window behavior and visual continuity.

The new release adds:

- a persistent Always on Top preference
- edge proximity state with hysteresis and release-to-commit docking
- a shared-window morph between the full timer and compact timer
- transparent companion rendering in the compact window
- reduced-motion handling and geometry tests for negative-coordinate displays and overflow docking

The project includes Core / localization / parity / media checks and builds universal Apple Silicon + Intel apps with the command-line tools.

Repository: https://github.com/Davied-H/Pomolet
Release: https://github.com/Davied-H/Pomolet/releases/tag/v1.3.0

Contributions and review of the window geometry are welcome.
