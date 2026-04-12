/// Vesta Providers — Riverpod state for the Observe-Think-Act loop.

import 'dart:typed_data';
import 'dart:io' show Process;
import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vesta/data/gemma_engine.dart';
import 'package:vesta/data/chat_repository.dart';
import 'package:vesta/data/native_bridge.dart';
import 'package:vesta/data/tts_service.dart';

// ── Agent State ──
enum AgentPhase { idle, listening, observing, thinking, acting, blocked, error }

class AgentState {
  final AgentPhase phase;
  final String statusMessage;
  final String? lastCommand;
  final String? lastThought;
  final Map<String, dynamic>? lastAction;
   final Uint8List? lastScreenshot;
   final String? lastScreenNodes;
   final bool isServiceEnabled;
  final ModelStatus modelStatus;
  final double downloadProgress;
  final String? downloadSpeed;
  final String? downloadSizeInfo;
  final List<Map<String, String>> chatHistory;

  const AgentState({
    this.phase = AgentPhase.idle,
    this.statusMessage = 'Initializing...',
    this.lastCommand,
    this.lastThought,
    this.lastAction,
    this.lastScreenshot,
    this.lastScreenNodes,
    this.isServiceEnabled = false,
    this.modelStatus = ModelStatus.notDownloaded,
    this.downloadProgress = 0.0,
    this.downloadSpeed,
    this.downloadSizeInfo,
    this.chatHistory = const [],
  });

  AgentState copyWith({
    AgentPhase? phase,
    String? statusMessage,
    String? lastCommand,
    String? lastThought,
    Map<String, dynamic>? lastAction,
    Uint8List? lastScreenshot,
    String? lastScreenNodes,
    bool? isServiceEnabled,
    ModelStatus? modelStatus,
    double? downloadProgress,
    String? downloadSpeed,
    String? downloadSizeInfo,
    List<Map<String, String>>? chatHistory,
  }) {
    return AgentState(
      phase: phase ?? this.phase,
      statusMessage: statusMessage ?? this.statusMessage,
      lastCommand: lastCommand ?? this.lastCommand,
      lastThought: lastThought ?? this.lastThought,
       lastAction: lastAction ?? this.lastAction,
      lastScreenshot: lastScreenshot ?? this.lastScreenshot,
      lastScreenNodes: lastScreenNodes ?? this.lastScreenNodes,
      isServiceEnabled: isServiceEnabled ?? this.isServiceEnabled,
      modelStatus: modelStatus ?? this.modelStatus,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadSpeed: downloadSpeed ?? this.downloadSpeed,
      downloadSizeInfo: downloadSizeInfo ?? this.downloadSizeInfo,
      chatHistory: chatHistory ?? this.chatHistory,
    );
  }
}

// ── Agent Notifier (Observe-Think-Act) ──
class AgentNotifier extends StateNotifier<AgentState> {
  final GemmaEngine _engine;
  final TtsService _tts;
  final ChatRepository _chatRepo = ChatRepository();
  final List<dynamic> _streamSubs = []; // Keep track of subscriptions to cancel them

  AgentNotifier(this._engine, this._tts) : super(const AgentState());

  Future<void> initialize() async {
    // Check accessibility service status
    final serviceOk = await NativeBridge.isServiceEnabled();
    
    // Load historical state
    final historyData = await _chatRepo.loadHistory();
    final List<Map<String, String>> loadedHistory = historyData
        .map((e) => {'role': e.role, 'text': e.content})
        .toList();
    
    // Initialize the AI engine
    await _engine.initialize(onStatusChange: (status) {
      state = state.copyWith(modelStatus: status);
    });

    // If model isn't ready, attempt download
    if (_engine.status == ModelStatus.notDownloaded) {
      state = state.copyWith(
        statusMessage: 'Connecting to Vesta Cloud...',
        modelStatus: ModelStatus.downloading,
        chatHistory: loadedHistory,
      );
      await _engine.downloadModel(
        onProgress: (p, speed, sizeInfo) {
          state = state.copyWith(
            downloadProgress: p,
            downloadSpeed: speed,
            downloadSizeInfo: sizeInfo,
          );
        },
      );
    }

    state = state.copyWith(
      phase: AgentPhase.idle,
      isServiceEnabled: serviceOk,
      modelStatus: _engine.status,
      chatHistory: loadedHistory.isNotEmpty ? loadedHistory : state.chatHistory,
      statusMessage: serviceOk
          ? 'Vesta ready. Say the wake word.'
          : 'Enable Accessibility Service to begin.',
    );
  }

