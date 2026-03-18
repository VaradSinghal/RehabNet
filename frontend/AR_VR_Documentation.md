# RehabNet — AR & VR Module Documentation

## 1. Architecture Overview

RehabNet uses two distinct interaction paradigms for Parkinson's rehabilitation:

| Module | Technology | Input | AI Integration |
|--------|-----------|-------|---------------|
| **AR Exercise** | Device camera + ML Kit Pose Detection | Real body movement | MovementClassifier (backend) |
| **VR Interaction** | Pseudo-3D rendered environment | Touch/drag gestures | SessionService (local) |

### System Data Flow

```
┌────────────────────── AR MODULE ──────────────────────┐
│                                                        │
│  Camera Feed → ML Kit PoseDetector → 33 Landmarks     │
│       │                                    │           │
│       ▼                                    ▼           │
│  Live Preview                     Exercise Logic       │
│  (CameraPreview)                  (local heuristics)   │
│       │                                    │           │
│       │                    Landmarks (JSON) ▼           │
│       ▼                     POST /pose-data/ ──────►   │
│  Skeleton Overlay          Backend MovementClassifier   │
│  AR Targets                        │                   │
│  Feedback Banner   ◄───── AI Feedback + Accuracy       │
└────────────────────────────────────────────────────────┘

┌────────────────────── VR MODULE ──────────────────────┐
│                                                        │
│  CustomPainter → Perspective 3D Tunnel Rendering       │
│       │                                                │
│  GestureDetector → Hand position (drag)                │
│       │                                                │
│  GameLoop (32ms Timer) → Spawn, Move, Hit-test targets │
│       │                                                │
│  SessionService.addRep() ← on each hit                 │
│  SessionService.updateMetrics() ← on game end          │
└────────────────────────────────────────────────────────┘
```

---

## 2. AR Exercise Module

**File:** `lib/screens/ar_exercise_screen.dart`  
**Widget:** `ArExerciseScreen` (StatefulWidget)

### 2.1 Camera & Pose Detection Pipeline

```
CameraController (front camera, NV21 format, medium resolution)
        │
        ▼  startImageStream() → _onCameraFrame()
        │
   (process every 2nd frame for performance)
        │
        ▼
   _buildInputImage() → InputImage
        │
        ▼
   PoseDetector.processImage() → List<Pose>
        │
        ▼
   33 PoseLandmark objects (type, x, y, z, likelihood)
```

**Key Implementation Details:**

- **Frame Rate Throttling:** Processes every 2nd camera frame (`_frameCount % 2`) to maintain UI responsiveness.
- **Image Format:** NV21 (raw bytes from camera) — required for ML Kit on Android.
- **Resolution:** `ResolutionPreset.medium` — balances detection accuracy with processing speed.

### 2.2 Coordinate System Transformation

ML Kit returns landmark coordinates in the **rotated sensor image space**. The app performs a multi-step transformation:

```
ML Kit coordinates (image pixels)
        │
   Step 1: Account for sensor rotation (90°/270°)
        │  Swap width/height for rotated orientations
        │
   Step 2: Normalize to 0.0 – 1.0
        │  nx = x / absWidth,  ny = y / absHeight
        │
   Step 3: Front camera mirror
        │  nx = 1.0 - nx  (horizontal flip)
        │
   Step 4: Scale to screen dimensions
        │  screenX = nx × screenWidth
        │  screenY = ny × screenHeight
        │
        ▼
Flutter screen coordinates (pixels)
```

Two variants are used:
- `_translateToScreen()` → pixel coordinates for UI rendering
- `_translateToNormalized()` → 0–1 coordinates for backend transmission

### 2.3 Supported Exercises

#### Exercise 1: Target Touch
```
Objective: Move your HAND to the green target on screen.

Algorithm:
  1. Spawn target at random position (15-85% X, 22-70% Y)
  2. For each frame, compute distance: |hand_position - target_position|
  3. If distance < 70px → HIT (record reaction time)
  4. If 4.5 seconds elapsed → MISS (respawn)
  5. Reaction time displayed as feedback
```

#### Exercise 2: Guided Path
```
Objective: Trace a curved path with your wrist.

Algorithm:
  1. Generate 7 waypoints along a sine curve:
     x = 0.15 + 0.70 × t
     y = 0.40 + 0.14 × sin(2π × t)
  2. User must reach each waypoint in sequence
  3. Each waypoint has a 50px reach radius
  4. Path regenerates after completion
```

#### Exercise 3: Arm Raise Reps
```
Objective: Count full arm raises (wrist above shoulder).

Algorithm:
  1. Track right wrist and right shoulder landmarks
  2. Compute height ratio: shoulder_y - wrist_y (normalised)
  3. State machine:
     - heightRatio > 0.08 AND _armWasDown → REP COUNTED
     - heightRatio < 0.02 → arm returned to rest (_armWasDown = true)
     - 0.0 < heightRatio < 0.08 → "Raise higher!" feedback
  4. Accuracy: 95% per successful rep
```

### 2.4 Backend AI Integration

Every 15th frame, pose landmarks are serialised and sent to the backend:

```dart
POST /pose-data/
{
  "user_id": 1,
  "landmarks": [
    {"x": 0.52, "y": 0.31, "z": -0.05, "likelihood": 0.92, "type": "rightWrist"},
    ...
  ],
  "exercise": "arm_raise"
}
```

The backend `MovementClassifier` returns:

