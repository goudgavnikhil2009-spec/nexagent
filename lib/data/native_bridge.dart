/// Native Bridge — Dart ↔ Kotlin MethodChannel
/// Provides typed Dart functions for screenshots, clicks, and service status.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'package:flutter/services.dart';

class NativeBridge {
  static const MethodChannel _channel = MethodChannel('com.vesta.agent/service');
  
  // Platform awareness
  static final bool isLinux = !kIsWeb && Platform.isLinux;

  /// Check if the AccessibilityService is currently active.
  static Future<bool> isServiceEnabled() async {
    if (isLinux) return true;
    try {
      final bool result = await _channel.invokeMethod('isServiceEnabled');
      return result;
    } on PlatformException {
      return false;
    }
  }

  /// Capture a screenshot.
  static Future<Uint8List?> takeScreenshot() async {
    if (isLinux) return null;
    try {
      return await _channel.invokeMethod<Uint8List>('takeScreenshot');
    } catch (e) {
      debugPrint('NativeBridge.takeScreenshot error: $e');
      return null;
    }
  }

  /// Scan the screen for UI elements (Node Tree Parsing).
  static Future<String> getScreenNodes() async {
    if (isLinux) return "[]";
    try {
      return await _channel.invokeMethod<String>('getScreenNodes') ?? "[]";
    } catch (e) {
      debugPrint('NativeBridge.getScreenNodes error: $e');
      return "[]";
    }
  }

  /// Simulate a click at (x, y).
  static Future<bool> performClick(double x, double y) async {
    if (isLinux) return true;
    try {
      return await _channel.invokeMethod('performClick', {'x': x, 'y': y}) ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Swipe from (x1, y1) to (x2, y2).
  static Future<bool> performSwipe(double x1, double y1, double x2, double y2) async {
    if (isLinux) return true;
    try {
      return await _channel.invokeMethod('performSwipe', {
        'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2
      }) ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Type text into focused field.
  static Future<bool> typeText(String text) async {
    if (isLinux) return true;
    try {
      return await _channel.invokeMethod('typeText', {'text': text}) ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Navigational actions.
  static Future<bool> back() async => isLinux ? true : await _channel.invokeMethod('performBack') ?? false;
  static Future<bool> home() async => isLinux ? true : await _channel.invokeMethod('performHome') ?? false;
  static Future<bool> recents() async => isLinux ? true : await _channel.invokeMethod('performRecents') ?? false;

  /// System Controls.
  static Future<void> setWifi(bool enable) async {
    if (!isLinux) await _channel.invokeMethod('setWifi', {'enable': enable});
  }

  static Future<void> setFlashlight(bool enable) async {
    if (!isLinux) await _channel.invokeMethod('setFlashlight', {'enable': enable});
  }

  static Future<void> setVolume(int level) async {
    if (!isLinux) await _channel.invokeMethod('setVolume', {'level': level});
  }

  static Future<int> getVolume() async {
    if (isLinux) return 50;
    return await _channel.invokeMethod<int>('getVolume') ?? 0;
  }

  static Future<void> setBrightness(int level) async {
    if (!isLinux) await _channel.invokeMethod('setBrightness', {'level': level});
  }

  static Future<Map<String, dynamic>> getBatteryStatus() async {
    if (isLinux) return {'level': 100, 'isCharging': true};
    final Map<dynamic, dynamic>? result = await _channel.invokeMethod('getBatteryStatus');
    return result?.cast<String, dynamic>() ?? {};
  }

  static Future<Map<String, dynamic>> getStorageStatus() async {
    if (isLinux) return {'freeGB': '10.0', 'totalGB': '128.0'};
    final Map<dynamic, dynamic>? result = await _channel.invokeMethod('getStorageStatus');
    return result?.cast<String, dynamic>() ?? {};
  }

  static Future<String> getForegroundApp() async {
    if (isLinux) return "com.vesta.agent";
    try {
      return await _channel.invokeMethod<String>('getForegroundApp') ?? "unknown";
    } catch (e) {
      return "unknown";
    }
  }

  static Future<bool> forceStopApp(String packageName) async {
    if (isLinux) return true;
    try {
      return await _channel.invokeMethod('forceStopApp', {'packageName': packageName}) ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> launchApp(String packageName) async {
    if (isLinux) return true;
    try {
      return await _channel.invokeMethod('launchApp', {'packageName': packageName}) ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Media Controls.
  static Future<void> mediaPlay() async { if (!isLinux) await _channel.invokeMethod('mediaPlay'); }
  static Future<void> mediaNext() async { if (!isLinux) await _channel.invokeMethod('mediaNext'); }
  static Future<void> mediaPrevious() async { if (!isLinux) await _channel.invokeMethod('mediaPrevious'); }

  /// Settings Pages.
  static Future<void> openBluetoothSettings() async { if (!isLinux) await _channel.invokeMethod('openBluetoothSettings'); }
  static Future<void> openWriteSettingsPermission() async { if (!isLinux) await _channel.invokeMethod('openWriteSettingsPermission'); }

  /// Legacy - Read directory.
  static Future<List<String>> readDirectory(String path) async {
    if (isLinux) return ['file1.txt', 'notes.pdf'];
    try {
      final List<dynamic>? result = await _channel.invokeMethod('readDirectory', {'path': path});
      return result?.map((e) => e.toString()).toList() ?? [];
    } catch (e) {
      return [];
    }
  }

  /// Legacy - Answer call.
  static Future<bool> answerCall() async {
    if (isLinux) return true;
    try {
      return await _channel.invokeMethod('answerCall') ?? false;
    } catch (e) {
      return false;
    }
  }
}
