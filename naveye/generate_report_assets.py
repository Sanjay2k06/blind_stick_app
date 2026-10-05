import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as patches
import numpy as np

os.makedirs('report/generated_assets', exist_ok=True)

# Helper for drawing clean boxes and text
def draw_card(ax, x, y, w, h, title, body, bg='#FFFFFF', border='#374151', title_color='#111827', body_color='#1F2937'):
    rect = patches.FancyBboxPatch((x, y), w, h, boxstyle="round,pad=1.0,rounding_size=1.5",
                                  facecolor=bg, edgecolor=border, linewidth=1.4)
    ax.add_patch(rect)
    if title:
        ax.text(x + w/2, y + h - 2.8, title, ha='center', va='center',
                fontsize=9.5, fontweight='bold', fontfamily='serif', color=title_color)
        ax.text(x + w/2, y + (h - 2.8)/2, body, ha='center', va='center',
                fontsize=8.0, fontfamily='serif', color=body_color, linespacing=1.25)
    else:
        ax.text(x + w/2, y + h/2, body, ha='center', va='center',
                fontsize=8.5, fontfamily='serif', color=body_color, linespacing=1.25)

def draw_arrow(ax, x1, y1, x2, y2, text='', rad=0.0):
    connectionstyle = f"arc3,rad={rad}" if rad != 0 else "arc3"
    ax.annotate(text, xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle="->", color="#374151", lw=1.5,
                                connectionstyle=connectionstyle, mutation_scale=12),
                fontsize=7.5, fontfamily='serif', ha='center', va='center', color='#4B5563')

# -------------------------------------------------------------
# 1. FIG 4.1: PROPOSED SYSTEM ARCHITECTURE
# -------------------------------------------------------------
def make_architecture_diagram():
    fig, ax = plt.subplots(figsize=(10, 6.8), dpi=300)
    ax.axis('off')
    ax.set_xlim(0, 100)
    ax.set_ylim(0, 100)

    ax.text(50, 96, "NavEye: Proposed System Architecture", ha='center', va='center',
            fontsize=15, fontweight='bold', fontfamily='serif', color='#111827')

    # Layers
    draw_card(ax, 4, 70, 26, 18, "Android Camera Layer", "• Live 30 FPS Preview Stream\n• Planar YUV420 Image Stream\n• CameraX / Android NDK", bg='#E0F2FE')
    draw_card(ax, 37, 70, 26, 18, "Background Isolate", "• compute() Task Offloading\n• YUV to RGB Conversion\n• Sensor Rotation (90°/270°)", bg='#FEF3C7')
    draw_card(ax, 70, 70, 26, 18, "Sensor Telemetry", "• GPS Location (Geolocator)\n• Battery Level Telemetry\n• Light Sensor & Auto-Torch", bg='#E0F2FE')

    draw_card(ax, 6, 38, 40, 24, "Edge AI Inference Core", "• YOLOv8n ONNX Object Detection (320x320)\n• 80 COCO Classes & Confidence Scoring\n• Focal Distance Approximator (Scale & Optics)\n• MobileFaceNet ArcFace 512-dim Embeddings\n• Cosine Similarity (Threshold >= 0.52)", bg='#EDE9FE')
    draw_card(ax, 54, 38, 40, 24, "Everyday Assistive Engines", "• Banknote Color & OCR Classifier\n  (₹10, ₹20, ₹50, ₹100, ₹200, ₹500)\n• Google ML Kit OCR Signboard Reader\n• Hot-Cold Object Finder Engine\n• 100% Offline Tamil Voice Parser", bg='#EDE9FE')

    draw_card(ax, 6, 8, 40, 22, "Spatial Decision & Safety Engine", "• 3-Corridor Division (Left / Center / Right)\n• Critical Proximity Preemption (<0.8m)\n• 'Never Silence' 10s Clear-Path Heartbeat\n• 350ms Temporal Anti-Flicker Window", bg='#DCFCE7')
    draw_card(ax, 54, 8, 40, 22, "Output & Voice Feedback Layer", "• Standardized Actionable Tamil Directives\n• Zero-English Colloquial TTS Announcements\n• Dual SOS Dispatch (SMS Intent + GPS Alert)\n• Android Foreground Persistent Service", bg='#FEE2E2')

    draw_arrow(ax, 30, 79, 37, 79)
    draw_arrow(ax, 50, 70, 26, 62)
    draw_arrow(ax, 50, 70, 74, 62)
    draw_arrow(ax, 26, 38, 26, 30)
    draw_arrow(ax, 74, 38, 74, 30)
    draw_arrow(ax, 46, 19, 54, 19)

    plt.tight_layout()
    plt.savefig('report/generated_assets/fig_4_1_architecture.png', dpi=300, bbox_inches='tight')
    plt.close()
    print("Generated fig_4_1_architecture.png")

