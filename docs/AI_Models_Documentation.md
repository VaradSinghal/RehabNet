# RehabNet — AI Models Documentation

## 1. System Overview

RehabNet's AI backend consists of three specialised modules that process real-time sensor and pose data to assist Parkinson's Disease (PD) rehabilitation:

| Module | Input Source | Purpose |
|--------|-------------|---------|
| **TremorDetector** | ESP32 MPU6050 accelerometer (via WiFi POST) | Detects and classifies resting tremor |
| **MovementClassifier** | Google ML Kit pose landmarks (via Flutter camera) | Evaluates exercise form and accuracy |
| **GaitAnalyzer** | Ankle trajectory from pose or IMU data | Detects Freezing of Gait and stride irregularities |

### Data Flow

```
ESP32 (MPU6050)                 Flutter App (Camera)
     │                                 │
     │ POST /sensor-data/              │ POST /pose-data/
     ▼                                 ▼
┌─────────────┐              ┌─────────────────────┐
│ TremorDetect│              │ MovementClassifier   │
│   or        │              │                     │
│ FFT + Filter│              │ Angle-based scoring  │
└──────┬──────┘              └──────────┬──────────┘
       │                                │
       │     ┌──────────────────┐       │
       │     │   GaitAnalyzer   │       │
       │     │ Step detection + │       │
       │     │ Freeze Index     │       │
       │     └────────┬─────────┘       │
       ▼              ▼                 ▼
   WebSocket broadcast to Flutter    HTTP JSON response
   (real-time tremor updates)        (exercise feedback)
```

---

## 2. TremorDetector

**File:** `ai/tremor_detector.py`  
**Class:** `TremorDetector`  
**API Endpoint:** `POST /sensor-data/`

### 2.1 Purpose

Detects and classifies Parkinson's resting tremor from raw accelerometer data. PD tremor typically manifests at 4–6 Hz with amplitudes > 0.1 g.

### 2.2 Algorithm — Signal Processing Pipeline

```
Raw (ax, ay, az) samples
        │
        ▼
┌─── Sliding Buffer (256 samples ≈ 5 s at 50 Hz) ───┐
│                                                      │
│  Step 1: DC Offset Removal                           │
│    ─ Subtract per-axis mean to remove gravity (1g)   │
│                                                      │
│  Step 2: Magnitude Computation                       │
│    ─ mag = √(ax² + ay² + az²)                        │
│                                                      │
│  Step 3: Butterworth Bandpass Filter (3–12 Hz)       │
│    ─ 4th-order IIR filter via scipy.signal.filtfilt  │
│    ─ Isolates the clinically relevant tremor band    │
│                                                      │
│  Step 4: Hanning Window                              │
│    ─ Reduces spectral leakage before FFT             │
│    ─ w(n) = 0.5 × (1 − cos(2πn / N))                │
│                                                      │
│  Step 5: Real FFT                                    │
│    ─ scipy.fft.rfft for frequency decomposition      │
│                                                      │
│  Step 6: Peak Frequency Detection                    │
│    ─ Dominant frequency = argmax of FFT magnitude    │
│    ─ Only within the 3–12 Hz tremor band             │
│                                                      │
│  Step 7: Spectral Energy Ratio                       │
│    ─ ER = Σ|FFT(tremor band)|² / Σ|FFT(total)|²     │
│    ─ High ER = concentrated tremor activity          │
│                                                      │
│  Step 8: RMS Amplitude                               │
│    ─ RMS = √(mean(filtered_signal²))                 │
│                                                      │
│  Step 9: Severity Classification                     │
│    ─ Uses frequency, amplitude, and energy ratio     │
│                                                      │
│  Step 10: Exponential Moving Average Smoothing       │
│    ─ score_t = α × raw + (1−α) × score_{t-1}        │
│    ─ Prevents severity from flickering               │
└──────────────────────────────────────────────────────┘
```

### 2.3 Severity Classification Rules

| Severity | Frequency | RMS Amplitude | Energy Ratio | Clinical Meaning |
|----------|-----------|---------------|--------------|------------------|
| **High** | 3–8 Hz | ≥ 0.30 g | ≥ 0.50 | Significant PD tremor |
| **Moderate** | Any | ≥ 0.10 g | ≥ 0.25 | Notable tremor activity |
| **Low** | Any | < 0.10 g | < 0.25 | Normal physiological motion |

### 2.4 Output Format

```json
{
  "frequency_hz": 5.27,
  "amplitude_g": 0.2341,
  "severity": "Moderate",
  "energy_ratio": 0.3812,
  "smooth_score": 42.5
}
```

---

## 3. MovementClassifier

**File:** `ai/movement_classifier.py`  
**Class:** `MovementClassifier`  
**API Endpoint:** `POST /pose-data/`

### 3.1 Purpose

Evaluates rehabilitation exercise form by analysing body joint positions from Google ML Kit pose detection. Supports multiple exercises with continuous accuracy scoring.

### 3.2 Supported Exercises

| Exercise | Landmarks Used | Ideal Target | Measurement |
|----------|---------------|--------------|-------------|
| **arm_raise** | Wrist, Shoulder (bilateral) | Wrists above shoulders | Vertical displacement |
| **shoulder_flexion** | Hip → Shoulder → Wrist | 170° angle | Joint angle |
| **elbow_curl** | Shoulder → Elbow → Wrist | 40° angle | Joint angle |
| **lateral_raise** | Hip → Shoulder → Wrist | 90° angle | Joint angle |

