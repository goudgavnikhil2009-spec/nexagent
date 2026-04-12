import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:vesta/core/action_guard.dart';
import 'package:vesta/data/voice_service.dart';
import 'package:vesta/domain/agent_provider.dart';
import 'package:vesta/data/gemma_engine.dart';

class VestaHome extends ConsumerStatefulWidget {
  const VestaHome({super.key});

  @override
  ConsumerState<VestaHome> createState() => _VestaHomeState();
}

class _VestaHomeState extends ConsumerState<VestaHome>
    with TickerProviderStateMixin {
  final VoiceService _voice = VoiceService();
  late AnimationController _pulseController;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _partialText = '';

  static final bool isLinux = !kIsWeb && Platform.isLinux;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _initializeAgent();
  }

  Future<void> _initializeAgent() async {
    await _voice.initialize();
    ref.read(agentProvider.notifier).initialize();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _textController.dispose();
    _focusNode.dispose();
    _voice.dispose();
    super.dispose();
  }

  void _handleTerminalSubmit(String value) async {
    if (value.trim().isEmpty) return;
    
    final agent = ref.read(agentProvider.notifier);
    _textController.clear();
    _focusNode.unfocus();
    
    // Simulate voice flow
    agent.startListening();
    setState(() => _partialText = value);
    
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() => _partialText = '');
    await agent.onVoiceCommand(value);
    _dispatchAction();
  }

  void _toggleListening() {
    final agent = ref.read(agentProvider.notifier);
    if (_voice.isListening) {
      _voice.stopListening();
      agent.resetToIdle();
      setState(() => _partialText = '');
    } else {
      agent.startListening();
      
      _voice.startListening(
        onCommand: (cmd) async {
          setState(() => _partialText = '');
          await agent.onVoiceCommand(cmd);
          _dispatchAction();
        },
        onListeningStarted: () {},
        onPartial: (text) {
          setState(() => _partialText = text);
        },
      );
    }
  }

  Future<void> _dispatchAction() async {
    final state = ref.read(agentProvider);
    final action = state.lastAction;
    if (action == null) return;

    // ── ActionGuard is THE FIRST GATE ──
    final allowed = await ActionGuard.evaluate(
      context: context,
      action: action,
    );

    if (!allowed) {
      ref.read(agentProvider.notifier).setBlocked('User denied action');
      return;
    }

    await ref.read(agentProvider.notifier).executeAction(action);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentProvider);
    final phase = state.phase;

    return Scaffold(
      backgroundColor: const Color(0xFF111116), // Claude-like true dark
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Bar ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Image.asset(
                    'assets/images/logo.png',
                    width: 24,
                    height: 24,
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vesta',
                        style: TextStyle(
                          color: Color(0xFFEBEBEB),
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'sans-serif',
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  _StatusChip(
                    label: state.modelStatus == ModelStatus.ready
                        ? (phase == AgentPhase.observing ? 'Observing...' : 'AI Ready')
                        : 'AI Offline',
                    active: state.modelStatus == ModelStatus.ready,
                    pulse: phase == AgentPhase.observing,
                  ),
                ],
              ),
            ),
            // ── Background Download Indicator (Invisible if not downloading) ──

            // ── Chat Feed ──
            Expanded(
              child: state.chatHistory.isEmpty && phase != AgentPhase.thinking
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/images/logo.png',
                            width: 80,
                            height: 80,
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'How can I help you today?',
                            style: TextStyle(
                              color: Color(0xFFEBEBEB),
                              fontSize: 22,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      reverse: true, // Show latest at the bottom
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                      itemCount: state.chatHistory.length,
                      itemBuilder: (context, index) {
                        final chronologicalIndex = state.chatHistory.length - 1 - index;
                        final msg = state.chatHistory[chronologicalIndex];
                        final isUser = msg['role'] == 'user';
                        
                        return _buildChatBubble(msg['text'] ?? '', isUser);
                      },
                    ),
            ),

            // ── Input Area ──
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              decoration: const BoxDecoration(
                color: Color(0xFF111116),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF202024),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFF323238)),
                      ),
                      child: TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        onSubmitted: _handleTerminalSubmit,
                        style: const TextStyle(color: Color(0xFFEBEBEB), fontSize: 16),
                        minLines: 1,
                        maxLines: 5,
                        decoration: InputDecoration(
                          hintText: 'Message Vesta...',
                          hintStyle: const TextStyle(color: Color(0xFF8A8A93)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          border: InputBorder.none,
                          suffixIcon: GestureDetector(
                            onTap: _toggleListening,
                            child: Icon(
                              _voice.isListening ? Icons.mic : Icons.mic_none,
                              color: _voice.isListening ? const Color(0xFFEBEBEB) : const Color(0xFF8A8A93),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (phase == AgentPhase.thinking || phase == AgentPhase.acting)
                    GestureDetector(
                      onTap: () => ref.read(agentProvider.notifier).stopCurrentCycle(),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E2E33),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF323238)),
                        ),
                        child: const Icon(
                          Icons.stop_rounded,
                          color: Color(0xFFEBEBEB),
                          size: 24,
                        ),
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: () => _handleTerminalSubmit(_textController.text),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEBEBEB),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_upward_rounded,
                          color: Color(0xFF111116),
                          size: 24,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThinkingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 24, top: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(right: 16),
              child: Image.asset('assets/images/logo.png', width: 28, height: 28),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF28282D), // slightly lighter dark
                borderRadius: BorderRadius.circular(16),
              ),
              child: const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEBEBEB)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatBubble(String text, bool isUser) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: isUser
          ? Align(
              alignment: Alignment.centerRight,
              child: Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E2E33),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Color(0xFFEBEBEB),
                    fontSize: 16,
                  ),
                ),
              ),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(right: 16, top: 4),
                  child: Image.asset('assets/images/logo.png', width: 28, height: 28),
                ),
                Expanded(
                  child: MarkdownBody(
                    data: text,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(color: Color(0xFFEBEBEB), fontSize: 16, height: 1.5, fontFamily: 'sans-serif'),
                      code: const TextStyle(color: Color(0xFF8A8A93), backgroundColor: Color(0xFF1E1E22), fontFamily: 'monospace'),
                      codeblockPadding: const EdgeInsets.all(16),
                      codeblockDecoration: BoxDecoration(
                        color: const Color(0xFF1E1E22),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2E2E33), width: 1),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }



}

class _StatusChip extends StatefulWidget {
  final String label;
  final bool active;
  final bool pulse;

  const _StatusChip({required this.label, required this.active, this.pulse = false});

  @override
  State<_StatusChip> createState() => _StatusChipState();
}

class _StatusChipState extends State<_StatusChip> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _opacity = Tween<double>(begin: 1.0, end: 0.4).animate(_controller);
    if (widget.pulse) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_StatusChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse != oldWidget.pulse) {
      if (widget.pulse) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.reset();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: widget.pulse ? _opacity : const AlwaysStoppedAnimation(1.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: widget.active
              ? const Color(0xFFEBEBEB).withValues(alpha: 0.05)
              : const Color(0xFFEBEBEB).withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: widget.active
                ? const Color(0xFFEBEBEB).withValues(alpha: 0.15)
                : const Color(0xFFEBEBEB).withValues(alpha: 0.05),
          ),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            color: widget.active ? const Color(0xFFEBEBEB) : const Color(0xFF8A8A93),
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