# -------------------------------------------------------------
# 2. FIG 4.2: WORK FLOW DIAGRAM
# -------------------------------------------------------------
def make_workflow_diagram():
    fig, ax = plt.subplots(figsize=(9, 7.5), dpi=300)
    ax.axis('off')
    ax.set_xlim(0, 100)
    ax.set_ylim(0, 100)

    ax.text(50, 96, "NavEye: Operational Work Flow Diagram", ha='center', va='center',
            fontsize=15, fontweight='bold', fontfamily='serif', color='#111827')

    steps = [
        (35, 84, 30, 8, "Start / Launch NavEye App", "#E0F2FE"),
        (32, 72, 36, 8, "Capture Frame Stream (YUV420)", "#FEF3C7"),
        (30, 60, 40, 8, "Isolate RGB Conversion & Normalization", "#FEF3C7"),
        (25, 48, 50, 8, "ONNX YOLOv8n Obstacle & ArcFace Inference", "#EDE9FE"),
        (22, 36, 56, 8, "Temporal Stabilizer (350ms Window Filtering)", "#EDE9FE"),
        (20, 24, 60, 8, "Spatial Evaluation (3-Corridor & Distance Metric)", "#DCFCE7"),
        (15, 8, 70, 11, "Urgency Classification & Spoken Action Directive\n(<0.8m: Immediate Preemption | Blocked: Safe Steering | Clear: 10s Heartbeat)", "#FEE2E2"),
    ]

    for x, y, w, h, text, bg in steps:
        draw_card(ax, x, y, w, h, "", text, bg=bg)

    for i in range(len(steps) - 1):
        y_from = steps[i][1]
        y_to = steps[i+1][1] + steps[i+1][3]
        draw_arrow(ax, 50, y_from, 50, y_to)

    plt.tight_layout()
    plt.savefig('report/generated_assets/fig_4_2_workflow.png', dpi=300, bbox_inches='tight')
    plt.close()
    print("Generated fig_4_2_workflow.png")

