import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/game_mode.dart';
import '../../viewmodels/sequence_analyzer_viewmodel.dart';
import '../../viewmodels/overlay_buttons_viewmodel.dart';
import '../../models/stop_profit_milestone.dart';

class AnalyticsTabView extends StatefulWidget {
  const AnalyticsTabView({super.key});

  @override
  State<AnalyticsTabView> createState() => _AnalyticsTabViewState();
}

class _AnalyticsTabViewState extends State<AnalyticsTabView> {
  final TextEditingController _tpController = TextEditingController();
  GameMode? _lastMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final overlayVM = context.read<OverlayButtonsViewModel>();
      _tpController.text = overlayVM.getStopProfitPercent(overlayVM.activeGameMode).toStringAsFixed(1);
      _lastMode = overlayVM.activeGameMode;
    });
  }

  @override
  void dispose() {
    _tpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<SequenceAnalyzerViewModel, OverlayButtonsViewModel>(
      builder: (context, viewModel, overlayVM, child) {
        final int totalPredictions = viewModel.totalPredictions;
        final int wins = viewModel.correctPredictions;
        final int losses = totalPredictions - wins;
        final double winRate = totalPredictions > 0 ? (wins / totalPredictions * 100) : 0.0;
        final double profitLoss = viewModel.profitLossValue;
        final int maxLossStreak = viewModel.maxLossStreak;
        final String maxLossSequence = viewModel.maxLossSequence;
        final currentMode = overlayVM.activeGameMode;

        if (_lastMode != currentMode) {
          _lastMode = currentMode;
          _tpController.text = overlayVM.getStopProfitPercent(currentMode).toStringAsFixed(1);
        }

        return Scaffold(
          backgroundColor: const Color(0xFF0F1423),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: const Text(
          'Analytics',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatsHeader(winRate),
              const SizedBox(height: 24),
              _buildPerformanceCards(totalPredictions, wins, losses, profitLoss, maxLossStreak, maxLossSequence),
              const SizedBox(height: 24),
              _buildStopProfitSection(overlayVM, currentMode),
              const SizedBox(height: 24),
              _buildRecoveryProfitLevelSection(overlayVM),
              const SizedBox(height: 24),
              _buildProfitMilestonesSection(overlayVM),
            ],
          ),
        ),
      ),
    );
      },
    );
  }

  Widget _buildStatsHeader(double winRate) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF3B82F6),
            const Color(0xFF1E40AF),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Win Rate',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${winRate.toStringAsFixed(1)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.trending_up,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceCards(int totalPredictions, int wins, int losses, double profitLoss, int maxLossStreak, String maxLossSequence) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'Total Predictions',
                value: totalPredictions.toString(),
                icon: Icons.calculate,
                color: const Color(0xFF8B5CF6),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                title: 'Wins',
                value: wins.toString(),
                icon: Icons.emoji_events,
                color: const Color(0xFF10B981),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'Losses',
                value: losses.toString(),
                icon: Icons.trending_down,
                color: const Color(0xFFEF4444),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                title: 'Profit/Loss',
                value: profitLoss >= 0 ? '+\$${profitLoss.toStringAsFixed(2)}' : '-\$${profitLoss.abs().toStringAsFixed(2)}',
                icon: Icons.attach_money,
                color: const Color(0xFFF59E0B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'Max Losing Streak',
                value: '$maxLossStreak',
                icon: Icons.warning_amber_rounded,
                color: const Color(0xFFF97316),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                title: 'Max Loss Sequence',
                value: maxLossSequence.isEmpty ? '-' : maxLossSequence,
                icon: Icons.history,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStopProfitSection(OverlayButtonsViewModel overlayVM, GameMode mode) {
    final bool isEnabled = overlayVM.isStopProfitEnabledFor(mode);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEnabled ? const Color(0xFF10B981) : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.flag_circle, color: Color(0xFF10B981), size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'Stop Profit Target [${mode.displayName}]',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Switch(
                value: isEnabled,
                onChanged: (val) {
                  overlayVM.setStopProfitEnabled(val, mode: mode);
                },
                activeThumbColor: const Color(0xFF10B981),
              ),
            ],
          ),
          if (isEnabled) ...[
            const SizedBox(height: 16),
            Text(
              'Target Profit (%) for ${mode.displayName}',
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tpController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF0F1423),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      suffixText: '%',
                      suffixStyle: const TextStyle(color: Color(0xFF94A3B8)),
                    ),
                    onSubmitted: (value) {
                      double? parsed = double.tryParse(value);
                      if (parsed != null && parsed > 0) {
                        overlayVM.setStopProfitPercent(parsed, mode: mode);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    double? parsed = double.tryParse(_tpController.text);
                    if (parsed != null && parsed > 0) {
                      overlayVM.setStopProfitPercent(parsed, mode: mode);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Saved ${mode.displayName} target: $parsed%')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Save'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Bot will completely halt when net profit hits this target.',
              style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11),
            )
          ],
        ],
      ),
    );
  }

  Widget _buildRecoveryProfitLevelSection(OverlayButtonsViewModel overlayVM) {
    final double currentVal = overlayVM.recoveryProfitPercent;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune_rounded, color: Color(0xFF3B82F6), size: 24),
              SizedBox(width: 8),
              Text(
                'Recovery Profit Level (ระดับกำไรทวงหนี้)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'เลือกระดับ % กำไรที่นำไปคำนวณในสมการทวงหนี้ (M5):',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF0F1423),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<double>(
                value: currentVal,
                dropdownColor: const Color(0xFF1E293B),
                isExpanded: true,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                items: OverlayButtonsViewModel.recoveryProfitLevels.map((item) {
                  return DropdownMenuItem<double>(
                    value: item['value'] as double,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          item['label'] as String,
                          style: TextStyle(
                            color: item['value'] == currentVal ? const Color(0xFF3B82F6) : Colors.white,
                            fontWeight: item['value'] == currentVal ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        Text(
                          '${((item['value'] as double) * 100).toInt()}%',
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (double? newValue) {
                  if (newValue != null) {
                    overlayVM.setRecoveryProfitPercent(newValue);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F1423),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.calculate_outlined, color: Color(0xFF10B981), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'สูตรทวงหนี้: M5 Bet = (หนี้สะสม + กำไร) / ${(currentVal * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: Color(0xFF10B981),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfitMilestonesSection(OverlayButtonsViewModel overlayVM) {
    final milestones = overlayVM.profitMilestones;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.emoji_events_rounded, color: Color(0xFFF59E0B), size: 20),
                SizedBox(width: 8),
                Text(
                  'Session Milestones History (TP / SL)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (milestones.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Color(0xFF94A3B8), size: 20),
                tooltip: 'Clear Milestones History',
                onPressed: () => overlayVM.clearProfitMilestones(),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (milestones.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
            child: const Column(
              children: [
                Icon(Icons.hourglass_empty_rounded, color: Color(0xFF64748B), size: 36),
                SizedBox(height: 8),
                Text(
                  'No Session Milestones Yet',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Sessions reaching Take-Profit target (+TP) or Stop-Loss (-SL) will be recorded here automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          )
        else
          ...milestones.map((item) {
            final String timeStr = '${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}';
            final String dateStr = '${item.timestamp.day.toString().padLeft(2, '0')}/${item.timestamp.month.toString().padLeft(2, '0')}/${item.timestamp.year}';
            final String resumeTimeStr = '${item.resumeTime.hour.toString().padLeft(2, '0')}:${item.resumeTime.minute.toString().padLeft(2, '0')}';
            final String modeName = item.mode.displayName;
            final bool isTowers = item.mode == GameMode.towers;
            final bool isLoss = item.pnlPercent < 0;

            final Color borderColor = isLoss
                ? const Color(0xFFEF4444).withValues(alpha: 0.35)
                : const Color(0xFF10B981).withValues(alpha: 0.25);
            final Color badgeBg = isLoss
                ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                : const Color(0xFF10B981).withValues(alpha: 0.2);
            final Color badgeTextColor = isLoss
                ? const Color(0xFFF87171)
                : const Color(0xFF10B981);
            final String badgeText = isLoss
                ? '${item.pnlPercent.toStringAsFixed(2)}% 🛑'
                : '+${item.pnlPercent.toStringAsFixed(2)}% 🎯';

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: borderColor,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isTowers ? Icons.account_balance_rounded : Icons.grid_view_rounded,
                            color: isTowers ? const Color(0xFF60A5FA) : const Color(0xFFFBBF24),
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            modeName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$dateStr • $timeStr',
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            color: badgeTextColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: Colors.white10, height: 1),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Ending Balance: ${item.endingBalance.toStringAsFixed(4)}',
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        'Break: ${item.breakMinutes} mins (Resumes $resumeTimeStr)',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
