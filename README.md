# Veyra

### AI-Powered Real-Time Navigation and Assistance System for Visually Impaired Users

Veyra is an AI-powered Android navigation and assistance application designed to help visually impaired users understand and navigate their surroundings more safely and independently.

The system combines real-time computer vision, object detection, face recognition, GPS-based location awareness, Tamil voice guidance, and intelligent navigation logic into a single mobile application.

Veyra continuously analyzes the environment through the smartphone camera, identifies obstacles and known individuals, determines their relative direction, and provides clear Tamil voice instructions to help the user navigate.

---

## Key Features

- Real-time obstacle detection using computer vision
- Direction-aware navigation guidance
- Tamil-only voice navigation using `ta-IN`
- Real-time camera-based environment analysis
- Known-person recognition
- Face enrollment with multiple reference images
- GPS-based location detection
- Reverse geocoding for natural location announcements
- Current time announcement
- Tamil text-to-speech feedback
- Audio startup experience
- SQLite-based local data storage
- On-device processing for core navigation functionality
- Accessibility-focused user interface
- Continuous navigation state management
- Voice announcement stabilization to avoid repeated messages
- Offline-first architecture for core functionality

---

## Navigation Logic

Veyra analyzes the position of detected obstacles inside the camera frame.

| Detection | Voice Guidance |
|---|---|
| Center obstacle | முன்னால் தடையுள்ளது. இடப்பக்கம் செல்லுங்கள். |
| Left obstacle | இடப்பக்கம் தடையுள்ளது. வலப்பக்கம் செல்லுங்கள். |
| Right obstacle | வலப்பக்கம் தடையுள்ளது. இடப்பக்கம் செல்லுங்கள். |
| Clear path | முன்னால் பாதை தெளிவாக உள்ளது. செல்லலாம். |
| Critical obstacle | முன்னால் தடையுள்ளது. நின்றுவிடுங்கள். |

The system uses temporal stabilization and announcement suppression so that the same navigation message is not repeatedly spoken for every camera frame.

---

## Startup Flow

When the user opens Veyra:

1. Veyra startup screen is displayed.
2. Startup background music begins.
3. The application waits for approximately 15 seconds.
4. Startup music stops.
5. GPS location is obtained.
6. The location is converted into a human-readable location name.
7. The current location is announced in Tamil.
8. The current local time is announced in Tamil.
9. Camera processing starts.
10. Object detection and navigation begin.

Camera detection and navigation remain disabled during the startup sequence to avoid unnecessary processing and voice overlap.

---

## Known Person Recognition

Veyra supports recognition of previously enrolled individuals.

The current recognition system uses:

- MobileFaceNet
- ONNX Runtime
- Face embeddings
- Cosine similarity
- Multiple reference images
- Temporal verification
- Recognition confidence thresholds

Known-person recognition is designed to avoid identifying unknown individuals without enrollment.

---

## Technology Stack

### Mobile Application

- Flutter
- Dart
- Android
- Material UI / Custom Flutter UI

### Artificial Intelligence

- YOLO / Object Detection
- MobileFaceNet
- ONNX Runtime
- Computer Vision
- Face Embeddings
- Cosine Similarity

### Local Storage

- SQLite

### Location

- GPS
- Reverse Geocoding

### Voice

- Tamil Text-to-Speech
- Tamil locale: `ta-IN`

### Audio

- Flutter audio playback
- Local startup audio assets

---

## Architecture

```text
                    VEYRA
                      │
          ┌───────────┴───────────┐
          │                       │
       Flutter                 AI Engine
          │                       │
          │              ┌────────┴────────┐
          │              │                 │
       Camera          YOLO          Face Recognition
          │              │                 │
          └──────────────┴─────────────────┘
                         │
                  Navigation Engine
                         │
             ┌───────────┼───────────┐
             │           │           │
            GPS         SQLite      TTS
             │           │           │
             └───────────┴───────────┘
                         │
                  Tamil Voice Guidance