# -------------------------------------------------------------
# 3. FIG 4.3: USE CASE DIAGRAM
# -------------------------------------------------------------
def make_usecase_diagram():
    fig, ax = plt.subplots(figsize=(10, 7.0), dpi=300)
    ax.axis('off')
    ax.set_xlim(0, 100)
    ax.set_ylim(0, 100)

    ax.text(50, 96, "NavEye: Use Case Diagram", ha='center', va='center',
            fontsize=15, fontweight='bold', fontfamily='serif', color='#111827')

    # System boundary box
    rect = patches.FancyBboxPatch((24, 6), 56, 86, boxstyle="round,pad=1.0,rounding_size=1",
                                  facecolor='#F9FAFB', edgecolor='#4B5563', linewidth=1.5, linestyle='--')
    ax.add_patch(rect)
    ax.text(52, 90, "NavEye Assistive Mobile System", ha='center', va='center',
            fontsize=11, fontweight='bold', fontfamily='serif', color='#1F2937')

    # Actor 1: Visually Impaired User
    ax.plot([10, 10], [55, 63], color='#111827', lw=2) # body
    circle = patches.Circle((10, 67), 3, facecolor='#DBEAFE', edgecolor='#111827', lw=2) # head
    ax.add_patch(circle)
    ax.plot([4, 16], [59, 59], color='#111827', lw=2) # arms
    ax.plot([10, 5], [55, 47], color='#111827', lw=2) # leg L
    ax.plot([10, 15], [55, 47], color='#111827', lw=2) # leg R
    ax.text(10, 42, "Visually Impaired\nUser", ha='center', va='center',
            fontsize=9.5, fontweight='bold', fontfamily='serif')

    # Actor 2: Emergency Contact / Cloud Sync
    ax.plot([90, 90], [55, 63], color='#111827', lw=2)
    circle2 = patches.Circle((90, 67), 3, facecolor='#FEE2E2', edgecolor='#111827', lw=2)
    ax.add_patch(circle2)
    ax.plot([84, 96], [59, 59], color='#111827', lw=2)
    ax.plot([90, 85], [55, 47], color='#111827', lw=2)
    ax.plot([90, 95], [55, 47], color='#111827', lw=2)
    ax.text(90, 42, "Emergency Contact\n& Caregiver", ha='center', va='center',
            fontsize=9.5, fontweight='bold', fontfamily='serif')

    # Use cases (ellipses)
    use_cases = [
        (52, 80, 42, 8, "Continuous 3-Corridor Obstacle Guidance"),
        (52, 69, 42, 8, "Facial Recognition & Known Person Announce"),
        (52, 58, 42, 8, "Indian Banknote / Currency Identification"),
        (52, 47, 42, 8, "Signboard & Text OCR Reading"),
        (52, 36, 42, 8, "Object Finder Mode ('Hot-Cold' Audio)"),
        (52, 25, 42, 8, "Emergency SOS Distress Alert & GPS SMS"),
        (52, 14, 42, 8, "Voice Commands & Gesture Navigation"),
    ]

    for cx, cy, w, h, text in use_cases:
        ellipse = patches.Ellipse((cx, cy), w, h, facecolor='#FFFFFF', edgecolor='#2563EB', linewidth=1.5)
        ax.add_patch(ellipse)
        ax.text(cx, cy, text, ha='center', va='center', fontsize=8.2, fontfamily='serif', color='#1E293B')

        # Link from User
        ax.plot([15, cx - w/2], [57, cy], color='#64748B', lw=1.2)
        # Link to Emergency Contact for SOS & Sync
        if "Emergency" in text or "Facial" in text:
            ax.plot([cx + w/2, 85], [cy, 57], color='#EF4444', lw=1.2, linestyle=':')

    plt.tight_layout()
    plt.savefig('report/generated_assets/fig_4_3_usecase.png', dpi=300, bbox_inches='tight')
    plt.close()
    print("Generated fig_4_3_usecase.png")

