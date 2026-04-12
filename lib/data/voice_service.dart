/// Voice Service — Continuous speech-to-text with wake word detection.

import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;
  
  // Platform awareness
  static final bool isLinux = !kIsWeb && Platform.isLinux;

  static const String wakeWord = 'vesta';

  bool get isListening => _isListening;

  Future<bool> initialize() async {
    if (isLinux) {
      debugPrint('VoiceService: Running in simulation mode on Linux');
      _isInitialized = true;
      return true;
    }
    
    try {
      _isInitialized = await _speech.initialize(
        onError: (error) => debugPrint('VoiceService error: $error'),
        onStatus: (status) => debugPrint('VoiceService status: $status'),
      );
    } catch (e) {
      debugPrint('VoiceService init failed: $e');
      _isInitialized = false;
    }
    return _isInitialized;
  }

  Process? _linuxSttProcess;

  /// Start listening. On Linux, this spawns the STT python background process.
  Future<void> startListening({
    required Function(String command) onCommand,
    required Function() onListeningStarted,
    Function(String)? onPartial,
  }) async {
    if (!_isInitialized) {
      debugPrint('VoiceService: Not initialized');
      return;
    }

    _isListening = true;
    onListeningStarted();

    if (isLinux) {
      debugPrint('VoiceService: Starting Linux Python STT');
      try {
        _linuxSttProcess = await Process.start('python3', ['linux_stt.py']);
        
        _linuxSttProcess?.stdout.transform(SystemEncoding().decoder).listen((data) {
          final lines = data.split('\n');
          for (final line in lines) {
            if (line.startsWith('STT_RESULT:')) {
              final text = line.substring(11).trim().toLowerCase();
              debugPrint('Linux STT heard: $text');
              
              if (text.contains(wakeWord)) {
                final commandPart = text
                    .substring(text.indexOf(wakeWord) + wakeWord.length)
                    .trim();
                if (commandPart.isNotEmpty) {
                  onCommand(commandPart);
                }
              } else if (text.isNotEmpty) {
                onCommand(text);
              }
            } else if (line.startsWith('STT_ERROR:')) {
               debugPrint('Linux STT Error: ${line.substring(10)}');
            }
          }
        });

      } catch (e) {
        debugPrint('Failed to start python STT: $e');
      }
      return;
    }

    _speech.listen(
      onResult: (result) {
        final text = result.recognizedWords.toLowerCase().trim();

        if (result.finalResult) {
          // Check for wake word
          if (text.contains(wakeWord)) {
            final commandPart = text
                .substring(text.indexOf(wakeWord) + wakeWord.length)
                .trim();
            if (commandPart.isNotEmpty) {
              onCommand(commandPart);
            }
          } else if (text.isNotEmpty) {
            // If already in active mode, treat everything as a command
            onCommand(text);
          }

          // Restart listening for continuous mode
          if (_isListening) {
            Future.delayed(const Duration(milliseconds: 300), () {
              if (_isListening) {
                startListening(
                  onCommand: onCommand,
                  onListeningStarted: onListeningStarted,
                  onPartial: onPartial,
                );
              }
            });
          }
        } else {
          onPartial?.call(text);
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      listenMode: stt.ListenMode.dictation,
    );
  }

  /// Allow manual command injection (useful for Linux text fallback)
  void simulateCommand(String text, Function(String) onCommand) {
    if (_isListening) {
      onCommand(text);
    }
  }

  void stopListening() {
    _isListening = false;
    if (isLinux) {
      _linuxSttProcess?.kill();
      _linuxSttProcess = null;
    } else {
      _speech.stop();
    }
  }

  void dispose() {
    stopListening();
  }
}
