import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:golden_p/views/tabs/wallet_tab_view.dart';
import 'package:golden_p/views/tabs/ai_bot_tab_view.dart';
import 'package:golden_p/views/tabs/analytics_tab_view.dart';

class SuperAppTabsView extends StatefulWidget {
  const SuperAppTabsView({super.key});

  @override
  State<SuperAppTabsView> createState() => _SuperAppTabsViewState();
}

class _SuperAppTabsViewState extends State<SuperAppTabsView> {
  int _currentTabIndex = 0;

  final List<Widget> _tabs = [
    const WalletTabView(),
    const AIBotTabView(),
    const AnalyticsTabView(),
  ];

  @override
  Widget build(BuildContext context) {
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
                  icon: Icon(Icons.smart_toy_outlined),
                  activeIcon: Icon(Icons.smart_toy_rounded),
                  label: 'AI Bot',
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
