import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_p/providers/websocket_provider.dart';
import 'package:golden_p/views/sequence_analyzer_view.dart';
import 'package:golden_p/services/auth_service.dart';
import 'package:golden_p/views/history_view.dart';
import 'package:golden_p/views/signals_view.dart';
import 'package:golden_p/views/support_view.dart';
import 'package:golden_p/views/settings/profile_info_view.dart';

class DashboardView extends ConsumerStatefulWidget {
  const DashboardView({super.key});

  @override
  ConsumerState<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends ConsumerState<DashboardView> {
  void _launchAnalyzer() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const SequenceAnalyzerView(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(websocketServiceProvider); // Keep socket active
    final userName = AuthService.currentUserEmail?.split('@').first ?? 'Professional';
    final role = AuthService.currentUserRole == 'admin' ? 'Editorial Director' : 'Premium Member';

    return Scaffold(
      backgroundColor: const Color(0xFF0F1423), // FaucetPay Navy
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(userName, role),
                const SizedBox(height: 24),
                _buildSystemStatusCard(),
                const SizedBox(height: 24),
                _buildLaunchCard(),
                const SizedBox(height: 24),
                const Text(
                  'Quick Access',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildQuickActionGrid(),
                const SizedBox(height: 100), // Padding for BottomNav
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String userName, String role) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome back,',
                style: TextStyle(color: const Color(0xFF94A3B8), fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                userName,
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.person_rounded, color: Color(0xFF3B82F6)),
        )
      ],
    );
  }

  Widget _buildSystemStatusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B2032), Color(0xFF141A28)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('AI Engine Status', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.circle, color: Color(0xFF10B981), size: 8),
                    SizedBox(width: 6),
                    Text('ONLINE', style: TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('Win Rate', '84.5%', const Color(0xFF10B981)),
              Container(width: 1, height: 40, color: Colors.white.withValues(alpha: 0.1)),
              _buildStatItem('Analyzed', '1,402', const Color(0xFF3B82F6)),
              Container(width: 1, height: 40, color: Colors.white.withValues(alpha: 0.1)),
              _buildStatItem('Volatility', 'Low', const Color(0xFFF59E0B)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
      ],
    );
  }

  Widget _buildLaunchCard() {
    return GestureDetector(
      onTap: _launchAnalyzer,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
              blurRadius: 20,
              spreadRadius: 2,
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0xFF3B82F6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 28),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF3B82F6), size: 20),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Sequence Analyzer',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Launch the V37.3 Engine to start monitoring market patterns and executing smart logic sequences.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionGrid() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: _buildActionItem(Icons.analytics_rounded, 'History', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryView())))),
        const SizedBox(width: 8),
        Expanded(child: _buildActionItem(Icons.auto_graph_rounded, 'Signals', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignalsView())))),
        const SizedBox(width: 8),
        Expanded(child: _buildActionItem(Icons.settings_suggest_rounded, 'Config', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileInfoView())))),
        const SizedBox(width: 8),
        Expanded(child: _buildActionItem(Icons.help_center_rounded, 'Support', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportView())))),
      ],
    );
  }

  Widget _buildActionItem(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF3B82F6), size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
