import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';
import 'package:golden_p/viewmodels/sequence_analyzer_viewmodel.dart';

class MarkerControlPanel extends StatefulWidget {
  const MarkerControlPanel({super.key});

  @override
  State<MarkerControlPanel> createState() => _MarkerControlPanelState();
}

class _MarkerControlPanelState extends State<MarkerControlPanel> {
  late TextEditingController _stopProfitController;
  late TextEditingController _maxM5StepsController;
  late TextEditingController _serverUrlController;
  bool _controllerInitialized = false;

  @override
  void dispose() {
    _stopProfitController.dispose();
    _maxM5StepsController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<OverlayButtonsViewModel>(
      builder: (context, viewModel, _) {
        // Initialize controller with current value once
        if (!_controllerInitialized) {
          _stopProfitController = TextEditingController(
            text: viewModel.stopProfitPercent.toStringAsFixed(1),
          );
          _maxM5StepsController = TextEditingController(
            text: viewModel.maxM5Steps.toString(),
          );
          final analyzerViewModel = Provider.of<SequenceAnalyzerViewModel>(context, listen: false);
          _serverUrlController = TextEditingController(
            text: analyzerViewModel.serverUrl,
          );
          _controllerInitialized = true;
        }
        if (viewModel.isSequencePanelCollapsed) {
          return Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton.extended(
              onPressed: viewModel.toggleSequencePanelCollapsed,
              backgroundColor: const Color(0xFF202124),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.settings_suggest, size: 20),
              label: const Text('Auto-Sequence'),
            ),
          );
        }

        return DraggableScrollableSheet(
          initialChildSize: 0.1,
          minChildSize: 0.1,
          maxChildSize: 0.5,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF202124), // Chrome Dark Bg
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                children: [
                  // HandleBar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header: Start/Stop & Clear
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70),
                            onPressed: viewModel.toggleSequencePanelCollapsed,
                            tooltip: 'Hide Panel',
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.only(right: 8),
                          ),
                          const Text(
                            'Auto-Sequence Control',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                            ),
                            onPressed: viewModel.clearSequence,
                            tooltip: 'Clear All Steps',
                          ),
                          ElevatedButton.icon(
                            onPressed: viewModel.toggleSequence,
                            icon: Icon(
                              viewModel.isSequenceRunning
                                  ? Icons.lock // PRO: Show padlock when running/locked
                                  : Icons.play_arrow,
                              color: Colors.white,
                            ),
                            label: Text(
                              viewModel.isSequenceRunning ? 'UNLOCK' : 'START',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: viewModel.isSequenceRunning
                                  ? Colors.redAccent
                                  : Colors.green[600],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const Divider(color: Colors.white12),

                  // Smart Mode Toggle
                  SwitchListTile(
                    title: const Text(
                      '🧠 Smart Logic Engine',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text(
                      'Auto-detect RED/WHITE results & scan for bombs',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    value: viewModel.isSmartMode,
                    onChanged: (val) => viewModel.toggleSmartMode(),
                    activeThumbColor: Colors.purpleAccent,
                  ),

                  const Divider(color: Colors.white12),
                  
                  // WebView Zoom Section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '🔍 Web Content Zoom',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              '${viewModel.webViewTextZoom}%',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                        Slider(
                          value: viewModel.webViewTextZoom.toDouble(),
                          min: 50.0,
                          max: 300.0,
                          divisions: 25,
                          activeColor: Colors.blueAccent,
                          inactiveColor: Colors.white.withValues(alpha: 0.1),
                          onChanged: (val) {
                            viewModel.setWebViewTextZoom(val.toInt());
                          },
                        ),
                      ],
                    ),
                  ),

                  const Divider(color: Colors.white12),
                  
                  // Speed Control Section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '⏲️ Execution Speed',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                                _buildSpeedChip(viewModel, 'Ultra 6x', 6.0),
                                _buildSpeedChip(viewModel, 'Fast 4x', 4.0),
                                _buildSpeedChip(viewModel, 'Normal 2x', 2.0),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const Divider(color: Colors.white12),

                  // --- Stop Loss / Stop Profit Controls ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '💰 Risk Management',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 8),

                        // Stop Profit Row
                        Row(
                          children: [
                            SizedBox(
                              width: 32,
                              height: 24,
                              child: Switch(
                                value: viewModel.isStopProfitEnabled,
                                onChanged: (val) => viewModel.setStopProfitEnabled(val),
                                activeThumbColor: Colors.greenAccent,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('🌟 Stop Profit:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 64,
                              height: 30,
                              child: TextFormField(
                                controller: _stopProfitController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                                decoration: InputDecoration(
                                  suffixText: '%',
                                  suffixStyle: const TextStyle(color: Colors.white54, fontSize: 11),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  filled: true,
                                  fillColor: Colors.white.withValues(alpha: 0.08),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(color: viewModel.isStopProfitEnabled ? Colors.greenAccent.withValues(alpha: 0.5) : Colors.transparent),
                                  ),
                                ),
                                onChanged: (val) {
                                  final parsed = double.tryParse(val);
                                  if (parsed != null && parsed > 0) {
                                    viewModel.setStopProfitPercent(parsed);
                                  }
                                },
                                onFieldSubmitted: (val) {
                                  final parsed = double.tryParse(val);
                                  if (parsed != null && parsed > 0) {
                                    viewModel.setStopProfitPercent(parsed);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Max M5 Row
                        Row(
                          children: [
                            const Icon(Icons.shield_outlined, color: Colors.blueAccent, size: 16),
                            const SizedBox(width: 8),
                            const Text('🛡️ Max M5 Steps:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            const Spacer(),
                            SizedBox(
                              width: 60,
                              height: 30,
                              child: TextFormField(
                                key: Key('m5_steps_${viewModel.maxM5Steps}'),
                                controller: _maxM5StepsController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                                decoration: InputDecoration(
                                  contentPadding: EdgeInsets.zero,
                                  filled: true,
                                  fillColor: Colors.white.withValues(alpha: 0.08),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.3)),
                                  ),
                                ),
                                onChanged: (val) {
                                  final parsed = int.tryParse(val);
                                  if (parsed != null && parsed > 0) {
                                    viewModel.setMaxM5Steps(parsed);
                                  }
                                },
                                onFieldSubmitted: (val) {
                                  final parsed = int.tryParse(val);
                                  if (parsed != null && parsed > 0) {
                                    viewModel.setMaxM5Steps(parsed);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),

                        // Show stop reason if triggered
                        if (viewModel.stopReason.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              viewModel.stopReason,
                              style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const Divider(color: Colors.white12),
                  
                  // Add Step Section
                  if (!viewModel.isSmartMode) ...[
                    const Padding(
                      padding: EdgeInsets.only(top: 8, bottom: 4),
                      child: Text(
                        'Tap to Add Step:',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: viewModel.buttons.map((btn) {
                        return GestureDetector(
                          onTap: () => viewModel.addStep(btn.id),
                          child: Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: btn.color.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Text(
                              btn.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  
                  const SizedBox(height: 16),
                  
                  // Sequence List or Smart Info
                  Text(
                    viewModel.isSmartMode ? 'Smart Flow Active Logic:' : 'Order of Operations:',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  
                  const SizedBox(height: 8),

                  if (viewModel.isSmartMode)
                    _buildSmartLogicSummary(viewModel)
                  else
                    _buildSequenceList(viewModel),

                  const Divider(color: Colors.white24, height: 32),

                  // --- AI Server Settings Section ---
                  _buildServerSettingsSection(context),

                  const SizedBox(height: 40),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildServerSettingsSection(BuildContext context) {
    return Consumer<SequenceAnalyzerViewModel>(
      builder: (context, analyzerViewModel, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🌐 AI Brain Server Settings',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Enter your Ngrok or Public Server URL here.',
              style: TextStyle(color: Colors.white54, fontSize: 10),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _serverUrlController,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'http://localhost:5000',
                      hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.link, color: Colors.blueAccent, size: 18),
                    ),
                    onFieldSubmitted: (val) {
                      analyzerViewModel.updateServerUrl(val.trim());
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    analyzerViewModel.updateServerUrl(_serverUrlController.text.trim());
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ Server URL Saved!'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  icon: const Icon(Icons.save_rounded, color: Colors.greenAccent),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildSmartLogicSummary(OverlayButtonsViewModel viewModel) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLogicStep('1', 'Wait for next result (M0 Detection)'),
          _buildLogicStep('2', 'Update AI Memory with actual bomb position'),
          _buildLogicStep('3', 'Branch: Recover Loss (M5) OR Next Pulse (M1-M3)'),
          _buildLogicStep('4', 'Drawdown Check: 2.5% Cap enforced'),
        ],
      ),
    );
  }

  Widget _buildLogicStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 8,
            backgroundColor: Colors.purpleAccent.withValues(alpha: 0.3),
            child: Text(number, style: const TextStyle(color: Colors.white, fontSize: 10)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 11))),
        ],
      ),
    );
  }

  Widget _buildSequenceList(OverlayButtonsViewModel viewModel) {
    if (viewModel.sequenceSteps.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('No steps added yet.', style: TextStyle(color: Colors.white38)),
        ),
      );
    }
    return Column(
      children: viewModel.sequenceSteps.map((stepId) {
        final btn = viewModel.buttons.firstWhere((b) => b.id == stepId);
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 12,
            backgroundColor: btn.color,
            child: Text(btn.label, style: const TextStyle(color: Colors.white, fontSize: 10)),
          ),
          title: Text(btn.label, style: const TextStyle(color: Colors.white)),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.white54),
            onPressed: () => viewModel.removeStep(viewModel.sequenceSteps.indexOf(stepId)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSpeedChip(OverlayButtonsViewModel viewModel, String label, double speed) {
    final bool isSelected = viewModel.speedMultiplier == speed;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 10)),
      selected: isSelected,
      onSelected: (val) {
        if (val) viewModel.setSpeedMultiplier(speed);
      },
      selectedColor: Colors.orangeAccent.withValues(alpha: 0.3),
      backgroundColor: Colors.white.withValues(alpha: 0.05),
      labelStyle: TextStyle(color: isSelected ? Colors.orangeAccent : Colors.white60),
    );
  }
}
