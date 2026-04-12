import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vesta/domain/agent_provider.dart';
import 'package:vesta/data/gemma_engine.dart';
import 'package:vesta/presentation/vesta_home.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool _termsAccepted = false;
  bool _isDownloadingModel = false;
  double _downloadProgress = 0.0;
  String _downloadSpeed = '';
  String _downloadSizeInfo = '';
  String _statusText = 'Welcome to Vesta.';

  static final bool isLinux = !kIsWeb && Platform.isLinux;

  Future<void> _completeSetup() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name.')),
      );
      return;
    }
    if (!_termsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please accept the terms to continue.')),
      );
      return;
    }

    setState(() {
      _statusText = 'Preparing environment...';
    });

    // Request permissions (Skip on Linux as permission_handler doesn't support it)
    if (!isLinux) {
      setState(() {
        _statusText = 'Requesting permissions...';
      });
      try {
        await [
          Permission.microphone,
        ].request();
      } catch (e) {
        debugPrint('Permission request error: $e');
      }
    }

    setState(() {
      _statusText = 'Connecting to Vesta Cloud...';
      _isDownloadingModel = true;
    });

    // Initialize Gemma Model
    final engine = ref.read(gemmaEngineProvider);
    await engine.initialize();
    
    // Attempt download if not ready
    if (engine.status != ModelStatus.ready) {
      final success = await engine.downloadModel(onProgress: (p, speed, size) {
        setState(() {
          _downloadProgress = p;
          _downloadSpeed = speed;
          _downloadSizeInfo = size;
          _statusText = 'Downloading Gemma 4 Model...';
        });
      });
      if (!success) {
        setState(() {
          _statusText = 'Failed to download model. You can retry later.';
          _isDownloadingModel = false;
        });
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    // Save preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    await prefs.setString('user_name', _nameController.text.trim());

    if (!mounted) return;
    
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (ctx) => const VestaHome()),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111116), // Claude-like refined dark
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Hero(
                  tag: 'vesta_logo',
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 120,
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Welcome to Vesta',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFEBEBEB),
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  fontFamily: 'sans-serif',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your fully autonomous local agent',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF8A8A93),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 48),
              if (!_isDownloadingModel) ...[
                TextField(
                  controller: _nameController,
                  style: const TextStyle(color: Color(0xFFEBEBEB)),
                  decoration: InputDecoration(
                    labelText: 'What should I call you?',
                    labelStyle: const TextStyle(color: Color(0xFF8A8A93)),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFF2E2E33)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFFD4D4D8)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Checkbox(
                      value: _termsAccepted,
                      onChanged: (val) {
                        setState(() {
                          _termsAccepted = val ?? false;
                        });
                      },
                      activeColor: const Color(0xFFEBEBEB),
                      checkColor: const Color(0xFF111116),
                      side: const BorderSide(color: Color(0xFF8A8A93)),
                    ),
                    const Expanded(
                      child: Text(
                        'I accept the Terms and Policies of Vesta AI, understanding that it operates fully autonomously on-device.',
                        style: TextStyle(color: Color(0xFF8A8A93), fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _completeSetup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEBEBEB),
                    foregroundColor: const Color(0xFF111116),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Initialize Agent',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ] else ...[
                Text(
                  _statusText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFEBEBEB), fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 24),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _downloadProgress,
                    backgroundColor: const Color(0xFF2E2E33),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFEBEBEB)),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _downloadSpeed,
                      style: const TextStyle(color: Color(0xFF8A8A93), fontSize: 13),
                    ),
                    Text(
                      '${(_downloadProgress * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: Color(0xFFEBEBEB),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _downloadSizeInfo,
                      style: const TextStyle(color: Color(0xFF8A8A93), fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                const Text(
                  'Vesta is downloading its open-source brain for fully offline telemetry.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF8A8A93), fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
