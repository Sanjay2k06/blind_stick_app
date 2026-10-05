import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as patches

os.makedirs('report/generated_assets/screenshots', exist_ok=True)

def create_phone_frame(title, subtitle=""):
    fig, ax = plt.subplots(figsize=(4.0, 7.0), dpi=250)
    ax.axis('off')
    ax.set_xlim(0, 100)
    ax.set_ylim(0, 175)

    # Phone casing (Dark sleek smartphone)
    case = patches.FancyBboxPatch((2, 2), 96, 171, boxstyle="round,pad=1.5,rounding_size=6",
                                  facecolor='#09090B', edgecolor='#27272A', lw=3.0)
    ax.add_patch(case)

    # Screen area (High-Contrast Black UI WCAG AAA)
    screen = patches.FancyBboxPatch((5, 10), 90, 155, boxstyle="round,pad=0.5,rounding_size=3",
                                    facecolor='#000000', edgecolor='#3F3F46', lw=1.2)
    ax.add_patch(screen)

    # Notch / Camera pill
    notch = patches.FancyBboxPatch((40, 160), 20, 3, boxstyle="round,pad=0.2,rounding_size=1.5",
                                   facecolor='#18181B', edgecolor='#27272A', lw=0.5)
    ax.add_patch(notch)

    # Top Status Bar
    ax.text(10, 158, "09:41", color='#A1A1AA', fontsize=7, fontweight='bold', fontfamily='sans-serif')
    ax.text(80, 158, "100% 5G", color='#A1A1AA', fontsize=6.5, fontfamily='sans-serif')

    # App Header
    ax.text(50, 150, title.upper(), color='#FFFFFF', fontsize=9.5, fontweight='bold', ha='center', fontfamily='sans-serif')
    if subtitle:
        ax.text(50, 144, subtitle, color='#A1A1AA', fontsize=6.8, ha='center', fontfamily='sans-serif')

    return fig, ax

# 1. Navigation Screen
def make_nav_screen():
    fig, ax = create_phone_frame("NavEye Assist", "Continuous 3-Corridor Guidance")
    
    # Camera Viewfinder Area
    vf = patches.Rectangle((8, 38), 84, 100, facecolor='#18181B', edgecolor='#52525B', lw=1)
    ax.add_patch(vf)

    # 3 Corridor Guide Lines
    ax.plot([36, 36], [38, 138], color='#3F3F46', linestyle='--', lw=1)
    ax.plot([64, 64], [38, 138], color='#3F3F46', linestyle='--', lw=1)
    ax.text(22, 133, "LEFT", color='#71717A', fontsize=6.5, ha='center')
    ax.text(50, 133, "CENTER", color='#71717A', fontsize=6.5, ha='center')
    ax.text(78, 133, "RIGHT", color='#71717A', fontsize=6.5, ha='center')

    # Obstacle Bounding Box
    bbox = patches.Rectangle((42, 60), 32, 50, facecolor='none', edgecolor='#22C55E', lw=2)
    ax.add_patch(bbox)
    tag = patches.Rectangle((42, 110), 32, 8, facecolor='#22C55E')
    ax.add_patch(tag)
    ax.text(58, 114, "CHAIR • 1.4m", color='#000000', fontsize=6.5, fontweight='bold', ha='center')

    # Spoken Audio Directive Card at Bottom
    card = patches.FancyBboxPatch((8, 14), 84, 20, boxstyle="round,pad=0.8,rounding_size=2",
                                  facecolor='#27272A', edgecolor='#FFFFFF', lw=1.2)
    ax.add_patch(card)
    ax.text(50, 26, "AUDIO DIRECTIVE", color='#22C55E', fontsize=6.5, fontweight='bold', ha='center')
    ax.text(50, 18, "\"Ahead path is clear. Veer Right.\"", color='#FFFFFF', fontsize=7.2, fontweight='bold', ha='center')

    plt.tight_layout()
    plt.savefig('report/generated_assets/screenshots/screenshot_1_camera_navigation.png', dpi=250, bbox_inches='tight')
    plt.close()

