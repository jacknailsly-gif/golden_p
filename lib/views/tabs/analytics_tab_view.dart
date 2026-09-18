import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/sequence_analyzer_viewmodel.dart';
import '../../viewmodels/overlay_buttons_viewmodel.dart';

class AnalyticsTabView extends StatefulWidget {
  const AnalyticsTabView({super.key});

  @override
  State<AnalyticsTabView> createState() => _AnalyticsTabViewState();
}

class _AnalyticsTabViewState extends State<AnalyticsTabView> {
  final TextEditingController _tpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final overlayVM = context.read<OverlayButtonsViewModel>();
      _tpController.text = overlayVM.stopProfitPercent.toStringAsFixed(1);
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
              _buildStopProfitSection(overlayVM),
              const SizedBox(height: 24),
              _buildRecoveryProfitLevelSection(overlayVM),
              const SizedBox(height: 24),
              _buildTrainingDataSection(overlayVM),
              const SizedBox(height: 24),
              _buildHistorySection(),
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

  Widget _buildStopProfitSection(OverlayButtonsViewModel overlayVM) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: overlayVM.isStopProfitEnabled ? const Color(0xFF10B981) : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.flag_circle, color: Color(0xFF10B981), size: 24),
                  SizedBox(width: 8),
                  Text(
                    'Stop Profit Target',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Switch(
                value: overlayVM.isStopProfitEnabled,
                onChanged: (val) {
                  overlayVM.setStopProfitEnabled(val);
                },
                activeColor: const Color(0xFF10B981),
              ),
            ],
          ),
          if (overlayVM.isStopProfitEnabled) ...[
            const SizedBox(height: 16),
            const Text(
              'Target Profit (%)',
              style: TextStyle(
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
                        overlayVM.setStopProfitPercent(parsed);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    double? parsed = double.tryParse(_tpController.text);
                    if (parsed != null && parsed > 0) {
                      overlayVM.setStopProfitPercent(parsed);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Saved target: $parsed%')),
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

  Widget _buildTrainingDataSection(OverlayButtonsViewModel overlayVM) {
    final logger = overlayVM.trainingDataLogger;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFA855F7).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.science_rounded, color: Color(0xFFA855F7), size: 24),
              SizedBox(width: 8),
              Text(
                'AI Training Data Logger',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F1423),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rows Logged: ${logger.totalRowsLogged}',
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Buffer: ${logger.bufferSize} rows (auto-save every 50)',
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFA855F7).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${logger.totalRowsLogged} rows',
                    style: const TextStyle(
                      color: Color(0xFFA855F7),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final path = await logger.exportNow();
                if (context.mounted) {
                  if (path != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✅ Exported to: $path'),
                        backgroundColor: const Color(0xFF10B981),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('⚠️ No data to export or storage error.'),
                        backgroundColor: Color(0xFFF59E0B),
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.file_download, size: 18),
              label: const Text('Export Training Data (CSV)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA855F7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'ข้อมูลจะถูกบันทึกลง Download/golden_p_training_data/ เพื่อนำไป Train AI Model',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    final history = [
      {'date': 'Today', 'predictions': 12, 'wins': 8, 'winRate': '66.7%'},
      {'date': 'Yesterday', 'predictions': 18, 'wins': 13, 'winRate': '72.2%'},
      {'date': 'Last 7 Days', 'predictions': 95, 'wins': 68, 'winRate': '71.6%'},
      {'date': 'Last 30 Days', 'predictions': 256, 'wins': 175, 'winRate': '68.4%'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Run History',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...history.map((item) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['date'] as String,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item['predictions']} predictions • ${item['wins']} wins',
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item['winRate'] as String,
                    style: const TextStyle(
                      color: Color(0xFF10B981),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
