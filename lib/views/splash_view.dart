import 'dart:async';
import 'package:flutter/material.dart';
import 'package:golden_p/views/login_view.dart';
import 'package:golden_p/views/super_app_tabs_view.dart';
import 'package:golden_p/services/auth_service.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> with TickerProviderStateMixin {
  late AnimationController _glowController;
  late AnimationController _spinController;
  String _statusText = "INITIALIZING SECURE CONNECTION...";

  @override
  void initState() {
    super.initState();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _startBootSequence();
  }

  Future<void> _startBootSequence() async {
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) {
      setState(() {
        _statusText = "VERIFYING ENGINE INTEGRITY...";
      });
    }
    
    await Future.delayed(const Duration(milliseconds: 1500));
    
    // Check session in the background
    await AuthService.checkSession();
    
    // Simulate Security Check (Pass)
    if (mounted) {
      setState(() {
        _statusText = "SECURITY PROTOCOLS VERIFIED";
      });
    }

    await Future.delayed(const Duration(milliseconds: 800));
    _navigateToLogin();
  }

  void _navigateToLogin() {
    if (mounted) {
      if (AuthService.currentUserEmail != null) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const SuperAppTabsView(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 800),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const LoginView(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 800),
          ),
        );
      }
    }
  }

  // Example Force Update Modal (For UX demonstration if needed)
  void _showForceUpdateModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.redAccent, width: 2),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
              SizedBox(width: 8),
              Text(
                "CRITICAL UPDATE",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Text(
            "Your engine version is out of date.\nPlease update to ensure maximum security.",
            style: TextStyle(color: Colors.grey),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: () {
                // Mock update action
              },
              child: const Text("UPDATE NOW", style: TextStyle(color: Colors.white)),
            )
          ],
        );
      }
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Midnight Azure Dark Background
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Professional Logo Area
            AnimatedBuilder(
              animation: _glowController,
              builder: (context, child) {
                return Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1E293B),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.1 + (_glowController.value * 0.15)),
                        blurRadius: 30 + (_glowController.value * 15),
                        spreadRadius: 5 + (_glowController.value * 5),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Inner Ring
                      RotationTransition(
                        turns: _spinController,
                        child: SizedBox(
                          width: 120,
                          height: 120,
                          child: CircularProgressIndicator(
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)), // Azure Blue
                            strokeWidth: 2,
                            backgroundColor: Colors.transparent,
                          ),
                        ),
                      ),
                      // Outer Ring
                      RotationTransition(
                        turns: Tween(begin: 1.0, end: 0.0).animate(_spinController),
                        child: SizedBox(
                          width: 100,
                          height: 100,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF3B82F6).withValues(alpha: 0.5)),
                            strokeWidth: 3,
                            backgroundColor: Colors.transparent,
                          ),
                        ),
                      ),
                      // Center Icon
                      const Icon(
                        Icons.verified_user_rounded,
                        size: 50,
                        color: Color(0xFF3B82F6),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 40),
            
            // Brand Name
            const Text(
              'Midnight Azure',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Color(0xFF3B82F6),
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'PROFESSIONAL INSIGHTS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF94A3B8),
                letterSpacing: 4,
              ),
            ),
            
            const SizedBox(height: 60),
            
            // Dynamic Status Text
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: Text(
                _statusText,
                key: ValueKey<String>(_statusText),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF94A3B8),
                  letterSpacing: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