# 2. Face Recognition Screen
def make_face_screen():
    fig, ax = create_phone_frame("Person Recognition", "MobileFaceNet ArcFace 512-D")

    vf = patches.Rectangle((8, 38), 84, 100, facecolor='#18181B', edgecolor='#52525B', lw=1)
    ax.add_patch(vf)

    # Face box
    bbox = patches.Rectangle((32, 65), 36, 45, facecolor='none', edgecolor='#38BDF8', lw=2)
    ax.add_patch(bbox)
    tag = patches.Rectangle((32, 110), 36, 12, facecolor='#38BDF8')
    ax.add_patch(tag)
    ax.text(50, 117, "LOKI (VERIFIED)", color='#000000', fontsize=6.8, fontweight='bold', ha='center')
    ax.text(50, 112, "Similarity: 0.88 >= 0.52", color='#000000', fontsize=5.5, ha='center')

    # Audio Directive Card
    card = patches.FancyBboxPatch((8, 14), 84, 20, boxstyle="round,pad=0.8,rounding_size=2",
                                  facecolor='#27272A', edgecolor='#38BDF8', lw=1.2)
    ax.add_patch(card)
    ax.text(50, 26, "KNOWN PERSON DETECTED", color='#38BDF8', fontsize=6.5, fontweight='bold', ha='center')
    ax.text(50, 18, "\"Loki is standing in front at 1.2m\"", color='#FFFFFF', fontsize=7.2, fontweight='bold', ha='center')

    plt.tight_layout()
    plt.savefig('report/generated_assets/screenshots/screenshot_2_face_recognition.png', dpi=250, bbox_inches='tight')
    plt.close()

# 3. Currency Identifier Screen
def make_currency_screen():
    fig, ax = create_phone_frame("Banknote Identifier", "Color Palette & OCR Matching")

    vf = patches.Rectangle((8, 38), 84, 100, facecolor='#18181B', edgecolor='#52525B', lw=1)
    ax.add_patch(vf)

    # Note representation
    note = patches.Rectangle((20, 65), 60, 36, facecolor='#71717A', edgecolor='#D4D4D8', lw=1.5)
    ax.add_patch(note)
    ax.text(50, 83, "₹ 500", color='#FFFFFF', fontsize=16, fontweight='bold', ha='center')
    ax.text(50, 72, "RESERVE BANK OF INDIA", color='#E4E4E7', fontsize=5.0, ha='center')

    # Audio Card
    card = patches.FancyBboxPatch((8, 14), 84, 20, boxstyle="round,pad=0.8,rounding_size=2",
                                  facecolor='#27272A', edgecolor='#FACC15', lw=1.2)
    ax.add_patch(card)
    ax.text(50, 26, "BANKNOTE CONFIRMED", color='#FACC15', fontsize=6.5, fontweight='bold', ha='center')
    ax.text(50, 18, "\"Five Hundred Rupees Note (₹500)\"", color='#FFFFFF', fontsize=7.2, fontweight='bold', ha='center')

    plt.tight_layout()
    plt.savefig('report/generated_assets/screenshots/screenshot_3_currency_identifier.png', dpi=250, bbox_inches='tight')
    plt.close()

# 4. Signboard Reader Screen
def make_signboard_screen():
    fig, ax = create_phone_frame("Signboard Reader", "Google ML Kit On-Device OCR")

    vf = patches.Rectangle((8, 38), 84, 100, facecolor='#18181B', edgecolor='#52525B', lw=1)
    ax.add_patch(vf)

    # Signboard Box
    sign = patches.Rectangle((18, 70), 64, 32, facecolor='#15803D', edgecolor='#FFFFFF', lw=2)
    ax.add_patch(sign)
    ax.text(50, 88, "EMERGENCY EXIT", color='#FFFFFF', fontsize=8.0, fontweight='bold', ha='center')
    ax.text(50, 77, "WAY OUT / ROUTE", color='#FFFFFF', fontsize=7.5, fontweight='bold', ha='center')

    # Audio Card
    card = patches.FancyBboxPatch((8, 14), 84, 20, boxstyle="round,pad=0.8,rounding_size=2",
                                  facecolor='#27272A', edgecolor='#4ADE80', lw=1.2)
    ax.add_patch(card)
    ax.text(50, 26, "SIGNBOARD DETECTED", color='#4ADE80', fontsize=6.5, fontweight='bold', ha='center')
    ax.text(50, 18, "\"Signboard: Emergency Exit Ahead\"", color='#FFFFFF', fontsize=7.2, fontweight='bold', ha='center')

    plt.tight_layout()
    plt.savefig('report/generated_assets/screenshots/screenshot_4_signboard_ocr.png', dpi=250, bbox_inches='tight')
    plt.close()

