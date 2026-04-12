/// Gemma Engine — Local AI Model Interface
/// In production this would load gemma4_e2b.bin via mediapipe_genai.
/// For beta, this provides a stub interface that simulates the
/// Observe → Think → Act pipeline with a structured JSON response.

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:vesta/services/model_downloader.dart';
import 'package:vesta/data/chat_repository.dart';
import 'package:vesta/data/memory_service.dart';

import 'package:llama_cpp_dart/llama_cpp_dart.dart';

enum ModelStatus { notDownloaded, downloading, ready, error }

class GemmaEngine {
  ModelStatus _status = ModelStatus.notDownloaded;
  ModelStatus get status => _status;

  String? _modelPath;
  LlamaParent? _llama;
  
  final ChatRepository _chatRepo = ChatRepository();
  final MemoryService memoryService = MemoryService();
  
  static const String _modelFileName = 'google_gemma-4-E2B-it-Q4_K_M.gguf';
  // ── Cloudflare R2 Model URL ──
  // User: Replace this with your public R2 bucket URL
  static const String _modelDownloadUrl = 'https://pub-2b34fc7d3e144a22b9085ebd8632b330.r2.dev/google_gemma-4-E2B-it-Q4_K_M.gguf';

  final ModelDownloader _downloader = ModelDownloader();

  /// Initialize the engine: check if model exists.
  Future<void> initialize({Function(ModelStatus)? onStatusChange}) async {
    final dir = await getApplicationDocumentsDirectory();
    final modelFile = File('${dir.path}/$_modelFileName');

    if (await modelFile.exists()) {
      _modelPath = modelFile.path;
      _status = ModelStatus.ready;
      onStatusChange?.call(_status);
      debugPrint('GemmaEngine: Model found at $_modelPath');
      
      // Initialize Native Inference Engine
      if (_llama == null) {
        debugPrint('GemmaEngine: Initializing Native Llama Engine...');
        
        final modelParams = ModelParams()
          ..nGpuLayers = 0; // CRITICAL FIX: Prevent Android GPU native crash

        final contextParams = ContextParams()
          ..nCtx = 2048 // CRITICAL FIX: Give enough context length so prompt doesn't exceed bounds
          ..nThreads = 4; // Safely cap threads to prevent BIG.little throttle panics
          
        _llama = LlamaParent(LlamaLoad(
          path: _modelPath!,
          modelParams: modelParams,
          contextParams: contextParams,
          samplingParams: SamplerParams(),
        ));
        await _llama!.init();
        debugPrint('GemmaEngine: Native Engine Ready.');
      }
    } else {
      _status = ModelStatus.notDownloaded;
      onStatusChange?.call(_status);
      debugPrint('GemmaEngine: Model not found. Ready for download.');
    }
  }

  /// Download the model file using Dio with resume support.
  Future<bool> downloadModel({
    required Function(double p, String speed, String sizeInfo) onProgress,
  }) async {
    try {
      _status = ModelStatus.downloading;

      await _downloader.downloadModel(
        url: _modelDownloadUrl,
        fileName: _modelFileName,
        onProgress: onProgress,
        onComplete: () {
          _status = ModelStatus.ready;
          debugPrint('GemmaEngine: Download complete.');
        },
        onError: (err) {
          _status = ModelStatus.error;
          debugPrint('GemmaEngine download error: $err');
        },
      );

      return _status == ModelStatus.ready;
    } catch (e) {
      debugPrint('GemmaEngine download error: $e');
      _status = ModelStatus.error;
      return false;
    }
  }

  String _normalize(String input) {
    // Lowercase, remove punctuation, and consolidate multiple spaces
    String normalized = input.toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    
    // Deduplicate repeated words (e.g., "hi hi" -> "hi")
    final words = normalized.split(' ');
    final uniqueWords = <String>[];
    for (var word in words) {
      if (uniqueWords.isEmpty || uniqueWords.last != word) {
        uniqueWords.add(word);
      }
    }
    return uniqueWords.join(' ');
  }

  bool _isGenerating = false;

