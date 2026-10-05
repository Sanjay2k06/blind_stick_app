import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as patches

os.makedirs('report/generated_assets', exist_ok=True)

# -------------------------------------------------------------
# Re-generate diagrams without untyped font glyphs
# -------------------------------------------------------------
def make_activity_clean():
    fig, ax = plt.subplots(figsize=(9, 7.5), dpi=300)
    ax.axis('off')
    ax.set_xlim(0, 100)
    ax.set_ylim(0, 100)

    ax.text(50, 96, "NavEye: Real-Time Navigation Activity Diagram", ha='center', va='center',
            fontsize=15, fontweight='bold', fontfamily='serif', color='#111827')

    init = patches.Circle((50, 88), 2.2, facecolor='#111827', edgecolor='#111827')
    ax.add_patch(init)

    def draw_c(x, y, w, h, body, bg='#FFFFFF'):
        rect = patches.FancyBboxPatch((x, y), w, h, boxstyle="round,pad=1.0,rounding_size=1.5",
                                      facecolor=bg, edgecolor='#374151', linewidth=1.4)
        ax.add_patch(rect)
        ax.text(x + w/2, y + h/2, body, ha='center', va='center',
                fontsize=8.5, fontfamily='serif', color='#1F2937', linespacing=1.25)

    def draw_a(x1, y1, x2, y2, text='', rad=0.0):
        cstyle = f"arc3,rad={rad}" if rad != 0 else "arc3"
        ax.annotate(text, xy=(x2, y2), xytext=(x1, y1),
                    arrowprops=dict(arrowstyle="->", color="#374151", lw=1.5,
                                    connectionstyle=cstyle, mutation_scale=12),
                    fontsize=7.5, fontfamily='serif', ha='center', va='center', color='#4B5563')

    draw_c(34, 76, 32, 8, "Acquire Camera Frame & Offload to Isolate", bg='#E0F2FE')
    draw_c(32, 64, 36, 8, "Run YOLOv8n & ArcFace Mobile Models", bg='#EDE9FE')

    diamond1 = patches.Polygon([[50, 58], [62, 52], [50, 46], [38, 52]],
                               facecolor='#FEF3C7', edgecolor='#B45309', lw=1.4)
    ax.add_patch(diamond1)
    ax.text(50, 52, "Obstacle < 0.8m?", ha='center', va='center', fontsize=8.0, fontweight='bold', fontfamily='serif')

    draw_c(66, 38, 30, 8, "Immediate Preemption:\nStop Alert + Rapid Haptics", bg='#FEE2E2')

    diamond2 = patches.Polygon([[34, 38], [46, 32], [34, 26], [22, 32]],
                               facecolor='#DCFCE7', edgecolor='#15803D', lw=1.4)
    ax.add_patch(diamond2)
    ax.text(34, 32, "Path Clear?", ha='center', va='center', fontsize=8.0, fontweight='bold', fontfamily='serif')

    draw_c(4, 14, 34, 8, "Speak 10s Heartbeat Directive:\n'Path Ahead is Clear. Proceed.'", bg='#DCFCE7')
    draw_c(46, 14, 40, 8, "Evaluate 3 Corridors & Announce Steering:\n'Obstacle Ahead. Veer Left / Right'", bg='#DBEAFE')

    final_outer = patches.Circle((50, 4), 2.5, facecolor='none', edgecolor='#111827', lw=1.5)
    final_inner = patches.Circle((50, 4), 1.6, facecolor='#111827', edgecolor='#111827')
    ax.add_patch(final_outer)
    ax.add_patch(final_inner)

    draw_a(50, 85.8, 50, 84)
    draw_a(50, 76, 50, 72)
    draw_a(50, 64, 50, 58)
    draw_a(62, 52, 78, 46, text=" Yes (Urgent)")
    draw_a(50, 46, 34, 38, text=" No (Safe)")
    draw_a(22, 32, 18, 22, text=" Yes")
    draw_a(46, 32, 60, 22, text=" No (Obstacle Ahead)")
    draw_a(78, 38, 52.5, 5, rad=0.2)
    draw_a(21, 14, 47.5, 5, rad=-0.2)
    draw_a(66, 14, 50, 6.5)

    plt.tight_layout()
    plt.savefig('report/generated_assets/fig_4_5_activity.png', dpi=300, bbox_inches='tight')
    plt.close()

def make_sequence_clean():
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
        rect = patches.FancyBboxPatch((x - 9, 86), 18, 6, boxstyle="round,pad=1.0,rounding_size=1",
                                      facecolor='#E2E8F0', edgecolor='#374151', lw=1.2)
        ax.add_patch(rect)
        ax.text(x, 89, label, ha='center', va='center', fontsize=8.2, fontfamily='serif', fontweight='bold')
        ax.plot([x, x], [86, 10], color='#94A3B8', lw=1.2, linestyle='--')

    calls = [
        (12, 34, 78, "Stream Frame (YUV420 Planar)"),
        (34, 56, 68, "RGB Tensor Matrix (320x320)"),
        (56, 76, 58, "Detected Objects [BoundingBox, Distance]"),
        (76, 76, 48, "Filter Corridor & Check Proximity (<0.8m)"),
        (76, 92, 38, "Dispatch Action Directive ('Steer Left')"),
        (92, 12, 26, "Colloquial Spoken Audio + Haptic Feedback"),
    ]

    for x1, x2, y, msg in calls:
        if x1 == x2:
            ax.plot([x1, x1 + 6, x1 + 6, x1], [y + 3, y + 3, y - 3, y - 3], color='#2563EB', lw=1.4)
            ax.annotate('', xy=(x1, y - 3), xytext=(x1 + 6, y - 3),
                        arrowprops=dict(arrowstyle="->", color="#2563EB", lw=1.4, mutation_scale=12))
            ax.text(x1 + 7, y, msg, va='center', fontsize=7.6, fontfamily='serif', color='#1E40AF')
        else:
            ax.annotate('', xy=(x2, y), xytext=(x1, y),
                        arrowprops=dict(arrowstyle="->", color="#374151", lw=1.4, mutation_scale=12))
            ax.text((x1 + x2)/2, y + 2, msg, ha='center', va='bottom', fontsize=7.6, fontfamily='serif', color='#1F2937')

    plt.tight_layout()
    plt.savefig('report/generated_assets/fig_4_6_sequence.png', dpi=300, bbox_inches='tight')
    plt.close()

make_activity_clean()
make_sequence_clean()
print("Cleaned diagrams updated successfully.")
