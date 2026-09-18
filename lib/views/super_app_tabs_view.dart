import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';
import 'package:golden_p/views/tabs/wallet_tab_view.dart';
import 'package:golden_p/views/tabs/analytics_tab_view.dart';
import 'package:golden_p/views/sequence_analyzer_view.dart';

class SuperAppTabsView extends StatefulWidget {
  const SuperAppTabsView({super.key});

  @override
  State<SuperAppTabsView> createState() => _SuperAppTabsViewState();
}

class _SuperAppTabsViewState extends State<SuperAppTabsView> {
  int _currentTabIndex = 1; // Default to Towers tab

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

    return Scaffold(
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
    );
  }
}
