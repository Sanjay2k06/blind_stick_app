# NavEye — Technical Stack, Models, Algorithms & Implementation Architecture

---

## 1. Executive System Overview

**NavEye** is an edge-native, real-time AI assistive navigation system designed for visually impaired and blind individuals. The system operates entirely on-device with zero-latency requirements for safety-critical collision avoidance, spatial corridor analysis, face identification (e.g., enrolled profile "Loki"), and deterministic actionable voice guidance.

```mermaid
flowchart TD
    subgraph SENSORS ["Sensor & Input Layer"]
        CAM[Camera Stream\nCameraX / Camera2 NV21]
        IMU[IMU Sensors\nAccelerometer & Gyroscope]
        GPS[GPS Receiver\nGeolocator Provider]
    end

    subgraph INFERENCE ["Edge AI & Vision Pipeline"]
        YOLO[YOLOv8n Object Detector\nONNX Runtime 320x320 / 640x640]
        NMS[Non-Maximum Suppression\nIoU 0.45, Conf >= 0.35]
        PINHOLE[Pinhole Distance & Depth Engine\nD = f * H_real / h_eff]
        STAB[Temporal Stabilizer & Tracker\nEuclidean Centroid + 2000ms Grace]
        MLKIT[Google ML Kit Face Detector\nLandmarks & Accurate Mode]
        ALIGN[Affine Face Aligner\nEye-Angle Horizontal Rotation]
        FACENET[MobileFaceNet ArcFace\nONNX Runtime 112x112 -> 512-d]
        METRIC[Multi-Reference Cosine Matcher\nCentroid + Top-K Averaging]
    end

    subgraph REASONING ["Spatial Reasoning & Decision Engine"]
        CORRIDOR[3-Corridor Horizontal Spatial Partition\nLeft < 0.35 | Center 0.35-0.65 | Right > 0.65]
        HYST[Boundary Hysteresis\nDelta = 0.04 Band Guard]
        DEB[Temporal Action Debounce\n350ms State Stability]
        DECIDE[Navigation Decision Engine\nFree-Space Evading Vector]
    end

    subgraph OUTPUT ["Centralized Output & State Machine"]
        VAM[VoiceAlertManager\nState Machine & Cooldown Queue]
        PREEMPT[Priority Preemption Queue\nCritical Stop > Evasive > Identity]
        TTS[Flutter TTS Engine\nEnglish en-US & Tamil ta-IN]
        HAPTIC[Vibration Engine\nMulti-Pattern Haptic Feedback]
        FGS[Android Foreground Service\nOngoing Notification & Watchdog]
    end

    subgraph STORAGE ["Offline-First Persistence & Sync"]
        SQLITE[(SQLite 3 sqflite\nPersons, Encounters, Events)]
        SUPABASE[(Supabase Cloud\nPostgreSQL & Storage Bucket)]
    end

    CAM --> YOLO --> NMS --> PINHOLE --> STAB
    STAB -->|Person Detected| MLKIT --> ALIGN --> FACENET --> METRIC
    METRIC --> STAB
    STAB --> CORRIDOR --> HYST --> DEB --> DECIDE
    DECIDE --> VAM --> PREEMPT --> TTS
    DECIDE --> HAPTIC
    DECIDE --> FGS
    METRIC --> SQLITE <--> SUPABASE
    IMU --> DECIDE
    GPS --> SQLITE
```

---

## 2. Technology Stack & Frameworks