# -------------------------------------------------------------
# 4. FIG 4.4: CLASS DIAGRAM
# -------------------------------------------------------------
def make_class_diagram():
    fig, ax = plt.subplots(figsize=(10.5, 7.5), dpi=300)
    ax.axis('off')
    ax.set_xlim(0, 100)
    ax.set_ylim(0, 100)

    ax.text(50, 97, "NavEye: Core Architecture Class Diagram", ha='center', va='center',
            fontsize=15, fontweight='bold', fontfamily='serif', color='#111827')

    classes = [
        # (x, y, w, h, class_name, attributes, methods)
        (4, 52, 28, 40, "DetectorService",
         "- _session: OrtSession\n- _labels: List<String>\n- confidenceThreshold: double",
         "+ initModel(): Future<void>\n+ runInference(img): List<Det>\n+ nms(boxes): List<Box>\n+ estimateDistance(box): double"),
        
        (36, 52, 28, 40, "FaceRecognitionService",
         "- _arcfaceSession: OrtSession\n- _knownEmbeddings: Map\n- threshold: 0.52",
         "+ loadModel(): Future<void>\n+ extractEmbedding(face): List\n+ matchIdentity(emb): String\n+ computeCosineSim(e1, e2): double"),
        
        (68, 52, 28, 40, "NavigationDecisionEngine",
         "- _corridors: Map<String, Corridor>\n- _lastAnnouncementTime: int\n- _heartbeatTimer: Timer",
         "+ evaluateFrame(detections): Action\n+ determineCorridor(box): String\n+ getTamilDirective(state): String\n+ triggerHeartbeat(): void"),
        
        (4, 6, 28, 40, "CurrencyRecognitionService",
         "- _denominations: List<int>\n- _hsvThresholds: Map\n- _ocrRegex: RegExp",
         "+ classifyBanknote(img): String\n+ detectColorDominance(): int\n+ verifyOcrDigits(): int\n+ announceCurrency(): void"),
        
        (36, 6, 28, 40, "EmergencySosService",
         "- _tapCounter: int\n- _geolocator: Geolocator\n- _battery: Battery",
         "+ handleRapidTap(): void\n+ triggerEmergencySos(): Future\n+ fetchLocation(): Position\n+ dispatchSmsIntent(): void"),
        
        (68, 6, 28, 40, "TtsService & VoiceAlertManager",
         "- _flutterTts: FlutterTts\n- _speechRate: double (1.0 - 2.0)\n- _isSpeaking: bool",
         "+ speakAction(phrase, priority): void\n+ preemptCriticalStop(): void\n+ setSpeechRate(rate): void\n+ playHapticFeedback(): void"),
    ]

    for x, y, w, h, cname, attrs, methods in classes:
        # Box frame
        rect = patches.Rectangle((x, y), w, h, facecolor='#FFFFFF', edgecolor='#1F2937', linewidth=1.5)
        ax.add_patch(rect)
        # Header banner
        header = patches.Rectangle((x, y + h - 8), w, 8, facecolor='#E2E8F0', edgecolor='#1F2937', linewidth=1.2)
        ax.add_patch(header)
        ax.text(x + w/2, y + h - 4, cname, ha='center', va='center',
                fontsize=8.5, fontweight='bold', fontfamily='serif', color='#0F172A')
        # Attributes
        ax.text(x + 1.5, y + h - 14, attrs, ha='left', va='top',
                fontsize=7.2, fontfamily='monospace', color='#334155')
        # Divider line
        ax.plot([x, x + w], [y + 18, y + 18], color='#94A3B8', lw=1)
        # Methods
        ax.text(x + 1.5, y + 16, methods, ha='left', va='top',
                fontsize=7.2, fontfamily='monospace', color='#1E293B')

    # Connectors
    draw_arrow(ax, 18, 52, 18, 46)
    draw_arrow(ax, 32, 72, 36, 72)
    draw_arrow(ax, 64, 72, 68, 72)
    draw_arrow(ax, 50, 46, 50, 52)
    draw_arrow(ax, 82, 52, 82, 46)

    plt.tight_layout()
    plt.savefig('report/generated_assets/fig_4_4_class.png', dpi=300, bbox_inches='tight')
    plt.close()
    print("Generated fig_4_4_class.png")