  void startListening() {
    state = state.copyWith(
      phase: AgentPhase.listening,
      statusMessage: 'Listening...',
    );
  }

  Future<void> onVoiceCommand(String command) async {
    // If the agent is already busy, ignore or inform the user
    if (state.phase == AgentPhase.observing || 
        state.phase == AgentPhase.thinking || 
        state.phase == AgentPhase.acting) {
      debugPrint('AgentNotifier: Agent is busy. Ignoring command: $command');
      return;
    }

    // Persist and Append User Message
    final userMsg = ChatMessage(role: 'user', content: command, timestamp: DateTime.now());
    await _chatRepo.saveMessage(userMsg);
    
    final updatedHistory = List<Map<String, String>>.from(state.chatHistory);
    updatedHistory.add({'role': 'user', 'text': command});

    // OBSERVE: Capture screen state
    state = state.copyWith(
      phase: AgentPhase.observing,
      lastCommand: command,
      chatHistory: updatedHistory,
      statusMessage: 'Observing screen...',
    );

    Uint8List? screenshot;
    String? screenNodes;
    if (state.isServiceEnabled) {
      screenshot = await NativeBridge.takeScreenshot();
      screenNodes = await NativeBridge.getScreenNodes();
    }

    // THINK: Send to Gemma engine
    state = state.copyWith(
      phase: AgentPhase.thinking,
      lastScreenshot: screenshot,
      lastScreenNodes: screenNodes,
      statusMessage: 'Thinking...',
    );

    // Add empty agent message for streaming
    final middleHistory = List<Map<String, String>>.from(state.chatHistory);
    middleHistory.add({'role': 'agent', 'text': '...'});
    state = state.copyWith(chatHistory: middleHistory);

    Map<String, dynamic> action = {};
    
    final completer = Completer<void>();
    final sub = _engine.streamCommand(
      voiceCommand: command,
      screenshot: screenshot,
      screenNodes: screenNodes,
    ).listen((update) {
      if (update.containsKey('partial_message')) {
        final currentHistory = List<Map<String, String>>.from(state.chatHistory);
        if (currentHistory.isNotEmpty && currentHistory.last['role'] == 'agent') {
          currentHistory.last['text'] = update['partial_message'] as String;
          state = state.copyWith(chatHistory: currentHistory);
        }
      }
      if (update.containsKey('final_action')) {
        action = update['final_action'] as Map<String, dynamic>;
      }
    }, onDone: () => completer.complete(), onError: (e) => completer.completeError(e));

    _streamSubs.add(sub);
    
    try {
      await completer.future;
    } catch (e) {
      debugPrint("Streaming interrupted or failed: $e");
    } finally {
      _streamSubs.remove(sub);
    }

    if (state.phase == AgentPhase.idle) return; // Already stopped by user

    // Handle Memory Updates
    if (action['memory_update'] != null) {
      final upd = action['memory_update'] as Map<String, dynamic>;
      final key = upd['key'] as String?;
      final value = upd['value'] as String?;
      if (key != null && value != null) {
        await _engine.memoryService.saveFact(key, value);
      }
    }

    // Persist Full AI Message
    final aiResponse = action['message'] as String? ?? 'Executed: ${action['action']}';
    final agentMsg = ChatMessage(role: 'agent', content: aiResponse, timestamp: DateTime.now());
    await _chatRepo.saveMessage(agentMsg);

    state = state.copyWith(
      lastAction: action,
      lastThought: action['thought'] as String?,
      statusMessage: action['memory_update'] != null ? 'Memory Updated.' : "Thinking finished.",
    );

    // ACT phase will be triggered by the UI after ActionGuard check
    state = state.copyWith(
      phase: AgentPhase.acting,
      statusMessage: "Action: ${action['action']}",
    );

    // Speak the thought or action intent
    if (action['message'] != null) {
      _tts.speak(action['message']);
    } else {
      _tts.speak(state.statusMessage);
    }
  }