| Layer | Component | Technologies / Libraries | Purpose & Configuration |
| :--- | :--- | :--- | :--- |
| **Framework** | Mobile SDK | **Flutter (Channel Stable, Dart 3.x)** | Cross-platform high-performance reactive UI and native channel orchestration. |
| **Edge Runtime** | Model Inference | **ONNX Runtime (`onnxruntime: ^1.4.0`)** | Native C++ execution engine utilizing CPU / NNAPI hardware acceleration for YOLO and MobileFaceNet models. |
| **Computer Vision** | Face Landmark & Detection | **Google ML Kit (`google_mlkit_face_detection: ^0.13.1`)** | Accurate landmark extraction (pupils, nose tip, mouth) used for face bounding and rotation alignment. |
| **Image Processing** | Geometry & Crops | **Dart Image (`image: ^4.5.4`)** | High-performance pixel manipulation, bicubic/linear resizing, YUV-to-RGB conversion, and NCHW tensor construction. |
| **Local Database** | Relational Store | **SQLite 3 (`sqflite: ^2.4.2`, `path: ^1.9.1`)** | Zero-latency local storage for profiles, 5120-d embedding vectors, encounter logs, and navigation telemetry. |
| **Cloud Backend** | Offline-First Sync | **Supabase (`supabase_flutter: ^2.17.2`)** | Cloud persistence of encounter audit trails, face references, and remote profiles with sync queue backoff. |
| **Speech (TTS)** | Centralized Audio | **Flutter TTS (`flutter_tts: ^4.2.3`)** | Dual-language speech synthesizer supporting `en-US` and `ta-IN` with explicit completion handlers. |
| **Sensors** | Spatial & Kinematics | **Sensors Plus (`sensors_plus: ^4.0.2`)** | Real-time tri-axial accelerometer and gyroscope analysis for user movement and fall detection. |
| **Location** | Spatial Coordinate | **Geolocator (`geolocator: ^13.0.4`)** | GPS coordinate acquisition for geotagging encounter histories (e.g. Kodambakkam, Chennai). |
| **Background Ops** | OS Keep-Alive | **Foreground Task (`flutter_foreground_task: ^8.18.0`)** | Android Foreground Service maintaining camera inference and speech alerts even when minimized. |
| **Haptics** | Tactile Feedback | **Vibration (`vibration: ^3.1.5`)** | Multi-pattern haptic impulses for emergency stops, critical walls, and confirmed person alerts. |

---

## 3. Deep Learning Models & Neural Architectures