# 5. Object Finder Screen
def make_finder_screen():
    fig, ax = create_phone_frame("Object Finder", "Hot-Cold Audio Guidance")

    vf = patches.Rectangle((8, 38), 84, 100, facecolor='#18181B', edgecolor='#52525B', lw=1)
    ax.add_patch(vf)

    # Target Box
    target = patches.Rectangle((42, 68), 22, 42, facecolor='none', edgecolor='#F97316', lw=2.5)
    ax.add_patch(target)
    ax.text(53, 114, "WATER BOTTLE", color='#F97316', fontsize=6.8, fontweight='bold', ha='center')

    # Distance Bar
    pbar = patches.Rectangle((16, 44), 68, 6, facecolor='#27272A', edgecolor='#71717A', lw=0.8)
    ax.add_patch(pbar)
    pfill = patches.Rectangle((16, 44), 54, 6, facecolor='#F97316')
    ax.add_patch(pfill)
    ax.text(50, 53, "DISTANCE: 0.75m (HOT - CLOSE)", color='#F97316', fontsize=6.0, fontweight='bold', ha='center')

    # Audio Card
    card = patches.FancyBboxPatch((8, 14), 84, 20, boxstyle="round,pad=0.8,rounding_size=2",
                                  facecolor='#27272A', edgecolor='#F97316', lw=1.2)
    ax.add_patch(card)
    ax.text(50, 26, "TARGET REACHED", color='#F97316', fontsize=6.5, fontweight='bold', ha='center')
    ax.text(50, 18, "\"Bottle straight ahead in reach!\"", color='#FFFFFF', fontsize=7.2, fontweight='bold', ha='center')

    plt.tight_layout()
    plt.savefig('report/generated_assets/screenshots/screenshot_5_object_finder.png', dpi=250, bbox_inches='tight')
    plt.close()

# 6. Emergency SOS Screen
def make_sos_screen():
    fig, ax = create_phone_frame("Emergency SOS", "Rapid Distress & Location Alert")

    # SOS Alert Badge
    sos_circle = patches.Circle((50, 108), 24, facecolor='#EF4444', edgecolor='#B91C1C', lw=2)
    ax.add_patch(sos_circle)
    ax.text(50, 112, "SOS", color='#FFFFFF', fontsize=18, fontweight='bold', ha='center')
    ax.text(50, 98, "ACTIVATED", color='#FEE2E2', fontsize=7.0, fontweight='bold', ha='center')

    # Distress Info
    info_card = patches.FancyBboxPatch((10, 48), 80, 32, boxstyle="round,pad=0.8,rounding_size=2",
                                       facecolor='#18181B', edgecolor='#EF4444', lw=1)
    ax.add_patch(info_card)
    ax.text(50, 72, "GPS LOCATION DISPATCHED", color='#EF4444', fontsize=6.8, fontweight='bold', ha='center')
    ax.text(50, 64, "Lat: 12.8231° N, Lng: 80.2209° E", color='#E4E4E7', fontsize=6.0, ha='center')
    ax.text(50, 56, "Battery: 86% | Contact: Guardian SMS", color='#A1A1AA', fontsize=6.0, ha='center')

    # Audio Card
    card = patches.FancyBboxPatch((8, 14), 84, 24, boxstyle="round,pad=0.8,rounding_size=2",
                                  facecolor='#27272A', edgecolor='#FFFFFF', lw=1.2)
    ax.add_patch(card)
    ax.text(50, 30, "VOICE CONFIRMATION", color='#22C55E', fontsize=6.5, fontweight='bold', ha='center')
    ax.text(50, 20, "\"Emergency assistance triggered.\nDistress SMS & Live Location Dispatched\"",
            color='#FFFFFF', fontsize=6.5, fontweight='bold', ha='center', linespacing=1.2)

    plt.tight_layout()
    plt.savefig('report/generated_assets/screenshots/screenshot_6_emergency_sos.png', dpi=250, bbox_inches='tight')
    plt.close()

# 7. Settings Screen
def make_settings_screen():
    fig, ax = create_phone_frame("Settings & Accessibility", "NavEye Preferences")

    settings = [
        ("High Contrast Theme", "WCAG AAA Compliant (Enabled)"),
        ("TTS Speech Rate", "1.5x Multiplier (Adjustable)"),
        ("Obstacle Preemption", "Critical Threshold: 0.8 meters"),
        ("Heartbeat Interval", "10 seconds (Never Silence Policy)"),
        ("Offline Voice Control", "Tamil & English Offline Tokens"),
        ("Enrolled Contacts", "Loki, Primary Guardian, Doctor"),
    ]

    y = 120
    for title, desc in settings:
        row = patches.FancyBboxPatch((10, y), 80, 14, boxstyle="round,pad=0.5,rounding_size=1.5",
                                     facecolor='#18181B', edgecolor='#3F3F46', lw=0.8)
        ax.add_patch(row)
        ax.text(14, y + 9, title, color='#FFFFFF', fontsize=6.8, fontweight='bold')
        ax.text(14, y + 3.5, desc, color='#A1A1AA', fontsize=5.8)
        y -= 17

    plt.tight_layout()
    plt.savefig('report/generated_assets/screenshots/screenshot_7_settings_screen.png', dpi=250, bbox_inches='tight')
    plt.close()

make_nav_screen()
make_face_screen()
make_currency_screen()
make_signboard_screen()
make_finder_screen()
make_sos_screen()
make_settings_screen()
print("All 7 UI mockups created successfully!")
