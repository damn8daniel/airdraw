<div align="center">

# AirDraw

[![Python](https://img.shields.io/badge/Python-3.10+-3776AB?logo=python&logoColor=white)](https://python.org)
[![Swift](https://img.shields.io/badge/Swift-5.9+-FA7343?logo=swift&logoColor=white)](https://swift.org)
[![MediaPipe](https://img.shields.io/badge/MediaPipe-Hand_Tracking-4285F4?logo=google&logoColor=white)](https://mediapipe.dev)
[![macOS](https://img.shields.io/badge/macOS-13+-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Draw in the air using hand gestures.** AirDraw tracks your hand in real time and translates finger movements into strokes on a digital canvas. Two implementations: a Python prototype (MediaPipe + Pygame) and a native macOS app (Swift + Vision).

</div>

---

## Features

- **Real-time hand tracking** powered by MediaPipe (Python) and Apple Vision (Swift)
- **5 gesture controls** -- point to draw, pinch to pause, V-sign to cycle color, open palm to clear, fist to pause
- **Exponential moving average smoothing** for fluid, jitter-free strokes (separate coefficients for drawing vs. idle)
- **9-color palette** with adjustable brush width (2--30 px)
- **Undo, clear, and save** -- PNG export to Desktop
- **Camera feed overlay** with hand skeleton and joint visualization
- **Gesture debouncing** -- 5-frame stability buffer prevents accidental triggers

## Architecture

```mermaid
graph TB
    subgraph Input
        CAM[Camera 1280x720] -->|30 fps| FLIP[Mirror Flip]
    end

    subgraph Detection ["Hand Detection (25 fps)"]
        FLIP --> MP[MediaPipe HandLandmarker]
        MP --> LM[21 Landmarks]
        LM --> GC[Gesture Classifier]
        GC --> DB[Debounce Buffer x5]
        DB --> SG[Stable Gesture]
    end

    subgraph Smoothing
        LM --> EMA[EMA Filter]
        EMA -->|alpha=0.12 draw| POS[Smooth Position]
        EMA -->|alpha=0.18 idle| POS
    end

    subgraph Canvas
        SG -->|POINTING| DRAW[Start/Add Stroke]
        SG -->|PEACE hold| COLOR[Cycle Color]
        SG -->|OPEN_PALM hold| CLEAR[Clear Canvas]
        POS --> DRAW
    end

    subgraph Render ["Pygame 60 fps"]
        DRAW --> R[Render Strokes]
        R --> UI[UI Overlay]
        UI --> DISP[Display]
    end
```

## Gesture Controls

| Gesture | Action | Hold Time |
|---------|--------|-----------|
| Point (index finger) | Draw | Instant |
| Pinch (thumb + index) | Pause (lift brush) | Instant |
| Peace / V-sign | Cycle color | 1.4s hold |
| Open palm | Clear canvas | 1.4s hold |
| Fist | Pause | Instant |

## Tech Stack

| Component | Technology |
|-----------|------------|
| Python version | Python 3, MediaPipe Tasks API, OpenCV, Pygame |
| macOS native | Swift 5.9, SwiftUI, AVFoundation, Apple Vision |
| Hand tracking | MediaPipe HandLandmarker (Python) / Vision framework (Swift) |

## Quick Start

### Python Version

```bash
# Install dependencies
pip install mediapipe opencv-python pygame numpy

# Download the hand tracking model
curl -L https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task \
  -o hand_landmarker.task

# Run
python3 airdraw.py
```

### macOS Native Version (Swift)

Requires macOS 13+ and Swift 5.9+.

```bash
# Build and package as .app
./build.sh

# Run
open AirDraw.app
```

### Keyboard Shortcuts (Python)

| Key | Action |
|-----|--------|
| `Cmd+Z` | Undo last stroke |
| `Cmd+C` | Clear canvas |
| `Cmd+S` | Save drawing as PNG |
| `H` | Toggle camera feed |
| `Arrow Up/Down` | Adjust brush width |
| `Arrow Right` | Next color |
| `Esc` | Quit |

## Camera Permissions

Both versions require camera access:

- **Python:** System Settings > Privacy & Security > Camera > allow Terminal (or your IDE)
- **Swift app:** Requests permission on first launch

## Project Structure

```
airdraw/
├── airdraw.py          # Python app (MediaPipe + Pygame, 694 lines)
├── Sources/AirDraw/
│   ├── AirDrawApp.swift      # SwiftUI app entry point
│   ├── ContentView.swift     # Main view
│   ├── CameraManager.swift   # AVFoundation camera
│   ├── HandTracker.swift     # Apple Vision hand tracking
│   ├── DrawingCanvas.swift   # Canvas rendering
│   └── Models.swift          # Data models
├── Package.swift       # Swift package manifest
├── build.sh            # Build + code-sign script
├── run.sh              # Python convenience launcher
├── Info.plist          # macOS app metadata
└── entitlements.plist  # Camera entitlements
```

## License

MIT