```json
{
  "classification": "Correct",
  "feedback": "Excellent arm raise! Great extension.",
  "accuracy_pct": 95.0,
  "symmetry": {"left_accuracy": 78.5, "right_accuracy": 92.3}
}
```

The AI feedback is displayed in the UI with a 🤖 prefix, overriding local heuristic feedback.

### 2.5 Instruction Overlay

An elderly-friendly instruction overlay appears before the exercise starts:
- Large text with icons explaining what to do
- "How to Play" guidance with step-by-step instructions
- Exercise starts ONLY after user taps "I'm Ready"

---

## 3. VR Hand Interaction Module

**File:** `lib/screens/vr_hand_screen.dart`  
**Widget:** `VrHandScreen` (StatefulWidget)

### 3.1 3D Rendering Engine

The VR module uses **CustomPainter** to render a pseudo-3D perspective tunnel:

```
Perspective Projection Formula:
    scale = 1.0 / (1.0 + z)     // z = 0 (far) to 1.0 (near)
    screenX = center + (worldX × scale × viewWidth)
    screenY = center + (worldY × scale × viewHeight)
    objectSize = baseSize × scale

Visual elements:
    - Converging grid lines → depth perception
    - Gradient background → atmospheric depth
    - Targets grow as they approach → sense of motion
    - Glow effects on targets → premium visual feel
```

### 3.2 Game Loop Architecture

```
Timer.periodic(32ms) → _gameLoop()
        │
   ┌────┴───────────────────────────────┐
   │                                      │
   ▼                                      ▼
Spawn Logic                          Move & Hit-test
   │                                      │
   ├─ Normal mode:                        ├─ tgt.z += approachSpeed
   │   random (x,y) in [-1,1]            │
   │                                      ├─ If z ∈ [0.85, 1.1]:
   ├─ Walking Path mode:                 │   compute distance to hand
   │   lane-based spawning               │   if dist < hitRadius → HIT
   │   x ∈ {-0.6, 0.0, 0.6}            │
   │                                      ├─ If z > 1.2 → MISS
   └──────────────────────────────────────┘
```

### 3.3 Difficulty System

| Parameter | Easy | Medium | Hard |
|-----------|------|--------|------|
| Approach Speed | 0.008 | 0.015 | 0.025 |
| Hit Radius | 0.25 | 0.15 | 0.10 |
| Spawn Rate | 0.15 | 0.25 | 0.40 |

### 3.4 Game Modes

**Normal Mode:**
- Targets spawn at random positions across the full 2D space
- Tests general motor control and reaction time

**Walking Path Mode:**
- Targets spawn in 3 fixed lanes (left, center, right)
- Simulates stepping on footprints approaching the user
- Targets at Y=0.3 (lower) to feel more like "stepping"

### 3.5 Audio Metronome

When enabled, plays a rhythmic beep every 800ms using the `audioplayers` package:
- Helps patients maintain consistent movement pace
- Clinically validated cueing strategy for PD

### 3.6 Session Timer & Summary

- 60-second countdown timer
- End-game summary panel shows:
  - Total score (hits)
  - Missed targets
  - Accuracy percentage
  - Time per hit average

### 3.7 Backend Integration

The VR screen connects to the backend via `SessionService`:

```
On each target HIT:
    → SessionService.addRep(accuracy: 100.0)
    → Dashboard reps counter updates live

On game END:
    → SessionService.updateMetrics(
        newReps: _score,
        newAccuracy: percentage,
      )
    → Final metrics recorded in session
```

---

## 4. Shared Components

### ExerciseSelector Widget
**File:** `lib/widgets/exercise_selector.dart`

Horizontal scrollable card list for AR exercise selection:
- Animated selection highlight with glow effect
- Each card shows icon, name, and subtitle
- Currently 3 exercises: Target Touch, Guided Path, Arm Raise

### FeedbackBanner Widget
Floating banner at the bottom of the AR screen:
- Green background for positive feedback ("Correct", "Hit!")
- Red/amber for corrective feedback ("Raise higher!")
- AI feedback from backend prefixed with 🤖

### Instruction Overlay
Full-screen overlay for both AR and VR:
- Appears before exercise/game starts
- Large, elderly-friendly text and icons
- "I'm Ready" / "Start Exercise" button to begin

---

## 5. Technology Stack

| Component | Library | Version | Purpose |
|-----------|---------|---------|---------|
| Camera | `camera` | latest | Live video feed |
| Pose Detection | `google_mlkit_pose_detection` | latest | 33-point body tracking |
| Audio | `audioplayers` | latest | VR metronome beep |
| State Management | `provider` | latest | SessionService (ChangeNotifier) |
| HTTP | `http` | latest | REST API calls to backend |
| WebSocket | `web_socket_channel` | latest | Real-time tremor data |
| Charts | `fl_chart` | latest | Tremor/accel visualization |

---

## 6. Design Rationale

### Why AR + ML Kit (not ARCore/ARKit)?
- **No AR glasses required** — works on any Android phone with a camera
- **Lower patient barrier** — elderly patients use their existing phone
- **ML Kit is lightweight** — processes at 15+ FPS on mid-range devices
- **Pose detection is sufficient** — we track joint positions, not 3D surfaces

### Why pseudo-3D VR (not WebXR/Unity)?
- **Zero additional hardware** — no VR headset needed
- **Flutter-native rendering** — no platform channel overhead
- **Customizable difficulty** — easy to adjust for PD motor limitations
- **Inclusive design** — standard touch input accessible to all patients
