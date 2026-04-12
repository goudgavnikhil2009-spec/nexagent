import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryService {
  static const String _key = 'vesta_memory_profile';

  Future<Map<String, String>> loadMemory() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_key);
    if (jsonStr == null) return {};
    return Map<String, String>.from(jsonDecode(jsonStr));
  }

  Future<void> saveFact(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    final memory = await loadMemory();
    memory[key] = value;
    await prefs.setString(_key, jsonEncode(memory));
  }
  
  Future<String> buildMemoryContext() async {
    final memory = await loadMemory();
    if (memory.isEmpty) return "No prior memory established.";
    
    final buffer = StringBuffer();
    memory.forEach((key, value) {
      buffer.writeln("- $key: $value");
    });
    return buffer.toString();
  }
}
