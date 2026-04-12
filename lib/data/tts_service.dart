import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    
    // Configure settings for Linux/Android
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _isInitialized = true;
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    if (!_isInitialized) await init();
    
    // On Linux, we need to ensure speech-dispatcher is working
    // but the plugin handles this internally.
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}

final ttsServiceProvider = Provider<TtsService>((ref) {
  return TtsService();
});
