import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';
import 'package:golden_p/views/tabs/wallet_tab_view.dart';
import 'package:golden_p/views/tabs/analytics_tab_view.dart';
import 'package:golden_p/views/sequence_analyzer_view.dart';
import 'package:golden_p/services/network_guard_service.dart';

class SuperAppTabsView extends StatefulWidget {
  const SuperAppTabsView({super.key});

  @override
  State<SuperAppTabsView> createState() => _SuperAppTabsViewState();
}

class _SuperAppTabsViewState extends State<SuperAppTabsView> {
  int _currentTabIndex = 1; // Default to Towers tab

  @override
  void initState() {
    super.initState();
    // 🛡️ เริ่มระบบตรวจจับและสั่งปิด Wi-Fi อัตโนมัติตลอดเวลาที่เปิดแอป
    NetworkGuardService.startContinuousMonitoring();
  }

  @override
  void dispose() {
    NetworkGuardService.stopContinuousMonitoring();
    super.dispose();
  }

  final List<Widget> _tabs = const [
    WalletTabView(),
    SequenceAnalyzerView(gameMode: GameMode.towers),
    SequenceAnalyzerView(gameMode: GameMode.mines),
    AnalyticsTabView(),
  ];

  @override
  Widget build(BuildContext context) {
    final overlayVM = Provider.of<OverlayButtonsViewModel>(
      context,
      listen: false,
    );

    return ValueListenableBuilder<bool>(
      valueListenable: NetworkGuardService.isWifiBlockedNotifier,
      builder: (context, isBlocked, _) {
        return Stack(
          children: [
            Scaffold(
      body: IndexedStack(
        index: _currentTabIndex,
        children: _tabs,
      ),
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withValues(alpha: 0.85),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.05),
                  width: 1,
                ),
              ),
            ),
            child: BottomNavigationBar(
              currentIndex: _currentTabIndex,
              onTap: (index) {
                setState(() {
                  _currentTabIndex = index;
                });
                if (index == 1) {
                  overlayVM.setActiveGameMode(GameMode.towers);
                } else if (index == 2) {
                  overlayVM.setActiveGameMode(GameMode.mines);
                }
              },
              backgroundColor: Colors.transparent,
              elevation: 0,
              type: BottomNavigationBarType.fixed,
              selectedItemColor: const Color(0xFF3B82F6),
              unselectedItemColor: const Color(0xFF94A3B8),
              selectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  activeIcon: Icon(Icons.account_balance_wallet_rounded),
                  label: 'Wallet',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.layers_outlined),
                  activeIcon: Icon(Icons.layers_rounded),
                  label: 'Towers',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.diamond_outlined),
                  activeIcon: Icon(Icons.diamond_rounded),
                  label: 'Mine',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.analytics_outlined),
                  activeIcon: Icon(Icons.analytics_rounded),
                  label: 'Analytics',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    if (isBlocked)
              Positioned.fill(
                child: Container(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.98),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off_rounded, color: Color(0xFFEF4444), size: 72),
                        const SizedBox(height: 16),
                        const Text(
                          "ไม่อนุญาตให้เปิดใช้งาน WI-FI",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          "ในขณะที่เปิดใช้งานแอป golden_p ระบบจะไม่อนุญาตให้เปิด Wi-Fi เพื่อความปลอดภัยของบัญชีและการหลบเลี่ยงการถูกแบน\n\nกรุณาปิด Wi-Fi แล้วใช้งานผ่านเน็ตมือถือ (Cellular Data) เท่านั้น",
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 14,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.flash_on_rounded),
                          label: const Text("บังคับปิด Wi-Fi ทันที (Force Kill)"),
                          onPressed: () async {
                            await NetworkGuardService.disableWifi();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            textStyle: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.settings, color: Color(0xFF38BDF8)),
                          label: const Text("เปิดการตั้งค่า Wi-Fi เพื่อปิด"),
                          onPressed: () => NetworkGuardService.openWifiSettings(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF38BDF8),
                            side: const BorderSide(color: Color(0xFF38BDF8)),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
