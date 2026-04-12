import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vesta/presentation/onboarding_screen.dart';
import 'package:vesta/presentation/vesta_home.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF050510),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  final prefs = await SharedPreferences.getInstance();
  final onboardingComplete = prefs.getBool('onboarding_complete') ?? false;

  runApp(ProviderScope(
      child: VestaApp(onboardingComplete: onboardingComplete)));
}

class VestaApp extends StatelessWidget {
  final bool onboardingComplete;
  
  const VestaApp({super.key, required this.onboardingComplete});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vesta',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF050510),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4A9EFF),
          secondary: Color(0xFF1A3A5C),
          surface: Color(0xFF0A0A1A),
          error: Color(0xFFFF4444),
        ),
        fontFamily: 'Roboto',
      ),
      home: onboardingComplete ? const VestaHome() : const OnboardingScreen(),
    );
  }
}
