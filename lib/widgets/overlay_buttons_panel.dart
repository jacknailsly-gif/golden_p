import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';
import 'package:golden_p/models/overlay_button.dart';
import 'package:golden_p/models/game_mode.dart';

class OverlayButtonsPanel extends StatefulWidget {
  final Size screenSize;
  final GameMode gameMode;

  const OverlayButtonsPanel({
    super.key,
    required this.screenSize,
    this.gameMode = GameMode.towers,
  });

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
    final buttons = viewModel.getButtons(widget.gameMode);
    return buttons.map((button) {
      final bool isActive =
          viewModel.getActiveButtonId(widget.gameMode) == button.id;
      final bool isRecording = viewModel.recordingButtonId == button.id;
      final bool isDragging = viewModel.draggingButtonId == button.id;

      // Special Sizing for M1-M5 (Less intrusive, fit exactly in grid slots for Tower/Mines)
      final bool isSmallMarker = button.id != 'M0';
      final double baseWidth = isSmallMarker ? (widget.gameMode == GameMode.mines ? 18.0 : 22.0) : 44.0;
      final double baseHeight = isSmallMarker ? (widget.gameMode == GameMode.mines ? 18.0 : 22.0) : 44.0;
      final double activeWidth = isSmallMarker ? (widget.gameMode == GameMode.mines ? 22.0 : 26.0) : 48.0;
      final double activeHeight = isSmallMarker ? (widget.gameMode == GameMode.mines ? 22.0 : 26.0) : 48.0;

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
                  mode: widget.gameMode,
                );
              },
              onPanEnd: (_) {
                viewModel.saveButtonPosition(
                  button.id,
                  button.position,
                  mode: widget.gameMode,
                );
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
    final Offset ctrlPos = viewModel.getControlPosition(widget.gameMode);
    return Positioned(
      left: ctrlPos.dx,
      top: ctrlPos.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          viewModel.updateControlPosition(
            ctrlPos + details.delta,
            mode: widget.gameMode,
          );
        },
        onPanEnd: (_) => viewModel.saveControlPosition(mode: widget.gameMode),
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
    final bool isRunning = viewModel.isRunningForMode(widget.gameMode);
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
            if (isRunning)
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
    final bool isRunning = viewModel.isRunningForMode(widget.gameMode);
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
          icon: isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
          label: isRunning ? 'STOP' : 'START',
          color: isRunning ? Colors.redAccent : Colors.greenAccent,
          onTap: () => viewModel.toggleSequence(mode: widget.gameMode),
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

        // 🌟 24/7 Autonomous Continuous Mode Toggle / Countdown Timer during 2-3 hour break
        if (viewModel.isBreakActiveFor(widget.gameMode))
          Tooltip(
            message: 'พัก 2-3 ชม. หลังได้กำไร (แตะเพื่อเริ่มทันที)',
            child: GestureDetector(
              onTap: () => viewModel.cancelBreak(mode: widget.gameMode),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: Colors.amberAccent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.amberAccent.withValues(alpha: 0.8),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.timer_outlined,
                      size: 13,
                      color: Colors.amberAccent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      viewModel.getBreakRemainingFormatted(widget.gameMode),
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          _buildSmallControl(
            icon: viewModel.is24HourMode
                ? Icons.all_inclusive_rounded
                : Icons.hourglass_disabled_rounded,
            color: viewModel.is24HourMode ? Colors.amberAccent : Colors.white60,
            onTap: () => viewModel.toggle24HourMode(),
            tooltip: viewModel.is24HourMode ? '24/7 Mode: ON (Non-stop)' : '24/7 Mode: OFF',
          ),

        // OLED Black Screen Saver
        _buildSmallControl(
          icon: Icons.dark_mode_rounded,
          color: viewModel.isBlackScreenSaverActive
              ? Colors.amberAccent
              : Colors.white60,
          onTap: () => viewModel.toggleBlackScreenSaver(),
          tooltip: 'โหมดจอดำ OLED (ประหยัดพลังงาน)',
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
    final control = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 22),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip, child: control);
    }
    return control;
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