### 3.3 Algorithm — Joint Angle Computation

For exercises requiring angle measurement, the classifier uses the **dot product formula**:

```
Given three points A (proximal), B (joint), C (distal):

    Vector BA = A − B
    Vector BC = C − B

    cos(θ) = (BA · BC) / (|BA| × |BC|)

    θ = arccos(cos(θ))    → angle in degrees
```

### 3.4 Accuracy Scoring

Accuracy is computed as a **continuous 0–100% score** based on deviation from the ideal angle:

```
    error = |measured_angle − ideal_angle|
    accuracy = max(0, (1 − error / tolerance) × 100)
```

For bilateral exercises, the final score is the **average** of left and right sides.

### 3.5 Symmetry Analysis

For bilateral exercises, the classifier compares left and right sides:

```json
{
  "left_accuracy": 78.5,
  "right_accuracy": 92.3,
  "imbalance": 13.8
}
```

If imbalance exceeds 25%, a coaching cue directs the patient to focus on the weaker side.

### 3.6 Classification Mapping

| Score Range | Classification | Feedback Tone |
|-------------|---------------|---------------|
| ≥ 75% | Correct | Positive reinforcement |
| 40–74% | Needs Improvement | Coaching guidance |
| < 40% | Incorrect | Corrective instruction |

### 3.7 Output Format

```json
{
  "classification": "Needs Improvement",
  "feedback": "Raise your hands higher — try to reach above your head.",
  "accuracy_pct": 58.3,
  "symmetry": {
    "left_accuracy": 45.2,
    "right_accuracy": 71.4,
    "imbalance": 26.2
  }
}
```

---

## 4. GaitAnalyzer

**File:** `ai/gait_analyzer.py`  
**Class:** `GaitAnalyzer`  
**API Endpoint:** Currently used internally (future: `POST /gait-data/`)

### 4.1 Purpose

Detects walking abnormalities, particularly **Freezing of Gait (FOG)** — a sudden inability to initiate or continue walking that is common in advanced PD.

### 4.2 Algorithm — Gait Analysis Pipeline

```
Ankle Y-trajectory samples
        │
        ▼
┌─── Signal Processing ──────────────────────────────┐
│                                                      │
│  Step 1: De-trending                                 │
│    ─ Moving average subtraction (15-sample window)   │
│    ─ Removes slow baseline drift                     │
│                                                      │
│  Step 2: Step Detection (Zero-Crossing)              │
│    ─ Positive-going zero crossings                   │
│    ─ Amplitude threshold: 0.3 × σ(signal)            │
│    ─ Minimum gap: 0.25 s (prevents double-counting)  │
│                                                      │
│  Step 3: Stride Metrics                              │
│    ─ Cadence = 60 / mean(inter-step intervals)       │
│    ─ CV% = σ(intervals) / mean(intervals) × 100      │
│                                                      │
│  Step 4: Freeze Index (Spectral)                     │
│    ─ FFT of de-trended signal                        │
│    ─ FI = Power(0.5–3 Hz) / Power(3–8 Hz)            │
│    ─ FI > 1.5 → Freezing of Gait detected            │
│                                                      │
│  Step 5: Classification                              │
│    ─ Priority: Freezing > Unstable > Normal           │
└──────────────────────────────────────────────────────┘
```

### 4.3 Freeze Index

The Freeze Index is the core innovation for FOG detection:

- **Freeze band (0.5–3 Hz):** Characteristic of the leg trembling that occurs during FOG episodes.
- **Locomotor band (3–8 Hz):** Normal walking step frequency.
- **FI = Freeze Power / Locomotor Power**

| FI Value | Interpretation |
|----------|---------------|
| < 1.0 | Normal walking |
| 1.0–1.5 | Borderline — monitor closely |
| > 1.5 | Freezing episode detected |

### 4.4 Classification Rules

| Condition | Threshold | Status |
|-----------|-----------|--------|
| Freeze Index > 1.5 | Highest priority | "Freezing detected" |
| Stride CV > 15% | High variability | "Unstable" |
| Cadence < 80 or > 140 | Abnormal pace | "Unstable" |
| All normal | — | "Normal" |

### 4.5 Output Format

```json
{
  "status": "Unstable",
  "feedback": "Your steps are uneven. Try to maintain a steady rhythm.",
  "cadence": 94.3,
  "stride_variability": 18.7,
  "freeze_index": 0.823,
  "step_count": 12
}
```

---

## 5. Dependencies

| Library | Version | Used By | Purpose |
|---------|---------|---------|---------|
| numpy | ≥ 1.26 | All modules | Array operations, linear algebra |
| scipy | ≥ 1.13 | TremorDetector, GaitAnalyzer | FFT, Butterworth filter, signal processing |
| scikit-learn | ≥ 1.5 | Future use | ML model integration (Random Forest, SVM) |

---

## 6. Future Improvements

1. **ML Model Integration:** Replace rule-based classifiers with trained Random Forest or LSTM models using collected patient data.
2. **Personalised Thresholds:** Adapt severity thresholds per-patient based on their baseline tremor profile.
3. **Medication Tracking:** Correlate tremor severity with medication timing (ON/OFF state).
4. **Fall Risk Score:** Combine gait metrics with tremor data for a composite fall-risk assessment.
