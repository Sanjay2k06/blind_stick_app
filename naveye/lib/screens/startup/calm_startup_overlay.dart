import 'package:flutter/material.dart';
import '../../services/startup_flow_manager.dart';

/// Calm, high-contrast, pure Black & White opening screen and startup overlay.
///
/// Features:
/// - 100% Responsive layout for all screen sizes and aspect ratios.
/// - Zero RenderFlex overflow guaranteed via LayoutBuilder, Flexible, and FittedBox.
/// - BLACK + WHITE ONLY (No colors, no colorful gradients).
/// - Centered responsive app icon with circular border.
/// - Minimal white typography: "வழிகாட்டுதல்".
/// - Extra-large accessible high-contrast start button: "தொடங்கவும்".
/// - Dynamic responsive status and loading indicator in Tamil.
class CalmStartupOverlay extends StatelessWidget {
  final StartupFlowManager flowManager;

  const CalmStartupOverlay({
    super.key,
    required this.flowManager,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StartupState>(
      valueListenable: flowManager.stateNotifier,
      builder: (context, state, _) {
        // If navigation is active, dismiss the overlay completely
        if (state == StartupState.navigationActive) {
          return const SizedBox.shrink();
        }

        return Container(
          color: Colors.black,
          width: double.infinity,
          height: double.infinity,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double horizontalPadding = (constraints.maxWidth * 0.06).clamp(16.0, 24.0);
                final double iconSize = (constraints.maxHeight * 0.20).clamp(100.0, 150.0);

                return Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: 16.0,
                  ),
                  child: Column(
                    children: [
                      // ── Top Header ─────────────────────────────────────
                      const SizedBox(height: 8),
                      const Text(
                        'வழிகாட்டுதல்',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'NavEye Assistive Vision',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 13,
                          letterSpacing: 1.1,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const Spacer(),

                      // ── Center App Icon & Status ───────────────────────
                      Center(
                        child: Container(
                          width: iconSize,
                          height: iconSize,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                          ),
                          padding: const EdgeInsets.all(4),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/images/app_icon1.jpg',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Image.asset(
                                'assets/images/app_icon.png',
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.remove_red_eye_rounded,
                                  size: 60,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      _buildStatusWidget(state),

                      const Spacer(),

                      // ── Bottom Action Button ───────────────────────────
                      _buildActionButton(context, state),
                      const SizedBox(height: 8),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusWidget(StartupState state) {
    String statusText;
    bool showSpinner = false;

    switch (state) {
      case StartupState.appOpening:
      case StartupState.bgmPlaying:
      case StartupState.waitingForAutoStart:
        statusText = 'தயாராகிறது...';
        break;
      case StartupState.bgmStopping:
      case StartupState.fetchingLocation:
        statusText = 'உங்கள் இருப்பிடத்தைப் பெறுகிறது...';
        showSpinner = true;
        break;
      case StartupState.locationResolved:
      case StartupState.announcingLocation:
        statusText = 'இருப்பிடம் அறிவிக்கப்படுகிறது...';
        showSpinner = true;
        break;
      case StartupState.announcingTime:
        statusText = 'தற்போதைய நேரம் அறிவிக்கப்படுகிறது...';
        showSpinner = true;
        break;
      case StartupState.startingCamera:
      case StartupState.startingDetection:
        statusText = 'வழிகாட்டுதல் தொடங்குகிறது...';
        showSpinner = true;
        break;
      case StartupState.startupError:
        statusText = 'இருப்பிடத்தைப் பெற முடியவில்லை.\nதயவுசெய்து மீண்டும் முயற்சிக்கவும்.';
        break;
      case StartupState.navigationActive:
        statusText = '';
        break;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showSpinner) ...[
          const Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Text(
            statusText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(BuildContext context, StartupState state) {
    final bool isError = state == StartupState.startupError;
    final bool isWaiting = state == StartupState.waitingForAutoStart;

    if (isError) {
      return Semantics(
        button: true,
        label: 'மீண்டும் முயற்சிக்கவும். இருப்பிடத்தைப் பெற மீண்டும் முயற்சிக்க இருமுறை தட்டவும்',
        child: SizedBox(
          width: double.infinity,
          height: 72,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              side: const BorderSide(color: Colors.white, width: 2.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            onPressed: () => flowManager.retry(),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.refresh_rounded, size: 28, color: Colors.white),
                SizedBox(width: 10),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'மீண்டும் முயற்சிக்கவும்',
                      maxLines: 1,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (isWaiting) {
      return ValueListenableBuilder<int>(
        valueListenable: flowManager.remainingSecondsNotifier,
        builder: (context, seconds, _) {
          final displaySec = seconds.clamp(0, 15);
          return Semantics(
            label: 'வழிகாட்டுதல் தயாராகிறது. 15 விநாடிகளில் தானாகத் தொடங்கும்.',
            child: Container(
              width: double.infinity,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white, width: 2.2),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'தயாராகிறது... ($displaySec வி)',
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    // Processing states (fetching location, announcing, starting camera & detection)
    return Semantics(
      label: 'செயலாக்குகிறது. காத்திருக்கவும்.',
      child: Container(
        width: double.infinity,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white54, width: 2.2),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
              ),
            ),
            SizedBox(width: 12),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'செயலாக்குகிறது...',
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
