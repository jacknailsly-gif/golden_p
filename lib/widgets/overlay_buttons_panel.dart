import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';
import 'package:golden_p/models/overlay_button.dart';

class OverlayButtonsPanel extends StatefulWidget {
  final Size screenSize;

  const OverlayButtonsPanel({super.key, required this.screenSize});

  @override
  State<OverlayButtonsPanel> createState() => _OverlayButtonsPanelState();
}

class _OverlayButtonsPanelState extends State<OverlayButtonsPanel> {
  @override
  Widget build(BuildContext context) {
    return Consumer<OverlayButtonsViewModel>(
      builder: (context, viewModel, _) {
        return Stack(
          children: [
            // ===== Draggable Button Overlay =====
            ..._buildMarkerButtons(viewModel),

            // ===== Unified Draggable Control Bar =====
            _buildUnifiedControl(viewModel),
          ],
        );
      },
    );
  }

  // ===== Build Marker Buttons =====
  List<Widget> _buildMarkerButtons(OverlayButtonsViewModel viewModel) {
    return viewModel.buttons.map((button) {
      final bool isActive = viewModel.activeButtonId == button.id;
      final bool isRecording = viewModel.recordingButtonId == button.id;
      final bool isDragging = viewModel.draggingButtonId == button.id;

      // Special Sizing for M4 and M5 (Less intrusive, fit exactly 1/2 and 2x web buttons)
      final bool isSmallMarker = button.id == 'M4' || button.id == 'M5';
      final double baseWidth = isSmallMarker ? 32.0 : 48.0;
      final double baseHeight = isSmallMarker ? 32.0 : 48.0;
      final double activeWidth = isSmallMarker ? 36.0 : 54.0;
      final double activeHeight = isSmallMarker ? 36.0 : 54.0;

      return Positioned(
        left: button.position.dx,
        top: button.position.dy,
        child: IgnorePointer(
          ignoring:
              viewModel.isNativeClickPassthrough ||
              (!viewModel.showMarkers && !isRecording),
          child: AnimatedOpacity(
            opacity: viewModel.showMarkers || isRecording ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: GestureDetector(
              onPanStart: (_) => viewModel.setDraggingButtonId(button.id),
              onPanUpdate: (details) {
                viewModel.updateButtonPosition(
                  button.id,
                  button.position + details.delta,
                );
              },
              onPanEnd: (_) {
                viewModel.saveButtonPosition(button.id, button.position);
                viewModel.setDraggingButtonId(null);
              },
              onLongPress: () => viewModel.startRecording(button.id),
              onTap: () {
                debugPrint('Marker tap: ${button.id}');
              },
              child: _buildMarkerWidget(
                button,
                isHighlighted: isRecording || isActive,
                isActive: isActive,
                isDragging: isDragging,
                clickCount: viewModel.clickCounts[button.id],
                width: baseWidth,
                height: baseHeight,
                activeWidth: activeWidth,
                activeHeight: activeHeight,
                isRect: isSmallMarker,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  // ===== Unified Draggable Control Bar =====
  Widget _buildUnifiedControl(OverlayButtonsViewModel viewModel) {
    return Positioned(
      left: viewModel.controlPosition.dx,
      top: viewModel.controlPosition.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          viewModel.updateControlPosition(
            viewModel.controlPosition + details.delta,
          );
        },
        onPanEnd: (_) => viewModel.saveControlPosition(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white24, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 15,
                spreadRadius: 2,
              ),
            ],
          ),
          padding: const EdgeInsets.all(6),
          child: viewModel.isControlCollapsed
              ? _buildCollapsedTrigger(viewModel)
              : _buildExpandedControls(viewModel),
        ),
      ),
    );
  }

  Widget _buildCollapsedTrigger(OverlayButtonsViewModel viewModel) {
    return InkWell(
      onTap: () => viewModel.toggleControlCollapsed(),
      child: Container(
        padding: const EdgeInsets.all(10),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(
              Icons.settings_suggest_rounded,
              color: Colors.orangeAccent,
              size: 28,
            ),
            if (viewModel.isSequenceRunning)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedControls(OverlayButtonsViewModel viewModel) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Collapse Button
        _buildSmallControl(
          icon: Icons.chevron_left_rounded,
          color: Colors.white60,
          onTap: () => viewModel.toggleControlCollapsed(),
        ),

        const SizedBox(width: 4),

        // Start/Stop
        _buildActionControl(
          icon: viewModel.isSequenceRunning
              ? Icons.stop_rounded
              : Icons.play_arrow_rounded,
          label: viewModel.isSequenceRunning ? 'STOP' : 'START',
          color: viewModel.isSequenceRunning
              ? Colors.redAccent
              : Colors.greenAccent,
          onTap: () => viewModel.toggleSequence(),
        ),

        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(
            height: 24,
            child: VerticalDivider(color: Colors.white24, width: 1),
          ),
        ),

        // Smart Mode Toggle
        _buildSmallControl(
          icon: viewModel.isSmartMode
              ? Icons.psychology
              : Icons.psychology_outlined,
          color: viewModel.isSmartMode ? Colors.purpleAccent : Colors.white60,
          onTap: () => viewModel.toggleSmartMode(),
          tooltip: 'Smart Mode',
        ),

        // Visibility
        _buildSmallControl(
          icon: viewModel.showMarkers
              ? Icons.visibility_rounded
              : Icons.visibility_off_rounded,
          color: viewModel.showMarkers ? Colors.blueAccent : Colors.white60,
          onTap: () => viewModel.toggleShowMarkers(),
          tooltip: 'Show/Hide Markers',
        ),
        // Speed
        _buildSmallControl(
          icon: Icons.speed_rounded,
          color: viewModel.speedMultiplier > 1.0
              ? Colors.orangeAccent
              : Colors.white60,
          onTap: () {
            double nextSpeed = 1.0;
            if (viewModel.speedMultiplier == 1.0) {
              nextSpeed = 1.5;
            } else if (viewModel.speedMultiplier == 1.5) {
              nextSpeed = 2.0;
            }
            viewModel.setSpeedMultiplier(nextSpeed);
          },
          tooltip: 'Speed',
        ),

        // Mode Switch (V17.0)
        _buildSmallControl(
          icon: viewModel.recoveryMode == 1
              ? Icons.shield_outlined
              : Icons.bolt_rounded,
          color: viewModel.recoveryMode == 1
              ? Colors.tealAccent
              : Colors.orangeAccent,
          onTap: () {
            viewModel.recoveryMode = viewModel.recoveryMode == 1 ? 2 : 1;
          },
          tooltip: viewModel.recoveryMode == 1
              ? 'Mode 1: Risk Distribution'
              : 'Mode 2: Profit Boost',
        ),
      ],
    );
  }

  Widget _buildActionControl({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallControl({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }

  // ===== Marker Button Widget =====
  Widget _buildMarkerWidget(
    OverlayButtonModel button, {
    bool isHighlighted = false,
    bool isActive = false,
    bool isDragging = false,
    int? clickCount,
    double width = 48,
    double height = 48,
    double activeWidth = 54,
    double activeHeight = 54,
    bool isRect = false,
  }) {
    final bool currentActive = isActive || isDragging;
    final double currentWidth = currentActive ? activeWidth : width;
    final double currentHeight = currentActive ? activeHeight : height;

    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: currentWidth,
            height: currentHeight,
            decoration: BoxDecoration(
              color:
                  (isActive
                          ? Colors.yellow
                          : (isHighlighted ? button.color : Colors.white))
                      .withValues(alpha: currentActive ? 0.6 : 0.3),
              shape: isRect ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: isRect ? BorderRadius.circular(6) : null,
              border: Border.all(
                color: isActive
                    ? Colors.yellow
                    : (isHighlighted
                          ? button.color
                          : Colors.white.withValues(alpha: 0.5)),
                width: (isHighlighted || isActive || isDragging) ? 2.5 : 1.5,
              ),
              boxShadow: (isHighlighted || isActive || isDragging)
                  ? [
                      BoxShadow(
                        color: (isActive ? Colors.yellow : button.color)
                            .withValues(alpha: 0.5),
                        blurRadius: currentActive ? 12 : 8,
                        spreadRadius: currentActive ? 4 : 2,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Text(
                button.label,
                style: TextStyle(
                  color: (isHighlighted || isActive || isDragging)
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.bold,
                  fontSize: currentActive ? (height * 0.4) : (height * 0.35),
                  shadows: const [
                    Shadow(
                      offset: Offset(0, 1),
                      blurRadius: 2,
                      color: Colors.black45,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Click Counter Badge (For M4, M5)
          if (clickCount != null && clickCount > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Center(
                  child: Text(
                    clickCount > 99 ? '99+' : '$clickCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
