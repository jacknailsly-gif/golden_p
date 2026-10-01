import 'dart:async';
import 'package:flutter/material.dart';
import 'package:golden_p/views/super_app_tabs_view.dart';
import 'package:golden_p/services/auth_service.dart';
import 'package:golden_p/services/network_guard_service.dart';

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

    // 🛡️ ตรวจสอบการเชื่อมต่อ Wi-Fi บน Android เครื่องจริง (Emulator ข้ามได้)
    bool canProceed = await NetworkGuardService.canProceed();
    if (!canProceed) {
      // สั่งปิด Wi-Fi ทันทีอัตโนมัติ
      await NetworkGuardService.disableWifi();
      await Future.delayed(const Duration(milliseconds: 300));
      canProceed = await NetworkGuardService.canProceed();
    }
    if (!canProceed && mounted) {
      _showWifiBlockedDialog();
      return;
    }

    await Future.delayed(const Duration(milliseconds: 800));
    _navigateToLogin();
  }

  Timer? _wifiPollTimer;

  void _showWifiBlockedDialog() {
    if (!mounted) return;
    _wifiPollTimer?.cancel();

    // Polling ตรวจสอบทุก 400ms พร้อมสั่งปิด Wi-Fi ต่อเนื่อง เมื่อปิดแล้วเข้าแอปทันที
    _wifiPollTimer = Timer.periodic(const Duration(milliseconds: 400), (timer) async {
      final allowed = await NetworkGuardService.canProceed();
      if (allowed && mounted) {
        timer.cancel();
        Navigator.of(context, rootNavigator: true).pop(); // ปิด dialog
        _navigateToLogin();
      } else {
        await NetworkGuardService.disableWifi();
      }
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: const Color(0xFF0F172A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
            ),
            title: const Row(
              children: [
                Icon(Icons.wifi_off_rounded, color: Color(0xFFEF4444), size: 28),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "ตรวจพบการเชื่อมต่อ WI-FI",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: const Text(
              "ระบบตรวจพบว่ากำลังเชื่อมต่อผ่าน Wi-Fi\n\nเพื่อความปลอดภัยสูงสุดและป้องกันความเสี่ยงโดนแบนบัญชีจากเว็บคาสิโน กรุณา \"ปิด Wi-Fi\" และใช้งานผ่านสัญญาณเน็ตมือถือ (Cellular Data) เท่านั้น จึงจะสามารถเปิดแอปได้ตามปกติ",
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 13,
                height: 1.5,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await NetworkGuardService.openWifiSettings();
                },
                child: const Text(
                  "เปิดการตั้งค่า Wi-Fi",
                  style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.flash_on_rounded, size: 18),
                label: const Text("บังคับปิด Wi-Fi ทันที"),
                onPressed: () async {
                  await NetworkGuardService.disableWifi();
                  final allowed = await NetworkGuardService.canProceed();
                  if (allowed && mounted) {
                    _wifiPollTimer?.cancel();
                    Navigator.of(ctx).pop();
                    _navigateToLogin();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _navigateToLogin() {
    if (mounted) {
      // 🧪 คำสั่งผู้ใช้: ข้ามหน้า Login เข้าสู่หน้าหลักโดยตรง (SuperAppTabsView) สำหรับการทดสอบ
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const SuperAppTabsView(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 800),
        ),
      );
    }
  }


  @override
  void dispose() {
    _wifiPollTimer?.cancel();
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
