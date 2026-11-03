import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../services/shared_stt.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Buttons
// ─────────────────────────────────────────────────────────────────────────────

class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  const PrimaryButton({super.key, required this.text, required this.onPressed});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity, height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.yellow,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final IconData? icon;
  const SecondaryButton({super.key, required this.text, required this.onPressed, this.icon});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity, height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.white,
          side: const BorderSide(color: AppColors.white, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
          Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Logo
// ─────────────────────────────────────────────────────────────────────────────

class NavEyeLogo extends StatelessWidget {
  const NavEyeLogo({super.key});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        width: 70, height: 70,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.greyDark),
        ),
        child: const Icon(Icons.remove_red_eye_outlined, color: AppColors.yellow, size: 36),
      ),
      const SizedBox(height: 12),
      const Text('VEYRA',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.white)),
      const Text('Your Assistant',
          style: TextStyle(fontSize: 13, color: AppColors.grey)),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  VoiceTextField — text field + mic button using shared STT singleton
// ─────────────────────────────────────────────────────────────────────────────

class VoiceTextField extends StatefulWidget {
  final String label;
  final String hint;
  final TextEditingController? controller;
  final TextInputType keyboardType;

  const VoiceTextField({
    super.key,
    required this.label,
    required this.hint,
    this.controller,
    this.keyboardType = TextInputType.text,
  });

  @override
  State<VoiceTextField> createState() => _VoiceTextFieldState();
}

class _VoiceTextFieldState extends State<VoiceTextField> {
  bool _listening = false;


  @override
  void initState() {
    super.initState();
    SharedStt.instance.init().catchError((_) => false);


  }

  @override
  void dispose() {
    if (_listening) SharedStt.instance.stop();
    super.dispose();
  }

  String _formatSpokenNumbers(String input) {
    var s = input.trim();
    final wordMap = {
      'zero': '0', 'one': '1', 'two': '2', 'three': '3', 'four': '4',
      'five': '5', 'six': '6', 'seven': '7', 'eight': '8', 'nine': '9',
      'பூஜ்ஜியம்': '0', 'ஒன்று': '1', 'இரண்டு': '2', 'மூன்று': '3', 'நான்கு': '4',
      'ஐந்து': '5', 'ஆறு': '6', 'ஏழு': '7', 'எட்டு': '8', 'ஒன்பது': '9', 'பத்து': '10'
    };
    wordMap.forEach((k, v) {
      s = s.replaceAll(RegExp('\b$k\b', caseSensitive: false), v);
    });
    // Remove space between digits
    s = s.replaceAll(RegExp(r'(?<=\d)\s+(?=\d)'), '');
    return s;
  }

  Future<void> _stopListening() async {
    SharedStt.instance.clearListeners();
    await SharedStt.instance.stop();
    if (mounted) setState(() => _listening = false);
  }

  Future<void> _startListening() async {
    if (_listening) return;

    // 1. Immediately stop any active TTS guidance so audio focus is clear
    await TtsService().stop();
    HapticFeedback.mediumImpact();

    // 2. Request mic permission if not granted
    try {
      final status = await Permission.microphone.status;
      if (!status.isGranted) {
        final req = await Permission.microphone.request();
        if (!req.isGranted) {
          debugPrint('VoiceTextField: Mic permission denied');

          return;
        }
        SharedStt.instance.reset();
      }
    } catch (e) {
      debugPrint('VoiceTextField permission check: $e');
    }

    // 3. Ensure SharedStt is initialized
    bool ok = SharedStt.instance.available;
    if (!ok) {
      ok = await SharedStt.instance.init();

      if (!ok) {
        debugPrint('VoiceTextField: SharedStt init returned false');
        return;
      }
    }

    if (SharedStt.instance.isListening) {
      await SharedStt.instance.stop();
    }
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    setState(() {
      _listening = true;

    });

    SharedStt.instance.setErrorListener((e) {
      debugPrint('STT error in VoiceTextField: ${e.errorMsg}');
      SharedStt.instance.clearListeners();
      if (mounted) setState(() => _listening = false);
    });

    SharedStt.instance.setStatusListener((status) {
      debugPrint('STT status in VoiceTextField: $status');
      if (status == 'notListening' || status == 'done') {
        SharedStt.instance.clearListeners();
        if (mounted) setState(() => _listening = false);
      }
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final lang = (prefs.getString('language') ?? 'Tamil').toLowerCase();
      final localeId = lang.contains('english') ? 'en_US' : 'ta_IN';

      debugPrint('STT listen ← VoiceTextField (label="${widget.label}", localeId=$localeId)');
      await SharedStt.instance.raw.listen(
        onResult: (result) {
          String words = result.recognizedWords.trim();
          if (words.isNotEmpty) {
            if (widget.keyboardType == TextInputType.number || widget.keyboardType == TextInputType.phone) {
              words = _formatSpokenNumbers(words);
            }
            widget.controller?.text = words;
          }
          if (result.finalResult) {
            SharedStt.instance.clearListeners();
            if (mounted) setState(() => _listening = false);
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          cancelOnError: false,
          partialResults: true,
          onDevice: false,
          listenFor: const Duration(seconds: 15),
          pauseFor: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      debugPrint('STT listen exception: $e');
      SharedStt.instance.clearListeners();
      if (mounted) setState(() => _listening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.label,
          style: const TextStyle(
              color: AppColors.greyLight, fontSize: 13, fontWeight: FontWeight.w500)),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: TextField(
            controller: widget.controller,
            keyboardType: widget.keyboardType,
            style: const TextStyle(color: AppColors.white, fontSize: 14),
            decoration: InputDecoration(hintText: widget.hint),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _listening ? _stopListening : _startListening,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: _listening ? AppColors.white : AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.white,
                width: _listening ? 2.5 : 1.5,
              ),
              boxShadow: _listening
                  ? [BoxShadow(
                      color: AppColors.white.withValues(alpha: 0.4),
                      blurRadius: 10, spreadRadius: 1)]
                  : null,
            ),
            child: Icon(
              _listening ? Icons.mic : Icons.mic_none,
              color: _listening ? Colors.black : Colors.white,
              size: 22,
            ),
          ),
        ),
      ]),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  LabelledTextField  (kept for backward compat)
// ─────────────────────────────────────────────────────────────────────────────

class LabelledTextField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController? controller;
  final TextInputType keyboardType;
  const LabelledTextField({
    super.key,
    required this.label,
    required this.hint,
    this.controller,
    this.keyboardType = TextInputType.text,
  });
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(
              color: AppColors.greyLight, fontSize: 13, fontWeight: FontWeight.w500)),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(color: AppColors.white, fontSize: 14),
        decoration: InputDecoration(hintText: hint),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  LevelSelector
// ─────────────────────────────────────────────────────────────────────────────

class LevelSelector extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;
  const LevelSelector({
    super.key,
    required this.title,
    required this.icon,
    required this.options,
    required this.selected,
    required this.onSelected,
  });
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: AppColors.greyLight, size: 18),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(color: AppColors.white, fontSize: 14)),
      ]),
      const SizedBox(height: 10),
      Row(children: options.map((opt) {
        final sel = opt == selected;
        return Expanded(child: GestureDetector(
          onTap: () => onSelected(opt),
          child: Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: sel ? AppColors.yellow : AppColors.inputBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(child: Text(opt, style: TextStyle(
              color: sel ? Colors.black : AppColors.greyLight,
              fontSize: 13,
              fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
            ))),
          ),
        ));
      }).toList()),
    ]);
  }
}