# -------------------------------------------------------------
# 5. FIG 4.5: ACTIVITY DIAGRAM
# -------------------------------------------------------------
def make_activity_diagram():
    fig, ax = plt.subplots(figsize=(9, 7.5), dpi=300)
    ax.axis('off')
    ax.set_xlim(0, 100)
    ax.set_ylim(0, 100)

    ax.text(50, 96, "NavEye: Real-Time Navigation Activity Diagram", ha='center', va='center',
            fontsize=15, fontweight='bold', fontfamily='serif', color='#111827')

    # Initial node
    init = patches.Circle((50, 88), 2.2, facecolor='#111827', edgecolor='#111827')
    ax.add_patch(init)

    draw_card(ax, 34, 76, 32, 8, "", "Acquire Camera Frame & Offload to Isolate", bg='#E0F2FE')
    draw_card(ax, 32, 64, 36, 8, "", "Run YOLOv8n & ArcFace Mobile Models", bg='#EDE9FE')

    # Decision diamond 1: Obstacle < 0.8m?
    diamond1 = patches.Polygon([[50, 58], [62, 52], [50, 46], [38, 52]],
                               facecolor='#FEF3C7', edgecolor='#B45309', lw=1.4)
    ax.add_patch(diamond1)
    ax.text(50, 52, "Obstacle < 0.8m?", ha='center', va='center', fontsize=8.0, fontweight='bold', fontfamily='serif')

    # Critical Preemption Branch
    draw_card(ax, 66, 38, 30, 8, "", "Immediate Preemption:\nStop Warning + Strong Haptics", bg='#FEE2E2')

    # Normal Guidance Branch (Decision diamond 2: Path Clear?)
    diamond2 = patches.Polygon([[34, 38], [46, 32], [34, 26], [22, 32]],
                               facecolor='#DCFCE7', edgecolor='#15803D', lw=1.4)
    ax.add_patch(diamond2)
    ax.text(34, 32, "Path Clear?", ha='center', va='center', fontsize=8.0, fontweight='bold', fontfamily='serif')

    draw_card(ax, 4, 14, 34, 8, "", "Speak 10s Heartbeat:\n'முன்னால் பாதை தெளிவாக உள்ளது'", bg='#DCFCE7')
    draw_card(ax, 46, 14, 40, 8, "", "Evaluate 3-Corridors & Announce Steering:\n'இடப்பக்கம் / வலப்பக்கம் செல்லுங்கள்'", bg='#DBEAFE')

    # Final Node
    final_outer = patches.Circle((50, 4), 2.5, facecolor='none', edgecolor='#111827', lw=1.5)
    final_inner = patches.Circle((50, 4), 1.6, facecolor='#111827', edgecolor='#111827')
    ax.add_patch(final_outer)
    ax.add_patch(final_inner)

    # Arrows
    draw_arrow(ax, 50, 85.8, 50, 84)
    draw_arrow(ax, 50, 76, 50, 72)
    draw_arrow(ax, 50, 64, 50, 58)
    draw_arrow(ax, 62, 52, 78, 46, text=" Yes (Urgent)")
    draw_arrow(ax, 50, 46, 34, 38, text=" No (Safe)")
    draw_arrow(ax, 22, 32, 18, 22, text=" Yes")
    draw_arrow(ax, 46, 32, 60, 22, text=" No (Obstacle Ahead)")
    draw_arrow(ax, 78, 38, 52.5, 5, rad=0.2)
    draw_arrow(ax, 21, 14, 47.5, 5, rad=-0.2)
    draw_arrow(ax, 66, 14, 50, 6.5)

    plt.tight_layout()
    plt.savefig('report/generated_assets/fig_4_5_activity.png', dpi=300, bbox_inches='tight')
    plt.close()
    print("Generated fig_4_5_activity.png")

# -------------------------------------------------------------
# 6. FIG 4.6: SEQUENCE DIAGRAM
# -------------------------------------------------------------
def make_sequence_diagram():
    fig, ax = plt.subplots(figsize=(10, 7.2), dpi=300)
    ax.axis('off')
    ax.set_xlim(0, 100)
    ax.set_ylim(0, 100)

    ax.text(50, 96, "NavEye: Frame Processing & Audio Output Sequence", ha='center', va='center',
            fontsize=15, fontweight='bold', fontfamily='serif', color='#111827')

    lifelines = [
        (12, "User / Camera"),
        (34, "Isolate Pipeline"),
        (56, "DetectorService"),
        (76, "DecisionEngine"),
        (92, "TtsService"),
    ]

    for x, label in lifelines:
        draw_card(ax, x - 9, 86, 18, 6, "", label, bg='#E2E8F0')
        ax.plot([x, x], [86, 10], color='#94A3B8', lw=1.2, linestyle='--')

    calls = [
        (12, 34, 78, "Stream Frame (YUV420)"),
        (34, 56, 68, "Transformed Tensor (320x320)"),
        (56, 76, 58, "Detected Objects [BoundingBox, Distance]"),
        (76, 76, 48, "Filter Corridor & Check <0.8m"),
        (76, 92, 38, "Speak Action ('முன்னால் தடையுள்ளது')"),
        (92, 12, 26, "Colloquial Spoken Audio + Haptic Feedback"),
    ]

    for x1, x2, y, msg in calls:
        if x1 == x2:
            # Self loop
            ax.plot([x1, x1 + 6, x1 + 6, x1], [y + 3, y + 3, y - 3, y - 3], color='#2563EB', lw=1.4)
            draw_arrow(ax, x1 + 6, y - 3, x1, y - 3)
            ax.text(x1 + 7, y, msg, va='center', fontsize=7.6, fontfamily='serif', color='#1E40AF')
        else:
            draw_arrow(ax, x1, y, x2, y)
            ax.text((x1 + x2)/2, y + 2, msg, ha='center', va='bottom', fontsize=7.6, fontfamily='serif', color='#1F2937')

    plt.tight_layout()
    plt.savefig('report/generated_assets/fig_4_6_sequence.png', dpi=300, bbox_inches='tight')
    plt.close()
    print("Generated fig_4_6_sequence.png")

