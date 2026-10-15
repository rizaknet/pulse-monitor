# Pulse

A modern, lightweight macOS menu-bar activity & application monitor engineered in pure Swift & SwiftUI for Apple Silicon Macs.

Pulse provides real-time visibility into per-application resource consumption, memory pressure, battery metrics, and developer workspaces with minimal system overhead.

---

## Highlights

- **App-Centric Monitoring**: Collapses helper, renderer, and crashpad processes directly into their parent application.
- **Actor-Isolated Sampling Engine**: Zero UI lockups or freezes. Heavy system probes run in a background `SamplingEngine` actor with asynchronous snapshot delivery.
- **Adaptive Sampling Cadence**: Automatically throttles sampling frequency (5s in background, 2s when active) to maintain <1% CPU and <30MB RAM usage.
- **True macOS Memory Pressure**: Directly monitors kernel VM pressure states (`Normal`, `Elevated`, `Critical`).
- **Battery & Power Analytics**: Live wattage, battery health percentage, cycle counts, voltage, and remaining time.
- **Developer Workspace & Port Inspector**: Detects active codebases, open TCP listening ports, idle developer servers, and sleep blockers.
- **Customizable Menu Bar**: Choose between pulse icon, CPU/Memory figures, CPU only, or network throughput.

---

## Build & Run

### Prerequisites
- macOS 15+ (Apple Silicon or Intel)
- Command Line Tools (`clang`, `swift`)

### Building the Application Bundle
```zsh
./scripts/bundle.sh
```
The application will be compiled in release mode and packaged into `build/Pulse.app`.

### Launching Pulse
```zsh
open build/Pulse.app
```

### Command Line Tools & Diagnostics
Run a diagnostic snapshot:
```zsh
./build/Pulse.app/Contents/MacOS/Pulse --dump
```

Run test suite:
```zsh
./build/Pulse.app/Contents/MacOS/Pulse --test
```

---

## Architecture Overview

```
Pulse/
├── Package.swift                     # PulseCore library + Pulse application targets
├── scripts/bundle.sh                 # Release packager & codesign script
├── Sources/
│   ├── PulseCore/                    # Pure engine & probes (No UI dependencies)
│   │   ├── Models/Models.swift       # Immutable Sendable snapshots
│   │   ├── Engine/                   # SamplingEngine actor, AppGrouper, AlertEngine
│   │   ├── Probes/                   # libproc, mach, IOKit, SystemConfiguration
│   │   └── Util/                     # Formatting, sysctl, RingBuffer, SelfTest
│   └── Pulse/                        # SwiftUI Application Layer
│       ├── PulseApp.swift            # Entry point, Scene declarations, Settings
│       ├── AppStore.swift            # @MainActor Observable store
│       ├── MenuBar/                  # Menu bar item & compact dropdown panel
│       ├── Window/                   # Multi-tab MainWindow (Apps, Overview, Metrics, Battery, Dev)
│       └── Design/                   # Theme tokens, Swift Charts, visual components
```