  Future<void> executeAction(Map<String, dynamic> action) async {
    final actionType = action['action'] as String? ?? '';

    switch (actionType) {
      case 'answer_question':
        final msg = action['message'] as String? ?? 'I am thinking about that.';
        state = state.copyWith(statusMessage: msg);
        break;
      case 'greet':
        final msg = action['message'] as String? ?? 'Hello!';
        state = state.copyWith(statusMessage: msg);
        break;
      case 'open_app':
        final target = action['target'] as String? ?? '';
        state = state.copyWith(statusMessage: 'Opening $target...');
        
        // Execute on Linux using xdg-open if applicable
        if (NativeBridge.isLinux) {
          try {
            // Very simple heuristic to map common apps to URLs or basic bins
            String binOrUrl = target.toLowerCase();
            if (binOrUrl.contains('youtube')) binOrUrl = 'https://youtube.com';
            else if (binOrUrl.contains('browser')) binOrUrl = 'xdg-open'; 
            else if (binOrUrl.contains('google')) binOrUrl = 'https://google.com';
            
            if (binOrUrl.startsWith('http')) {
               Process.run('xdg-open', [binOrUrl]);
            } else {
               // Try opening via gtk-launch or directly
               Process.run('gtk-launch', [binOrUrl]);
            }
          } catch (e) {
            debugPrint('Failed to open app on Linux: $e');
          }
        } else {
          await NativeBridge.performClick(0, 0); // Simulated trigger for Android
        }
        break;
      case 'type_text':
        final text = action['text'] as String? ?? '';
        state = state.copyWith(statusMessage: 'Typing: "$text"');
        break;
      case 'scroll':
        final dir = action['direction'] as String? ?? 'down';
        state = state.copyWith(statusMessage: 'Scrolling $dir');
        break;
      case 'home':
        state = state.copyWith(statusMessage: 'Returning Home');
        break;
      case 'click':
        final x = (action['x'] as num?)?.toDouble() ?? 0;
        final y = (action['y'] as num?)?.toDouble() ?? 0;
        await NativeBridge.performClick(x, y);
        state = state.copyWith(
          statusMessage: 'Clicked at ($x, $y)',
        );
        break;
      case 'screenshot':
        final ss = await NativeBridge.takeScreenshot();
        state = state.copyWith(
          lastScreenshot: ss,
          statusMessage: 'Screenshot captured',
        );
        break;
       case 'answer_call':
        final ok = await NativeBridge.answerCall();
        state = state.copyWith(
          statusMessage: ok ? 'Call answered' : 'Failed to answer call',
        );
        break;

      case 'toggle_wifi':
        final enable = action['enable'] == true;
        await NativeBridge.setWifi(enable);
        state = state.copyWith(statusMessage: 'Wi-Fi ${enable ? 'on' : 'off'}');
        break;

      case 'toggle_flashlight':
        final enable = action['enable'] == true;
        await NativeBridge.setFlashlight(enable);
        state = state.copyWith(statusMessage: 'Flashlight ${enable ? 'on' : 'off'}');
        break;

      case 'set_volume':
        final lvl = (action['level'] as num?)?.toInt() ?? 50;
        await NativeBridge.setVolume(lvl);
        state = state.copyWith(statusMessage: 'Volume set to $lvl%');
        break;

      case 'set_brightness':
        final lvl = (action['level'] as num?)?.toInt() ?? 50;
        await NativeBridge.setBrightness(lvl);
        state = state.copyWith(statusMessage: 'Brightness set to $lvl%');
        break;

      case 'get_status':
        final batt = await NativeBridge.getBatteryStatus();
        final storage = await NativeBridge.getStorageStatus();
        final msg = 'Battery: ${batt['level']}% (${batt['isCharging'] ? 'Charging' : 'Discharging'}). Storage: ${storage['freeGB']}GB free.';
        state = state.copyWith(statusMessage: msg);
        _tts.speak(msg);
        break;

      case 'launch_app':
        final pkg = action['target'] as String? ?? '';
        final ok = await NativeBridge.launchApp(pkg);
        state = state.copyWith(statusMessage: ok ? 'Launched $pkg' : 'Failed to launch $pkg');
        break;

      case 'force_stop':
        final pkg = action['target'] as String? ?? '';
        final ok = await NativeBridge.forceStopApp(pkg);
        state = state.copyWith(statusMessage: ok ? 'Settings for $pkg opened' : 'Failed to find $pkg');
        break;

      case 'media_control':
        final cmd = action['command'] as String? ?? 'play';
        if (cmd == 'play' || cmd == 'pause') await NativeBridge.mediaPlay();
        else if (cmd == 'next') await NativeBridge.mediaNext();
        else if (cmd == 'prev') await NativeBridge.mediaPrevious();
        state = state.copyWith(statusMessage: 'Media: $cmd');
        break;

      case 'navigation':
        final nav = action['command'] as String? ?? 'back';
        if (nav == 'back') await NativeBridge.back();
        else if (nav == 'home') await NativeBridge.home();
        else if (nav == 'recents') await NativeBridge.recents();
        state = state.copyWith(statusMessage: 'Navigation: $nav');
        break;

      case 'read_directory':
        final target = action['target'] as String? ?? '/storage/emulated/0/Download';
        final files = await NativeBridge.readDirectory(target);
        state = state.copyWith(
          statusMessage: 'Found ${files.length} items in $target',
        );
        break;
      default:
        state = state.copyWith(
          statusMessage: 'Action "$actionType" acknowledged.',
        );
    }

    // Return to listening
    state = state.copyWith(phase: AgentPhase.idle);
  }

