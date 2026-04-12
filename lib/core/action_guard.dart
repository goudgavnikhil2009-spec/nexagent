/// ActionGuard — Security Firewall Middleware
/// This is the FIRST gate before any AI-driven action is dispatched.
/// It checks for dangerous keywords and sensitive app targets, and
/// requires biometric confirmation before proceeding.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

class ActionGuard {
  // Platform awareness
  static final bool isLinux = !kIsWeb && Platform.isLinux;

  static const List<String> _dangerousKeywords = [
    'delete',
    'remove',
    'uninstall',
    'wipe',
    'factory_reset',
    'clear_history',
    'format',
    'erase',
  ];

  static const List<String> _sensitiveApps = [
    'whatsapp',
    'chrome',
    'firefox',
    'brave',
    'edge',
    'safari',
    'paytm',
    'gpay',
    'phonepe',
    'bank',
    'payment',
    'upi',
  ];

  static final LocalAuthentication _auth = LocalAuthentication();

  /// Evaluates an AI action JSON before execution.
  /// Returns `true` if the action is safe to proceed, `false` if blocked.
  static Future<bool> evaluate({
    required BuildContext context,
    required Map<String, dynamic> action,
  }) async {
    final String actionType = (action['action'] ?? '').toString().toLowerCase();
    final String target = (action['target'] ?? '').toString().toLowerCase();
    final String text = (action['text'] ?? '').toString().toLowerCase();
    final String fullPayload = '$actionType $target $text';

    // ── CHECK 1: Dangerous keywords ──
    for (final keyword in _dangerousKeywords) {
      if (fullPayload.contains(keyword)) {
        return await _requestConfirmation(
          context: context,
          reason: 'Dangerous action detected: "$keyword"',
          actionSummary: 'Action: $actionType\nTarget: $target',
        );
      }
    }

    // ── CHECK 2: Sensitive application targets ──
    for (final app in _sensitiveApps) {
      if (fullPayload.contains(app)) {
        return await _requestConfirmation(
          context: context,
          reason: 'Action targeting sensitive app: "$app"',
          actionSummary: 'Action: $actionType\nTarget: $target',
        );
      }
    }

    // Action is safe
    return true;
  }

  /// Shows a modal bottom sheet and requires biometric/fingerprint auth or manual choice.
  static Future<bool> _requestConfirmation({
    required BuildContext context,
    required String reason,
    required String actionSummary,
  }) async {
    final bool? userChoice = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SecurityBottomSheet(
        reason: reason,
        actionSummary: actionSummary,
      ),
    );

    if (userChoice != true) return false;

    // On Linux, the manual Choice is enough because local_auth doesn't support it.
    if (isLinux) {
      debugPrint('ActionGuard: Linux detected, skipping biometric challenge.');
      return true;
    }

    // Biometric challenge for other supported platforms
    try {
      final bool canAuthenticate = await _auth.canCheckBiometrics;
      if (!canAuthenticate) {
        // Fallback: if no biometrics, the manual "Approve" tap is enough
        return true;
      }
      final bool didAuthenticate = await _auth.authenticate(
        localizedReason: 'Confirm: $reason',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
      return didAuthenticate;
    } catch (e) {
      debugPrint('ActionGuard biometric error: $e');
      return false;
    }
  }
}

class _SecurityBottomSheet extends StatelessWidget {
  final String reason;
  final String actionSummary;

  const _SecurityBottomSheet({
    required this.reason,
    required this.actionSummary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: Color(0xFF1A3A5C), width: 1),
          left: BorderSide(color: Color(0xFF1A3A5C), width: 1),
          right: BorderSide(color: Color(0xFF1A3A5C), width: 1),
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Icon(
            Icons.shield_outlined,
            color: Color(0xFFFF4444),
            size: 48,
          ),
          const SizedBox(height: 16),
          const Text(
            'SECURITY CHECKPOINT',
            style: TextStyle(
              color: Color(0xFFFF4444),
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            reason,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              actionSummary,
              style: const TextStyle(
                color: Color(0xFF4A9EFF),
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF333333)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'DENY',
                    style: TextStyle(
                      color: Colors.white54,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.fingerprint, size: 20),
                  label: const Text(
                    'APPROVE',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A3A5C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
