# AirDraw — Air Drawing with Hand Gestures

Draw in the air using hand gestures captured by your camera. AirDraw tracks your hand in real time and translates finger movements into strokes on a digital canvas.

Two implementations are included: a **Python prototype** (MediaPipe + Pygame) and a **native macOS app** (Swift + SwiftUI + Vision).

## Features

- **Real-time hand tracking** powered by MediaPipe (Python) and Apple Vision framework (Swift)
- **Gesture recognition** — five gestures control the drawing flow:
  | Gesture | Action |
  |---------|--------|
  | Point (index finger) | Draw |
  | Pinch | Pause (lift brush) |
  | Peace / V-sign (hold) | Cycle color |
  | Open palm (hold) | Clear canvas |
  | Fist | Pause |
- **Exponential moving average smoothing** for fluid, jitter-free strokes
- **9-color palette** with adjustable brush width
- **Undo, clear, and save** (PNG export to Desktop)
- Camera feed overlay with hand skeleton visualization

## Tech Stack

| Component | Technology |
|-----------|------------|
| Python version | Python 3, MediaPipe Tasks API, OpenCV, Pygame |
| macOS native version | Swift, SwiftUI, AVFoundation, Vision framework |
| Hand tracking model | MediaPipe HandLandmarker (Python) / Apple Vision (Swift) |

## Demo

> Screenshots and demo GIFs coming soon.

## Getting Started

### Python Version

1. **Install dependencies:**
   ```bash
   pip install mediapipe opencv-python pygame numpy
   ```

2. **Download the MediaPipe hand tracking model:**
   ```bash
   curl -L https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task -o hand_landmarker.task
   ```

3. **Run:**
   ```bash
   python3 airdraw.py
   ```
   Or use the convenience script:
   ```bash
   ./run.sh
   ```

### macOS Native Version (Swift)

Requires macOS 13+ and Swift 5.9+.

1. **Build:**
   ```bash
   swift build -c release
   ```

2. **Build and package as .app:**
   ```bash
   ./build.sh
   ```
   This compiles the Swift package, creates `AirDraw.app`, and code-signs it for camera access.

3. **Run:**
   ```bash
   open AirDraw.app
   ```

### Controls (Python version)

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

Both versions require camera access. If the camera does not work:

- **Python:** Go to System Settings > Privacy & Security > Camera and allow access for Terminal (or your IDE).
- **Swift app:** The app will request permission on first launch.

## License

MIT