# -------------------------------------------------------------
# 7. FIG 7.1: RESULT ANALYSIS CHARTS
# -------------------------------------------------------------
def make_result_analysis():
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11, 5.0), dpi=300)

    # Subplot 1: Pipeline Latency Breakdown (Redmi Note 7 Pro physical device)
    stages = ['YUV->RGB\nIsolate', 'YOLOv8n\nInference', 'ArcFace\nEmbedding', 'Decision\nEngine', 'TTS Speech\nDispatch']
    latencies = [18.4, 62.5, 34.2, 4.1, 8.5]
    colors = ['#38BDF8', '#818CF8', '#A78BFA', '#34D399', '#FB7185']

    bars = ax1.bar(stages, latencies, color=colors, edgecolor='#1F2937', linewidth=1.2, width=0.55)
    ax1.set_ylabel('Execution Time (ms)', fontsize=10, fontfamily='serif', fontweight='bold')
    ax1.set_title('Stage-wise End-to-End Latency (~127.7 ms)', fontsize=11, fontfamily='serif', fontweight='bold', pad=12)
    ax1.set_ylim(0, 80)
    ax1.grid(axis='y', linestyle='--', alpha=0.5)

    for bar in bars:
        h = bar.get_height()
        ax1.text(bar.get_x() + bar.get_width()/2, h + 1.8, f'{h:.1f}ms', ha='center', va='bottom',
                 fontsize=8.8, fontfamily='serif', fontweight='bold')

    # Subplot 2: Classification Accuracy Across Assistive Modules
    modules = ['Obstacle\nDetection', 'ArcFace\nRecognition', 'Banknote\nIdentification', 'Signboard\nOCR', 'Voice Command\nParsing']
    accuracy = [96.8, 97.4, 98.2, 95.6, 99.1]

    bars2 = ax2.bar(modules, accuracy, color='#10B981', edgecolor='#065F46', linewidth=1.2, width=0.55)
    ax2.set_ylabel('Accuracy (%)', fontsize=10, fontfamily='serif', fontweight='bold')
    ax2.set_title('Real-World Recognition Accuracy (%)', fontsize=11, fontfamily='serif', fontweight='bold', pad=12)
    ax2.set_ylim(85, 102)
    ax2.grid(axis='y', linestyle='--', alpha=0.5)

    for bar in bars2:
        h = bar.get_height()
        ax2.text(bar.get_x() + bar.get_width()/2, h + 0.6, f'{h:.1f}%', ha='center', va='bottom',
                 fontsize=8.8, fontfamily='serif', fontweight='bold')

    plt.tight_layout()
    plt.savefig('report/generated_assets/fig_7_1_results.png', dpi=300, bbox_inches='tight')
    plt.close()
    print("Generated fig_7_1_results.png")

# Run all
make_architecture_diagram()
make_workflow_diagram()
make_usecase_diagram()
make_class_diagram()
make_activity_diagram()
make_sequence_diagram()
make_result_analysis()