  void setBlocked(String reason) {
    state = state.copyWith(
      phase: AgentPhase.blocked,
      statusMessage: 'BLOCKED: $reason',
    );
  }

  void setError(String msg) {
    state = state.copyWith(
      phase: AgentPhase.error,
      statusMessage: msg,
    );
  }

  void stopCurrentCycle() {
    for (var sub in _streamSubs) {
      sub.cancel();
    }
    _streamSubs.clear();
    
    // Remove the trailing agent message if it was empty or thinking
    final newHistory = List<Map<String, String>>.from(state.chatHistory);
    if (newHistory.isNotEmpty && newHistory.last['role'] == 'agent') {
      newHistory.removeLast();
    }
    
    state = state.copyWith(
      phase: AgentPhase.idle,
      statusMessage: 'Interrupted by user.',
      chatHistory: newHistory,
    );
  }

  void resetToIdle() {
    state = state.copyWith(
      phase: AgentPhase.idle,
      statusMessage: 'Ready.',
    );
  }
}

// ── Providers ──

final gemmaEngineProvider = Provider<GemmaEngine>((ref) => GemmaEngine());

final agentProvider = StateNotifierProvider<AgentNotifier, AgentState>((ref) {
  final engine = ref.watch(gemmaEngineProvider);
  final tts = ref.watch(ttsServiceProvider);
  return AgentNotifier(engine, tts);
});
