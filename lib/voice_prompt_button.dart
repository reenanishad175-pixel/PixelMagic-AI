// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoicePromptButton extends StatefulWidget {
  final ValueChanged<String> onRecognized;
  final bool enabled;
  const VoicePromptButton({super.key, required this.onRecognized, this.enabled = true});

  @override
  State<VoicePromptButton> createState() => _VoicePromptButtonState();
}

class _VoicePromptButtonState extends State<VoicePromptButton> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _available = false;
  bool _listening = false;
  bool _initializing = false;
  bool _finalHandled = false;

  Future<void> _toggle() async {
    if (!widget.enabled || _initializing) return;
    if (_speech.isListening) {
      await _speech.stop();
      if (mounted) {
        setState(() => _listening = false);
      }
      return;
    }
    final localeId = Localizations.localeOf(context).languageCode == 'hi' ? 'hi_IN' : 'en_IN';
    setState(() => _initializing = true);
    try {
      _available = await _speech.initialize(
        onStatus: (status) {
          if (mounted) {
            setState(() => _listening = status == 'listening');
          }
        },
        onError: (_) {
          if (mounted) {
            setState(() => _listening = false);
          }
        },
      );
      if (!_available) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Voice input is unavailable. Enable a speech recognition service and microphone permission.')),
          );
        }
        return;
      }
      _finalHandled = false;
      await _speech.listen(
        options: stt.SpeechListenOptions(
          localeId: localeId,
          listenFor: const Duration(minutes: 1),
          pauseFor: const Duration(seconds: 4),
        ),
        onResult: (result) {
          if (!result.finalResult || _finalHandled) {
            return;
          }
          final words = result.recognizedWords.trim();
          if (words.isEmpty) {
            return;
          }
          _finalHandled = true;
          widget.onRecognized(words);
          _speech.stop();
          if (mounted) {
            setState(() => _listening = false);
          }
        },
      );
      if (mounted) {
        setState(() => _listening = _speech.isListening);
      }
    } finally {
      if (mounted) {
        setState(() => _initializing = false);
      }
    }
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: _listening ? 'Stop voice input' : 'Speak',
    onPressed: widget.enabled ? _toggle : null,
    icon: Icon(
      _listening ? Icons.mic : Icons.mic_none_rounded,
      color: _listening ? Colors.redAccent : const Color(0xFF55DCCB),
    ),
  );
}