### 3.1. Real-Time Object Detection: YOLOv8n / YOLOv11n
- **Model Path**: [`assets/models/yolov8n.onnx`](file:///c:/Users/sanjay/OneDrive/Desktop/blinded-git/naveye/naveye/assets/models/yolov8n.onnx) / [`assets/models/yolo.onnx`](file:///c:/Users/sanjay/OneDrive/Desktop/blinded-git/naveye/naveye/assets/models/yolo.onnx)
- **Input Tensor**: `float32 [1, 3, 320, 320]` (or `[1, 3, 640, 640]`) in **BCHW** format. Pixel values scaled linearly to $[0.0, 1.0]$ via $p / 255.0$.
- **Output Tensor**: `float32 [1, 84, 2100]`
  - $84 = 4 \text{ bounding box coordinates } [c_x, c_y, w, h] + 80 \text{ COCO class scores}$.
  - $2100 = \text{number of anchorless candidate predictions}$.
- **Supported Classes**: Full 80 COCO categories with prioritized weighting for:
  - *Pedestrians & People*: `person`
  - *Vehicles (High Danger)*: `car`, `motorcycle`, `bus`, `truck`, `bicycle`, `train`
  - *Trip & Collision Obstacles*: `chair`, `couch`, `dining table`, `bench`, `door`, `stairs`, `fire hydrant`
  - *Personal Tech & Indoor Items*: `laptop`, `cell phone`, `bottle`, `backpack`
- **Inference Optimization**: Post-processed with Non-Maximum Suppression (NMS) with an IoU threshold of $0.45$ and confidence threshold of $0.35$.

### 3.2. Facial Landmark & Geometry: Google ML Kit
- **Detector Configuration**:
  - `performanceMode: FaceDetectorMode.accurate`
  - `enableLandmarks: true` (extracts left eye, right eye, nose base, left mouth corner, right mouth corner)
  - `minFaceSize: 0.07` (enables detection of faces at distances up to 4 meters)

### 3.3. Deep Face Representation: MobileFaceNet (ArcFace)
- **Model Path**: [`assets/models/mobilefacenet.onnx`](file:///c:/Users/sanjay/OneDrive/Desktop/blinded-git/naveye/naveye/assets/models/mobilefacenet.onnx)
- **Architecture**: Inverted residual bottlenecks with depthwise separable convolutions optimized for real-time mobile inference.
- **Trained Objective**: Additive Angular Margin Loss (ArcFace) on WebFace600K / MS1MV2 datasets.
- **Input Tensor**: `float32 [1, 3, 112, 112]` in **NCHW** format.
  - Normalization: $(p / 255.0 - 0.5) / 0.5 \in [-1.0, 1.0]$.
- **Output Tensor**: `float32 [1, 512]` — 512-dimensional feature embedding vector lying on a hypersphere.
- **Normalization**: Post-inference $L_2$ normalization:
  $$\hat{\mathbf{v}} = \frac{\mathbf{v}}{\|\mathbf{v}\|_2} = \frac{\mathbf{v}}{\sqrt{\sum_{i=1}^{512} v_i^2}}$$

---

## 4. Computer Vision Algorithms & Geometric Methods

### 4.1. Facial Landmark Affine Alignment
Before passing a detected face to MobileFaceNet, the crop is aligned to correct for head roll:
1. Extract coordinates of the left eye $(x_L, y_L)$ and right eye $(x_R, y_R)$.
2. Compute the roll angle $\theta$:
   $$\theta = \text{atan2}(y_R - y_L, x_R - x_L) \times \frac{180}{\pi}$$
3. If $|\theta| \in [1^\circ, 45^\circ]$, perform affine rotation of the crop by $\theta$ degrees around the inter-ocular center.
4. Apply 30% contextual padding ($0.30 \cdot w_{box}$, $0.30 \cdot h_{box}$) to capture forehead and chin features before resizing to $112 \times 112$.

### 4.2. Monocular Pinhole Distance Estimation
Calculates real-world distance without requiring specialized ToF or LiDAR sensors:
$$D = \frac{f \times H_{\text{real}}}{h_{\text{eff}}}$$
- $f$: Approximate focal length coefficient ($f \approx 0.866$).
- $H_{\text{real}}$: Real-world physical height heuristic from prior empirical distribution:
  - `person`: $1.70\text{ m}$
  - `car`: $1.50\text{ m}$
  - `bus` / `truck`: $2.80\text{ m}$
  - `chair`: $0.85\text{ m}$
  - `laptop`: $0.25\text{ m}$
  - `cell phone` / `bottle`: $0.15\text{ m}$
- $h_{\text{eff}}$: Effective normalized bounding height adjusted for aspect ratios:
  $$h_{\text{eff}} = \max\left(h_{\text{box}}, 0.6 \cdot w_{\text{box}}\right)$$
- Output range clamped between $0.3\text{ m}$ and $15.0\text{ m}$.

### 4.3. Wall & Massive Obstacle Heuristic
Detects physical walls, large barriers, and structural boundaries that do not match specific object labels:
- An object is classified as a wall obstacle if:
  $$\text{class} \notin \{\text{'person'}, \text{'laptop'}, \text{'cell phone'}, \text{'remote'}, \text{'book'}\} \quad \land \quad w_{\text{box}} > 0.68 \quad \land \quad D < 2.0\text{ m}$$
- Triggers immediate critical emergency warning (*"Obstacle very close ahead. Stop and wait."*).

---

## 5. Spatial Reasoning & Navigation Decision Engine

### 5.1. 3-Corridor Horizontal Field-of-View Partitioning
The camera frame width ($W$) is normalized to $x \in [0.0, 1.0]$ and divided into 3 discrete spatial corridors:

$$\text{Corridor}(x) = \begin{cases} 
\mathbf{LEFT} & x < 0.35 \\
\mathbf{CENTER} & 0.35 \le x \le 0.65 \\
\mathbf{RIGHT} & x > 0.65 
\end{cases}$$

### 5.2. Boundary Hysteresis Algorithm
To prevent flickering between directions when an obstacle is near the boundary:
- A guard band $\delta = 0.04$ is enforced:
  - Transition from `CENTER` to `LEFT` requires $x < (0.35 - 0.04) = 0.31$.
  - Transition from `LEFT` to `CENTER` requires $x \ge (0.35 + 0.04) = 0.39$.
  - Transition from `CENTER` to `RIGHT` requires $x > (0.65 + 0.04) = 0.69$.
  - Transition from `RIGHT` to `CENTER` requires $x \le (0.65 - 0.04) = 0.61$.

### 5.3. Spatial Corridor Occupancy & Avoidance Reasoning
Obstacle bounds $[x_{\min}, x_{\max}]$ evaluate corridor blockages across three channels (`leftBlocked`, `centerBlocked`, `rightBlocked`):

```
+-------------------+-------------------+-------------------+
|   LEFT CORRIDOR   |  CENTER CORRIDOR  |  RIGHT CORRIDOR   |
|     (0.0 - 0.35)  |   (0.35 - 0.65)   |   (0.65 - 1.0)    |
+-------------------+-------------------+-------------------+
```

1. **Center Corridor Blocked**:
   - If `!leftBlocked && rightBlocked` $\longrightarrow$ **"Move left."**
   - If `!rightBlocked && leftBlocked` $\longrightarrow$ **"Move right."**
   - If `!leftBlocked && !rightBlocked` $\longrightarrow$ Evaluates safer side (default: **"Move left."**)
   - If `leftBlocked && rightBlocked` $\longrightarrow$ **"Stop and wait."**
2. **Side Corridors Blocked (Center Clear)**:
   - If `leftBlocked && !rightBlocked` $\longrightarrow$ **"Move right."**
   - If `rightBlocked && !leftBlocked` $\longrightarrow$ **"Move left."**
3. **Emergency Distance Rule**:
   - If $D < 0.9\text{ m}$ in center corridor or $A_{\text{rel}} \ge 0.18$ $\longrightarrow$ Immediate **"Stop and wait."**

### 5.4. Temporal Smoothing & Action Debounce
- **Tracking Grace Period**: Objects retain identity across frames for up to $2000\text{ ms}$ if temporarily occluded.
- **Directional Debounce**: Non-emergency action transitions require stability for $\ge 350\text{ ms}$.
- **Emergency Bypass**: Any transition to `NavigationAction.stop` bypasses debounce timers and fires instantly ($0\text{ ms}$).

---

## 6. Multi-Reference Face Recognition & Metric Learning

### 6.1. Enrolled Profile Structure (Loki)
Instead of relying on a single reference photo, each enrolled profile stores multiple reference embeddings ($N = 10$) representing varied angles, expressions, and lighting conditions:
- Enrolled Name: `Loki`
- Stored Vector: Concatenated $10 \times 512 = 5,120$ float values stored as binary blobs in SQLite.
- Registration Metadata: Date `28-09-2026 10:30 AM`, Location `Kodambakkam, Chennai`.

### 6.2. Dual-Component Scoring Metric
A live query embedding $\mathbf{q} \in \mathbb{R}^{512}$ is scored against the enrolled set $\{\mathbf{e}_1, \dots, \mathbf{e}_{10}\}$ using a composite similarity function:

$$S(\mathbf{q}) = 0.5 \cdot \text{CosineSim}(\mathbf{q}, \mathbf{c}) + 0.5 \cdot \left(\frac{1}{K} \sum_{k=1}^K \text{CosineSim}(\mathbf{q}, \mathbf{e}_{(k)})\right)$$

Where:
- $\mathbf{c} = \frac{\sum_{i=1}^N \mathbf{e}_i}{\|\sum_{i=1}^N \mathbf{e}_i\|_2}$ is the normalized centroid of the enrolled cluster.
- $\mathbf{e}_{(k)}$ are the top $K$ closest individual reference vectors ($K = \min(3, N)$).
- $\text{CosineSim}(\mathbf{u}, \mathbf{v}) = \frac{\mathbf{u} \cdot \mathbf{v}}{\|\mathbf{u}\|_2 \|\mathbf{v}\|_2} = \sum_{j=1}^{512} u_j v_j$ (since vectors are unit-normalized).

### 6.3. Decision Boundary & Ambiguity Margin
Identity confirmation requires meeting three distinct mathematical criteria:
1. **Absolute Similarity**: $S(\mathbf{q}) \ge \tau_{\text{sim}}$ ($\tau_{\text{sim}} = 0.50$).
2. **Ambiguity Margin**: $S_{\text{best}} - S_{\text{second}} \ge \delta_{\text{margin}}$ ($\delta_{\text{margin}} = 0.08$). When only one profile is enrolled, $S_{\text{second}}$ defaults to baseline $0.30$.
3. **Temporal Verification**: Identity must match for $\ge 2$ consecutive frames before confirming `person_Loki`.

---

## 7. Audio Narration & Centralized State Machine

### 7.1. Three-Part Natural Grammar
All spoken announcements adhere strictly to a deterministic, actionable format:

$$\mathbf{[OBJECT]} \;+\; \mathbf{[POSITION]} \;+\; \mathbf{[ACTION]}$$

| Scenario | Spoken English Alert (`en-US`) | Spoken Tamil Alert (`ta-IN`) |
| :--- | :--- | :--- |
| Laptop ahead, left path clear | `"Laptop ahead. Move left."` | `"மடிக்கணினி முன்னால் உள்ளது. இடதுபுறம் செல்லுங்கள்."` |
| Chair on left side | `"Chair on your left. Move right."` | `"நாற்காலி உங்கள் இடதுபுறம் உள்ளது. வலதுபுறம் செல்லுங்கள்."` |
| Enrolled Person (Loki) ahead | `"Loki ahead. Move left."` | `"Loki முன்னால் உள்ளது. இடதுபுறம் செல்லுங்கள்."` |
| Person on right side | `"Person on your right. Move left."` | `"நபர் உங்கள் வலதுபுறம் உள்ளது. இடதுபுறம் செல்லுங்கள்."` |
| Barrier directly ahead ($<0.9\text{m}$) | `"Obstacle very close ahead. Stop and wait."` | `"தடை முன்னால் மிக அருகில் உள்ளது. நில்லுங்கள்."` |

### 7.2. Priority Preemption Hierarchy
Incoming alerts pass through `VoiceAlertManager`:

```
Priority 0: Critical Stop (Emergency wall / vehicle < 2m) -> INTERRUPTS CURRENT SPEECH
Priority 1: Directional Evasive Action (Obstacle Ahead -> Move Left / Right)
Priority 2: Known Person Recognition (Loki identity announcement)
Priority 3: Normal Informational Object Detection
```

### 7.3. Duplicate Suppression & Continuous Detection
- **Continuous Detection**: Camera capture and ONNX neural inference run continuously at native frame rates without stopping after speaking.
- **State Machine Duplicate Suppression**:
  - The system computes an active state key: `stateKey = spokenTextEn`.
  - When state is unchanged: `MONITORING SILENTLY` — voice is suppressed.
  - When state changes (e.g., Loki moves from center to left, or an obstacle approaches): the new instruction is spoken immediately.
- **Watchdog Recovery**: An internal timer ($1,800\text{ ms}$) automatically releases the TTS lock if the operating system fails to fire completion callbacks.

---

## 8. Data Schema & Persistence

### 8.1. SQLite Relational Schema (`naveye.db`)

#### Table: `persons`
```sql
CREATE TABLE persons (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  image_path TEXT NOT NULL,
  created_at TEXT NOT NULL,
  last_seen_at TEXT,
  last_seen_latitude REAL,
  last_seen_longitude REAL,
  location_name TEXT,
  reference_images TEXT,        -- JSON encoded list of image paths
  embedding TEXT,               -- Concatenated 5120-d float list
  consent_status TEXT,
  consent_timestamp TEXT
);
```

#### Table: `person_encounters`
```sql
CREATE TABLE person_encounters (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  person_id INTEGER NOT NULL,
  timestamp TEXT NOT NULL,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  confidence REAL NOT NULL,
  source TEXT NOT NULL,         -- 'camera', 'registration', 'manual'
  FOREIGN KEY (person_id) REFERENCES persons(id) ON DELETE CASCADE
);
```

#### Table: `event_history`
```sql
CREATE TABLE event_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  event_type TEXT NOT NULL,     -- 'obstacle', 'person', 'fall', 'warning'
  description TEXT NOT NULL,
  severity TEXT NOT NULL,       -- 'info', 'warning', 'critical'
  timestamp TEXT NOT NULL,
  latitude REAL,
  longitude REAL
);
```

---

## 9. Verification & Performance Benchmarks

- **Target Device Tested**: Redmi Note 7 Pro (Snapdragon 675, Android 10, API 29).
- **Inference Latency**:
  - YOLOv8n ($320 \times 320$): $\approx 42 - 68\text{ ms}$ / frame.
  - MobileFaceNet ($112 \times 112$): $\approx 18 - 26\text{ ms}$ / face crop.
  - Google ML Kit Face Landmark: $\approx 25 - 35\text{ ms}$.
- **Pipeline Frame Rate**: Sustained $12 - 16\text{ FPS}$ continuous real-time navigation.
- **Unit & Integration Test Coverage**: **32/32 tests passing** (`flutter test`).
- **Static Analysis**: **0 issues found** (`flutter analyze`).