  /// Process a command and yield partial updates for the chat message.
  Stream<Map<String, dynamic>> streamCommand({
    required String voiceCommand,
    Uint8List? screenshot,
    String? screenNodes,
  }) async* {
    if (_isGenerating) {
      yield {
        'thought': 'Engine busy.',
        'action': 'answer_question',
        'message': 'Thinking...',
      };
      return;
    }

    if (_llama == null) {
      if (_status == ModelStatus.ready) {
        await initialize();
      } else {
        yield {
          'action': 'error',
          'message': 'Model not ready.',
        };
        return;
      }
    }

    _isGenerating = true;
    String rawOutput = '';
    bool messageFound = false;
    int messageStartIdx = -1;

    try {
      final now = DateTime.now();
      final memoryContext = await memoryService.buildMemoryContext();
      final history = await _chatRepo.loadHistory();
      final recentHistory = history.length > 5 ? history.sublist(history.length - 5) : history;
      final historyBuffer = StringBuffer();
      for (var msg in recentHistory) {
        historyBuffer.writeln("${msg.role == 'user' ? 'User' : 'Vesta'}: ${msg.content}");
      }

      final contextHeader = '''
System: You are Vesta, an advanced, highly capable autonomous AI desktop agent. 
You run locally and have access to the user's desktop.
Current Date: ${now.toIso8601String().split('T').first}
Current Time: ${now.hour}:${now.minute.toString().padLeft(2, '0')}

--- USER MEMORY PROFILE ---
$memoryContext

--- RECENT CONVERSATION ---
$historyBuffer

--- SCREEN VISION (UI NODES) ---
${_compactNodes(screenNodes ?? '[]')}

--- PACKAGE DICTIONARY ---
- WhatsApp: com.whatsapp
- YouTube: com.google.android.youtube
- Spotify: com.spotify.music
- Settings: com.android.settings

INSTRUCTIONS:
You MUST output your response ONLY as a raw JSON object. Use the "message" field for your conversation.
Available actions: "open_app", "click", "type_text", "answer_question", "toggle_wifi", "toggle_flashlight", "set_volume", "set_brightness", "get_status", "launch_app", "force_stop", "media_control", "navigation".

Schema:
{
  "thought": "internal diagnostic",
  "action": "action_name",
  "message": "YOUR MESSAGE HERE",
  ...
}
''';

      final promptId = await _llama!.sendPrompt("$contextHeader\nUser: $voiceCommand\nVesta: ");
      
      await for (final textChunk in _llama!.stream) {
        rawOutput += textChunk;

        if (!messageFound) {
          final mIdx = rawOutput.indexOf('"message": "');
          if (mIdx != -1) {
            messageFound = true;
            messageStartIdx = mIdx + 12;
          }
        }

        if (messageFound) {
          // Extract current message content
          // Look for the end of the message (unescaped quote followed by comma or brace)
          String currentMsg = rawOutput.substring(messageStartIdx);
          
          // Basic heuristic: strip things after matching end quote
          final endQuoteIdx = currentMsg.lastIndexOf('"');
          if (endQuoteIdx != -1 && endQuoteIdx > 0 && currentMsg[endQuoteIdx-1] != '\\') {
             currentMsg = currentMsg.substring(0, endQuoteIdx);
          }
          
          yield {'partial_message': currentMsg};
        }
      }

      // Cleanup and Final Parse
      final jsonStart = rawOutput.indexOf('{');
      final jsonEnd = rawOutput.lastIndexOf('}');
      if (jsonStart != -1 && jsonEnd != -1) {
        final jsonStr = rawOutput.substring(jsonStart, jsonEnd + 1);
        final parsed = jsonDecode(jsonStr);
        yield {
          'final_action': {
            'thought': parsed['thought'] ?? 'Used native AI.',
            'action': parsed['action'] ?? 'answer_question',
            'message': parsed['message'] ?? '',
            'target': parsed['target'],
            'text': parsed['text'],
            'enable': parsed['enable'],
            'level': parsed['level'],
            'command': parsed['command'],
            'memory_update': parsed['memory_update'],
          }
        };
      }
    } catch (e) {
      debugPrint('Stream inference error: $e');
      yield {'action': 'error', 'message': 'Engine error: $e'};
    } finally {
      _isGenerating = false;
    }
  }

  /// Process a voice command + optional screenshot and return a JSON action.
  Future<Map<String, dynamic>> processCommand({
    required String voiceCommand,
    Uint8List? screenshot,
    String? screenNodes,
  }) async {
    // Wrap streamCommand for backward compatibility or one-off calls
    final stream = streamCommand(
      voiceCommand: voiceCommand,
      screenshot: screenshot,
      screenNodes: screenNodes,
    );

    Map<String, dynamic> result = {};
    await for (final update in stream) {
      if (update.containsKey('final_action')) {
        result = update['final_action'];
      }
    }
    
    if (result.isEmpty) {
       return {
         'thought': 'Timeout or parse failure.',
         'action': 'answer_question',
         'message': 'I failed to generate a response in time.'
       };
    }
    return result;
  }

  String _compactNodes(String rawJson) {
    try {
      final List<dynamic> nodes = jsonDecode(rawJson);
      if (nodes.isEmpty) return "None";
      
      final buffer = StringBuffer();
      for (var node in nodes) {
        final label = node['label'] ?? '';
        final x = node['x'] ?? 0;
        final y = node['y'] ?? 0;
        final type = node['type'] ?? 'unknown';
        buffer.write('[$type: "$label" @ ($x, $y)] ');
      }
      return buffer.toString();
    } catch (e) {
      return "Error parsing nodes";
    }
  }
}
