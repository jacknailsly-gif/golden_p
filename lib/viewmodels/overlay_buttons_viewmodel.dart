import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:golden_p/models/overlay_button.dart';
import 'package:golden_p/engines/provably_fair_engine.dart';
import 'dart:async';

class OverlayButtonsViewModel with ChangeNotifier {
  List<OverlayButtonModel> _buttons = [];
  bool _isRunning = false;
  bool _isSmartMode = false;
  bool _showMarkers = true;
  bool _isControlCollapsed = false;
  bool _isSequencePanelCollapsed = false;
  Offset _controlPosition = const Offset(20, 100);
  String? _activeButtonId;
  String? _draggingButtonId;
  final Map<String, int> _clickCounts = {};
  double _speedMultiplier = 1.0; // Higher = Faster (e.g. 2.0 = 2x Faster)
  String? _recordingButtonId;
  late SharedPreferences _prefs;

  // --- Smart Flow State ---
  double? _lowestObservedBet; // PRO: Session-wide memory of lowest bet seen

  // --- Stop Loss / Stop Profit / Safety ---
  bool _isStopProfitEnabled = false;
  double _stopProfitPercent = 10.0;
  int _maxM5Steps = 5; // PRO: Max double-ups before recovery
  String _stopReason = '';

  // V15.0: Zero-Tolerance Single Source of Truth
  final List<String> _lossSequence =
      []; // 🛡️ Tracks 'A', 'B', or 'C' that failed.

  Timer? _slCheckTimer; // High-frequency monitor for TP
  bool _isDisposed = false;
  int _sequenceRunToken = 0;
  bool _nativeClickPassthrough = false;
  
  // --- V25.0 Fortress Safety System ---
  final List<bool> _recentHighConfSuccess = []; // 🛡️ Last 5 high-conf results
  double _sessionMaxBalance = 0.0; 
  int _ghostRoundCounter = 0;
  final double _confThreshold = 0.70;
  final double _riskPercent = 0.025;

  // --- Mandatory Session Break (Bot Detection Avoidance) ---
  DateTime? _sessionStartTime;
  bool _isBreakActive = false;
  int _breakMinutesRemaining = 0;
  Timer? _breakTimer;

  InAppWebViewController? _webViewController;
  Offset _webViewOffset = Offset.zero;
  dynamic _sequenceAnalyzerViewModel;
  int _webViewTextZoom = 100; // Default zoom level

  bool get _isWindowsDesktop => defaultTargetPlatform == TargetPlatform.windows;
  static const MethodChannel _nativeInputChannel = MethodChannel(
    'golden_p/native_input',
  );

  // ลำดับขั้นตอนการกด (list ของ buttonId)
  List<String> _sequenceSteps = [];

  // Getters
  List<OverlayButtonModel> get buttons => _buttons;
  bool get isSequenceRunning => _isRunning;
  bool get isSmartMode => _isSmartMode;
  bool get showMarkers => _showMarkers;
  bool get isControlCollapsed => _isControlCollapsed;
  bool get isSequencePanelCollapsed => _isSequencePanelCollapsed;
  Offset get controlPosition => _controlPosition;
  String? get activeButtonId => _activeButtonId;
  String? get draggingButtonId => _draggingButtonId;
  Map<String, int> get clickCounts => _clickCounts;
  double get speedMultiplier => _speedMultiplier;
  String? get recordingButtonId => _recordingButtonId;
  List<String> get sequenceSteps => _sequenceSteps;
  int get webViewTextZoom => _webViewTextZoom;
  bool get isNativeClickPassthrough => _nativeClickPassthrough;
  bool get shouldAbsorbMainContent => _isRunning && !_nativeClickPassthrough;

  bool get isStopProfitEnabled => _isStopProfitEnabled;
  double get stopProfitPercent => _stopProfitPercent;
  int get maxM5Steps => _maxM5Steps;
  String get stopReason => _stopReason;

  // Break Getters
  bool get isBreakActive => _isBreakActive;
  int get breakMinutesRemaining => _breakMinutesRemaining;

  OverlayButtonsViewModel() {
    _initializeButtons();
  }

  // ===== Initialization =====
  void _initializeButtons() {
    _buttons = List.from(defaultOverlayButtons);
  }

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _isSmartMode = _prefs.getBool('overlay_smart_mode') ?? false;
    _showMarkers = _prefs.getBool('overlay_show_markers') ?? true;
    _isControlCollapsed = _prefs.getBool('overlay_control_collapsed') ?? false;
    _isSequencePanelCollapsed =
        _prefs.getBool('overlay_seq_panel_collapsed') ?? false;
    _speedMultiplier = _prefs.getDouble('overlay_speed_multiplier') ?? 1.0;

    final double ctrlX = _prefs.getDouble('overlay_control_x') ?? 20.0;
    final double ctrlY = _prefs.getDouble('overlay_control_y') ?? 100.0;
    _controlPosition = Offset(ctrlX, ctrlY);

    await loadButtonPositions();
    await loadSequenceFromStorage();

    // Load Stop Loss / Stop Profit settings
    _isStopProfitEnabled = _prefs.getBool('tp_enabled') ?? false;
    _stopProfitPercent = _prefs.getDouble('tp_percent') ?? 10.0;
    _maxM5Steps = _prefs.getInt('max_m5_steps') ?? 5;

    _webViewTextZoom = _prefs.getInt('webview_text_zoom') ?? 100;
  }

  void toggleControlCollapsed() {
    _isControlCollapsed = !_isControlCollapsed;
    _prefs.setBool('overlay_control_collapsed', _isControlCollapsed);
    notifyListeners();
  }

  void toggleSequencePanelCollapsed() {
    _isSequencePanelCollapsed = !_isSequencePanelCollapsed;
    _prefs.setBool('overlay_seq_panel_collapsed', _isSequencePanelCollapsed);
    notifyListeners();
  }

  // --- Stop Loss / Stop Profit Setters ---
  void setStopProfitEnabled(bool val) {
    _isStopProfitEnabled = val;
    _prefs.setBool('tp_enabled', val);
    if (_isRunning) {
      _startPnLMonitor();
    }
    notifyListeners();
  }

  void setStopProfitPercent(double val) {
    _stopProfitPercent = val;
    _prefs.setDouble('tp_percent', val);
    if (_isRunning) {
      _startPnLMonitor();
    }
    notifyListeners();
  }

  void setMaxM5Steps(int val) {
    _maxM5Steps = val;
    _prefs.setInt('max_m5_steps', val);
    notifyListeners();
  }

  void updateControlPosition(Offset newPos) {
    _controlPosition = newPos;
    notifyListeners();
  }

  void saveControlPosition() {
    _prefs.setDouble('overlay_control_x', _controlPosition.dx);
    _prefs.setDouble('overlay_control_y', _controlPosition.dy);
  }

  void toggleSmartMode() {
    _isSmartMode = !_isSmartMode;
    _prefs.setBool('overlay_smart_mode', _isSmartMode);
    notifyListeners();
  }

  void toggleShowMarkers() {
    _showMarkers = !_showMarkers;
    _prefs.setBool('overlay_show_markers', _showMarkers);
    notifyListeners();
  }

  void setSpeedMultiplier(double value) {
    _speedMultiplier = value;
    _prefs.setDouble('overlay_speed_multiplier', value);
    notifyListeners();
  }

  void setWebViewController(InAppWebViewController controller) {
    _webViewController = controller;
  }

  void setWebViewOffset(Offset offset) {
    _webViewOffset = offset;
    notifyListeners();
  }

  void setSequenceAnalyzerViewModel(dynamic viewModel) {
    _sequenceAnalyzerViewModel = viewModel;
  }

  void setWebViewTextZoom(int zoom) {
    if (zoom >= 50 && zoom <= 300) {
      _webViewTextZoom = zoom;
      _prefs.setInt('webview_text_zoom', zoom);

      // Inject native viewport scaling to dynamically expand layout while scaling down
      _webViewController?.evaluateJavascript(
        source:
            """
          var scale = $zoom / 100;
          var meta = document.querySelector('meta[name="viewport"]');
          if (meta) meta.remove();
          var m = document.createElement('meta');
          m.name = 'viewport';
          m.content = 'width=' + (window.screen.width / scale) + ', initial-scale=' + scale + ', maximum-scale=' + scale + ', minimum-scale=' + scale + ', user-scalable=no';
          document.head.appendChild(m);
          window.dispatchEvent(new Event('resize'));
          
          var oldStyle = document.getElementById('golden-zoom-style');
          if (oldStyle) oldStyle.remove();
        """,
      );

      notifyListeners();
    }
  }

  // ===== Button Position Management =====
  Future<void> loadButtonPositions() async {
    final String? jsonStr = _prefs.getString('overlay_buttons_positions');
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        final Map<String, dynamic> positions = Map.from(decoded[0]);

        for (var button in _buttons) {
          if (positions.containsKey(button.id)) {
            final pos = positions[button.id];
            button.position = Offset(
              (pos['x'] as num).toDouble(),
              (pos['y'] as num).toDouble(),
            );
          }
        }
        notifyListeners();
      } catch (e) {
        // Silently handle error in case of corrupted data
      }
    }
  }

  Future<void> saveButtonPosition(String buttonId, Offset position) async {
    final buttonIndex = _buttons.indexWhere((b) => b.id == buttonId);
    if (buttonIndex != -1) {
      final updated = _buttons[buttonIndex].copyWith(position: position);
      _buttons[buttonIndex] = updated;

      // บันทึกลง SharedPreferences
      final Map<String, dynamic> positions = {};
      for (var button in _buttons) {
        positions[button.id] = {
          'x': button.position.dx,
          'y': button.position.dy,
        };
      }

      await _prefs.setString(
        'overlay_buttons_positions',
        jsonEncode([positions]),
      );

      notifyListeners();
    }
  }

  // --- Smart Bot V7.0 State ---
  int _skipNextRounds = 0;
  int _consecutiveLossesStreak = 0;
  double _betScale = 1.0;

  // --- V16.1: Fractional Recovery State ---
  int _recoveryWinsRequired =
      0; // Randomized target: how many wins needed before M5
  int _recoveryWinsAchieved =
      0; // How many consecutive wins achieved since last loss
  bool _isRecoveryUnlocked = false; // True when bot is allowed to press M5
  double _totalAccumulatedLoss = 0.0; // Exact monetary loss sum
  double? _lockedBaseBet; // Locked 1 Unit of Desired Profit
  int _peakLossStreak = 0; // V16.1: Tracks max loss streak during drawdown
  double _recoveryTargetPercent = 0.5; // V21.0: Randomized fractional target (20%-50%)

  // --- V92.0: Ultimate Anti-Loss State ---
  final List<String> _bombHistory = []; // Multi-Bomb Evasion (Tier 3)
  final List<String> _recoveryBombHistory = []; // Evasive history during recovery
  bool _waitingForWinToRecover = false; // Ghost Sniper active flag
  int _ghostSniperWinCount = 0; // Ghost Sniper 2.0 consecutive wins counter
  bool _justWonRecoveryBet = false; // V103.5: Tracks if we just landed a recovery bet (but still have debt)
  int _consecutiveRecoveryLosses = 0;
  final int _maxRecoveryLossesLimit = 2; // Halt and reset after 2 consecutive recovery losses
  
  String? _lastPickedTile; // Anti-Repetition Guard
  int _consecutiveTilePicks = 0; // Anti-Repetition Guard
  
  final Map<String, double> _peakBalanceMemory = {}; // Peak Balance tracking
  String _currentFixedPattern = 'BCBC';
  bool _isFixedPatternEnabled = true; // V92.0: Re-enabled Fixed Pattern

  int _recoveryMode =
      1; // V17.0: 1 = Risk Distribution (Rhythm), 2 = Profit Boost (Immediate)

  // Getters for UI
  int get recoveryMode => _recoveryMode;
  set recoveryMode(int val) {
    _recoveryMode = val;
    notifyListeners();
  }

  // Getters for UI
  int get skipNextRounds => _skipNextRounds;
  int get consecutiveLossesStreak => _consecutiveLossesStreak;
  int get recoveryWinsRequired => _recoveryWinsRequired;
  int get recoveryWinsAchieved => _recoveryWinsAchieved;
  bool get isRecoveryUnlocked => _isRecoveryUnlocked;
  int get consecutiveRecoveryLosses => _consecutiveRecoveryLosses;
  int get maxRecoveryLossesLimit => _maxRecoveryLossesLimit;

  // ===== Button State Management =====
  void updateButtonPosition(String buttonId, Offset newPosition) {
    final index = _buttons.indexWhere((b) => b.id == buttonId);
    if (index != -1) {
      _buttons[index] = _buttons[index].copyWith(position: newPosition);
      notifyListeners();
    }
  }

  void startRecording(String buttonId) {
    _recordingButtonId = buttonId;
    for (var button in _buttons) {
      if (button.id == buttonId) {
        button.isRecording = true;
      } else {
        button.isRecording = false;
      }
    }
    notifyListeners();
  }

  void stopRecording() {
    _recordingButtonId = null;
    for (var button in _buttons) {
      button.isRecording = false;
    }
    notifyListeners();
  }

  void setDraggingButtonId(String? buttonId) {
    _draggingButtonId = buttonId;
    notifyListeners();
  }

  // ===== Sequence Control =====
  void toggleSequence() {
    if (_isRunning) {
      stopSequence();
    } else {
      startSequence();
    }
  }

  Future<void> startSequence() async {
    if (_isDisposed) return;
    if (!_isSmartMode && _sequenceSteps.isEmpty) return;
    _sequenceRunToken++;
    final int runToken = _sequenceRunToken;
    _isRunning = true;
    _consecutiveLossesStreak = 0;
    _lowestObservedBet = null; // PRO: Reset session-wide lowest bet memory
    _stopReason = ''; // Clear previous stop reason
    _skipNextRounds = 0;
    _consecutiveLossesStreak = 0;
    _betScale = 1.0;
    // V16.1: Reset recovery state
    _recoveryWinsRequired = 0;
    _recoveryWinsAchieved = 0;
    _isRecoveryUnlocked = false;
    _totalAccumulatedLoss = 0.0;
    _peakLossStreak = 0;

    // Lock the base bet at start
    double initialBet = await _getBetAmount();
    _lockedBaseBet = (initialBet > 0) ? initialBet : 0.000009; // fallback
    debugPrint(
      '[V15.1 STATE] 🔒 Locked Base Bet at ${_lockedBaseBet?.toStringAsFixed(8)} for the entire session.',
    );

    // 🔄 Reset profit tracking so profit% starts from CURRENT balance
    if (_sequenceAnalyzerViewModel != null) {
      _sequenceAnalyzerViewModel.resetProfitTracking();
    }

    notifyListeners();

    // Start high-frequency monitor timer
    _slCheckCounter = 0;
    debugPrint(
      '[START] 🚀 Sequence started | StopProfit: ${_isStopProfitEnabled ? "ON (${_stopProfitPercent.toStringAsFixed(4)}%)" : "OFF"} | SmartMode: $_isSmartMode',
    );
    _startPnLMonitor();
    _sessionStartTime = DateTime.now(); // Start tracking session duration
    _isBreakActive = false;

    if (_isSmartMode) {
      _executeSmartFlow(runToken);
    } else {
      _executeSequence(runToken);
    }
  }

  void stopSequence() {
    _sequenceRunToken++;
    _isRunning = false;
    _sessionStartTime = null;
    _isBreakActive = false;
    _breakTimer?.cancel();
    _stopPnLMonitor();
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  // --- High-Frequency TP Monitoring Timer ---
  void _startPnLMonitor() {
    _stopPnLMonitor();
    if (_isStopProfitEnabled) {
      _slCheckTimer = Timer.periodic(const Duration(milliseconds: 100), (
        _,
      ) async {
        await _monitorSLTP();
      });
      debugPrint('[PnL MONITOR] Started: Monitoring TP every 100ms');
    }
  }

  void _stopPnLMonitor() {
    _slCheckTimer?.cancel();
    _slCheckTimer = null;
  }

  int _slCheckCounter = 0; // Counter for periodic debug logging

  Future<void> _monitorSLTP() async {
    if (_isDisposed || !_isRunning || _sequenceAnalyzerViewModel == null) {
      return;
    }

    // 🔄 Force a fresh balance update — use FAST single-attempt reader
    try {
      await _sequenceAnalyzerViewModel.updateBalanceFast();
    } catch (_) {}

    // Re-check after async gap — state may have changed
    if (_isDisposed || !_isRunning) return;

    double pnl = _sequenceAnalyzerViewModel.profitPercentage;

    // Periodic log every 50 checks (~5 sec) to show monitor is alive
    _slCheckCounter++;
    if (_slCheckCounter % 50 == 0) {
      debugPrint(
        '[PnL MONITOR] 📊 PnL: ${pnl.toStringAsFixed(4)}% | Target: +${_stopProfitPercent.toStringAsFixed(4)}% | Enabled: $_isStopProfitEnabled',
      );
    }

    // 🌟 1. STOP PROFIT MONITOR (Highest Priority - STOP IMMEDIATELY)
    if (_isStopProfitEnabled && pnl >= _stopProfitPercent) {
      _stopReason =
          '🌟 STOP PROFIT triggered at ${pnl.toStringAsFixed(4)}% (Target: +${_stopProfitPercent.toStringAsFixed(4)}%)';
      debugPrint('[PnL MONITOR] 🛑 $_stopReason — FORCING IMMEDIATE HALT');
      _sequenceRunToken++; // 🛑 Invalidate run token so ALL loops break instantly
      _isRunning = false;
      _stopPnLMonitor();
      if (!_isDisposed) {
        notifyListeners();
      }
      return;
    }
  }

  /// 🛑 Quick check helper — returns true if the bot should stop immediately
  bool _shouldAbort(int runToken) {
    return _isDisposed || !_isRunning || runToken != _sequenceRunToken;
  }

  /// 🛑 Inline Stop Profit check — call this at critical decision points.
  /// Returns true if Stop Profit was triggered and bot should stop.
  Future<bool> _checkStopProfitInline(int runToken) async {
    if (!_isStopProfitEnabled || _sequenceAnalyzerViewModel == null) {
      return false;
    }

    // Force fresh balance read — FAST version
    try {
      await _sequenceAnalyzerViewModel.updateBalanceFast();
    } catch (_) {}

    double pnl = _sequenceAnalyzerViewModel.profitPercentage;
    if (pnl >= _stopProfitPercent) {
      _stopReason =
          '🌟 STOP PROFIT triggered at ${pnl.toStringAsFixed(4)}% (Target: +${_stopProfitPercent.toStringAsFixed(4)}%)';
      debugPrint('[INLINE TP] 🛑 $_stopReason — HALTING NOW');
      _sequenceRunToken++;
      _isRunning = false;
      _stopPnLMonitor();
      if (!_isDisposed) {
        notifyListeners();
      }
      return true;
    }
    return false;
  }

  /// Execute the custom sequence
  Future<void> _executeSequence(int runToken) async {
    while (!_shouldAbort(runToken) && !_isSmartMode) {
      // 🕒 Bot Detection Avoidance: Check for mandatory break
      if (await _handleSessionBreak(runToken)) {
        debugPrint('[SEQUENCE] ☕ Break complete — Resuming next round');
      }
      if (_shouldAbort(runToken)) break;

      // V90.0: DRAWDOWN STOP-LOSS (Removed per user request)
      if (_shouldAbort(runToken)) break;

      for (String buttonId in _sequenceSteps) {
        if (_shouldAbort(runToken) || _isSmartMode) break;
        await _performButtonAction(buttonId);
        if (_shouldAbort(runToken)) break; // 🛑 Check immediately after action
      }
      if (_shouldAbort(runToken)) break; // 🛑 Check before delay
      await Future.delayed(const Duration(milliseconds: 500));
    }
    _isRunning = false;
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  Future<void> _executeSmartFlow(int runToken) async {
    while (!_shouldAbort(runToken) && _isSmartMode) {
      // 🛑 CRITICAL: Check Stop Profit BEFORE starting a new round
      if (await _checkStopProfitInline(runToken)) {
        debugPrint(
          '[SMART FLOW] 🛑 Stop Profit reached — NOT starting new round',
        );
        break;
      }
      if (_shouldAbort(runToken)) break;

      // V25.0 Fortress: Session Max Balance (Logging only)
      double currentBalance = _getBalanceDouble();
      if (currentBalance > _sessionMaxBalance) {
        _sessionMaxBalance = currentBalance;
      }
      
      // V92.0: Peak Balance Memory
      String? coin = _sequenceAnalyzerViewModel?.detectedCoinType;
      if (coin != null && currentBalance > 0) {
        if (!_peakBalanceMemory.containsKey(coin) || currentBalance > _peakBalanceMemory[coin]!) {
            _peakBalanceMemory[coin] = currentBalance;
            debugPrint('[V92.0 PEAK] 📈 New Peak for $coin: $currentBalance');
        }

        // V96.1: Balance Reconciliation Guard (Self-Healing)
        double peak = _peakBalanceMemory[coin]!;
        if (currentBalance >= peak) {
          if (_totalAccumulatedLoss > 0.0) {
            debugPrint('[V96.1 RECONCILE] 🎉 Current Balance ($currentBalance) >= Peak ($peak). Resetting accumulated loss to 0.0!');
            _totalAccumulatedLoss = 0.0;
            _recoveryWinsAchieved = 0;
            _isRecoveryUnlocked = false;
            _peakLossStreak = 0;
            await _ensureBaseBet(runToken);
          }
        } else {
          double actualLoss = peak - currentBalance;
          if ((actualLoss - _totalAccumulatedLoss).abs() > 0.0001) {
            debugPrint('[V103.4 RECONCILE] 📈 Target Loss synced to Peak Balance gap: ${actualLoss.toStringAsFixed(2)}');
            _totalAccumulatedLoss = actualLoss;
          }
        }
      }
      // Auto-switch removed by user request (V27.1)

      // 🕒 Bot Detection Avoidance: Check for mandatory break
      if (await _handleSessionBreak(runToken)) {
        debugPrint('[SMART FLOW] ☕ Break complete — Resuming next round');
      }
      if (_shouldAbort(runToken)) break;

      // 1. Humanized Delay (150-450ms)
      final int humanDelay = 150 + Random().nextInt(300);
      await Future.delayed(
        Duration(milliseconds: (humanDelay / _speedMultiplier).round()),
      );

      if (_shouldAbort(runToken) || !_isSmartMode) break;

      // 10. Volatility Control (Beta: Bet Scaling)
      await _updateLowestObservedBet();
      if (_shouldAbort(runToken)) break; // 🛑 STOP PROFIT CHECK

      // V20.6: SMART COOL-DOWN (Still present to prevent bot detection)
      if (_consecutiveLossesStreak > 0) {
        final int coolDown = 1500 + Random().nextInt(2000); // 1.5-3.5 seconds
        debugPrint('[V20.6] 🧘 COOL-DOWN: Waiting ${coolDown}ms after loss...');
        await Future.delayed(Duration(milliseconds: (coolDown / _speedMultiplier).round()));
      }

      // 3. M0 Start — strict:false because SmartFlow detection loop handles timing
      debugPrint('V7.0 [EXEC]: Starting at M0');
      await _performButtonAction('M0', strict: false);
      if (_shouldAbort(runToken)) break; // 🛑 STOP PROFIT CHECK

      // V20.8: Windows WebView2 can lag behind slow network responses.
      // Give it a longer real-time grace period before picking a box.
      final int m0LoadDelay = _isWindowsDesktop
          ? (1200 + Random().nextInt(800))
          : (800 + Random().nextInt(1000));
      debugPrint(
        'V20.7 [LOAD]: Waiting ${m0LoadDelay}ms for the game to load after M0...',
      );
      await Future.delayed(Duration(milliseconds: (m0LoadDelay / _speedMultiplier).round()));
      if (_shouldAbort(runToken)) break; // 🛑 STOP PROFIT CHECK

      // V25.0 Fortress: Ghost Round (Break detection pattern)
      _ghostRoundCounter++;
      bool isGhostRound = false;
      if (_ghostRoundCounter >= 15 + Random().nextInt(10)) {
        isGhostRound = true;
        _ghostRoundCounter = 0;
        debugPrint('[V25.0 GHOST] 👻 Strategic Noise Round. Picking random target.');
      }

      String prediction = 'None';
      String targetId;

      if (isGhostRound) {
          // V103: Ghost Round STILL uses bomb evasion engine (not pure random)
          // This prevents Ghost Round from accidentally picking a recently-bombed column
          prediction = ProvablyFairEngine().getNextPrediction();
          targetId = prediction == 'A' ? 'M1' : (prediction == 'B' ? 'M2' : 'M3');
          debugPrint('[V103 GHOST] 👻 Ghost Round with bomb evasion: $prediction');
      } else {
          // V94.5: Pure Provably Fair Mirror Engine (No Evasive AI, No Bias)
          prediction = ProvablyFairEngine().getNextPrediction();
          debugPrint('[V94.5 PROVABLY FAIR] 🎲 Shadow Engine Predicted: $prediction');
          
          if (prediction != 'A' && prediction != 'B' && prediction != 'C') prediction = 'A';
          
          targetId = prediction == 'A' ? 'M1' : (prediction == 'B' ? 'M2' : 'M3');
      }
      
      debugPrint(
        'V15.0 [AI PREDICT]: $prediction (via $targetId) — Using Pure AI',
      );

      // V18 Shadow Hunter: Emergency Reset Check
      if (_sequenceAnalyzerViewModel.isEmergencyResetRequired &&
          _lowestObservedBet != null) {
        debugPrint("🕵️ [V18 EMERGENCY] Hunt detected! Resetting bet to base.");
        double currentBet = await _getBetAmount();
        int attempts = 0;
        while (currentBet > _lowestObservedBet! &&
            attempts < 20 &&
            !_shouldAbort(runToken)) {
          await _performButtonAction('M4', strict: false);
          await Future.delayed(
            Duration(milliseconds: (300 / _speedMultiplier).round()),
          );
          currentBet = await _getBetAmount();
          attempts++;
        }
      }

      if (prediction != 'A' && prediction != 'B' && prediction != 'C') {
        debugPrint('Smart Flow: Invalid prediction "$prediction". Returning.');
        continue;
      }

      final String targetMarker = (prediction == 'A')
          ? 'M1'
          : (prediction == 'B' ? 'M2' : 'M3');

      if (targetMarker.isEmpty) {
        debugPrint(
          'Smart Flow: No valid prediction (A/B/C). Returning to start.',
        );
        await Future.delayed(
          Duration(milliseconds: (1000 / _speedMultiplier).round()),
        );
        continue;
      }

      // 4. Active Flow — strict:false, detection loop below handles outcome
      debugPrint('Smart Flow: Executing Active Flow at $targetMarker');
      await _performButtonAction(targetMarker, strict: false);
      if (_shouldAbort(runToken)) break; // 🛑 STOP PROFIT CHECK

      // Wait for result UI to appear. Keep Windows waits real-time because
      // speed mode can otherwise outrun WebView2/network updates.
      final int resultWaitMs = _isWindowsDesktop
          ? (1000 / _speedMultiplier).round()
          : (800 / _speedMultiplier).round();
      await Future.delayed(Duration(milliseconds: resultWaitMs));
      if (_shouldAbort(runToken)) break; // 🛑 STOP PROFIT CHECK

      // 5 & 6. Guaranteed M0 Detection Loop (PRO)
      bool resolutionFound = false;
      int m0Retries = 0;
      final int maxM0Retries = _isWindowsDesktop ? 70 : 40;
      while (!_shouldAbort(runToken) &&
          _isSmartMode &&
          !resolutionFound &&
          m0Retries < maxM0Retries) {
        m0Retries++;
        // Wait for M0 button text to update
        final int scanDelayMs = _isWindowsDesktop
            ? (800 / _speedMultiplier).round()
            : (1000 / _speedMultiplier).round();
        await Future.delayed(Duration(milliseconds: scanDelayMs));
        if (_shouldAbort(runToken)) break; // 🛑 STOP PROFIT CHECK

        debugPrint('Smart Flow: Scanning M0 for CASHOUT or BET text');
        String m0Status = await _detectVisualOutcomeWithVerification('M0');
        if (_shouldAbort(runToken)) break; // 🛑 STOP PROFIT CHECK

        if (m0Status == 'cashout') {
          debugPrint(
            'Smart Flow: 💰 CASHOUT detected at M0 (Success). Claiming and Resetting.',
          );
          resolutionFound = true; // Break the detection loop

          // Successful round: Winner is what we clicked (targetMarker)
          String gemPos = (targetMarker == 'M1')
              ? 'A'
              : (targetMarker == 'M2' ? 'B' : 'C');
          await _sequenceAnalyzerViewModel.recordInput(
            gemPos,
            triggerId: targetMarker,
            multiplier: _betScale,
            selectedAction: prediction,
          );
          if (_shouldAbort(runToken)) break; // 🛑 STOP PROFIT CHECK

          // V7.0 Success Reset
          _consecutiveLossesStreak = 0;
          _skipNextRounds = 0;
          _betScale = 1.0;
          _lossSequence
              .clear(); // 🛡️ V15.0: Clear absolute ban sequence on WIN
          
          // V103: Record WIN in prediction engine
          ProvablyFairEngine().recordWin();
          debugPrint(
            'V103 [SUCCESS]: WIN recorded. Loss history cleared in prediction engine.',
          );

          // V25.0 Fortress: Accuracy Tracking
          double confAtRound = _sequenceAnalyzerViewModel.confidence;
          if (confAtRound >= _confThreshold) {
            _recentHighConfSuccess.add(true);
            if (_recentHighConfSuccess.length > 5) _recentHighConfSuccess.removeAt(0);
          }

          // 1. Click M0 to claim
          await _performButtonAction('M0');
          if (_shouldAbort(runToken)) break; // 🛑 STOP PROFIT CHECK
          await Future.delayed(
            Duration(milliseconds: (800 / _speedMultiplier).round()),
          );
          if (_shouldAbort(runToken)) break; // 🛑 STOP PROFIT CHECK

          // ═══════════════════════════════════════════════════════
          // V103.5: MATHEMATICAL RECOVERY — Win Branch
          // ═══════════════════════════════════════════════════════

          double winningBet = await _getBetAmount();
          final bool wonRecoveryBet = winningBet > (_lockedBaseBet ?? 0.0) + 0.00000001;

          if (wonRecoveryBet) {
            _consecutiveRecoveryLosses = 0;
            _justWonRecoveryBet = true;
          } else {
            _ghostSniperWinCount++;
            _justWonRecoveryBet = false;
          }

          // We let the start of the next round (Peak Balance sync) handle _totalAccumulatedLoss mathematically.
          // However, we need to check if this win brought us back to peak right now for status messages.
          double profit = winningBet * 0.42;
          bool isFullyRecovered = (_totalAccumulatedLoss - profit) <= 0.0001;

          if (isFullyRecovered) {
            // RECOVERY COMPLETELY FINISHED
            _totalAccumulatedLoss = 0.0;
            _recoveryWinsAchieved = 0;
            _isRecoveryUnlocked = false;
            _peakLossStreak = 0;
            _ghostSniperWinCount = 0;
            _justWonRecoveryBet = false; // Finished recovering

            _randomizeRhythm();

            debugPrint(
              '[V103.5 RECOVERY] 🌟 Full Recovery Achieved! Resetting to base bet.',
            );
            await _ensureBaseBet(runToken);
          } else {
            // STILL HAVE PENDING LOSSES (Partial Win due to Caps)
            debugPrint(
              '[V103.5 RECOVERY] 🔄 Partial Win. Remaining Loss (approx): ${(_totalAccumulatedLoss - profit).toStringAsFixed(2)}',
            );
            
            // Delegate entirely to V103.5 AI Policy to calculate the next recovery chain
            await _executeM5RecoveryEscalation(runToken);
          }
          if (_shouldAbort(runToken)) break; // 🛑 STOP PROFIT CHECK

          // 3. Reset Martingale Counts (M4) & rotation on full recovery
          _clickCounts['M4'] = 0;
          if (_totalAccumulatedLoss <= 0.0) {
            _clickCounts['M5'] = 0;
          }
          _consecutiveLossesStreak = 0;
          notifyListeners();
          debugPrint('Smart Flow: Counters reset after Success.');

          // 🛑 CRITICAL: After cashout + recovery, check profit BEFORE next round
          if (await _checkStopProfitInline(runToken)) {
            debugPrint(
              '[SMART FLOW] 🛑 Stop Profit reached after WIN — stopping',
            );
            break;
          }
        } else if (m0Status == 'bet') {
          debugPrint(
            'Smart Flow: 🎰 BET detected at M0 (Failure). V14.6 Delayed Recovery.',
          );
          resolutionFound = true; // Break the detection loop

          // 🛑 STOP PROFIT: If triggered during loss handling, abort immediately
          if (_shouldAbort(runToken)) break;

          // V25.0 Fortress: Accuracy Tracking
          double confAtRound = _sequenceAnalyzerViewModel.confidence;
          if (confAtRound >= _confThreshold) {
            _recentHighConfSuccess.add(false);
            if (_recentHighConfSuccess.length > 5) _recentHighConfSuccess.removeAt(0);
          }

          // --- V3.0: Automated Bomb Detection ---
          String? discoveredBombPos = await _findRevealedBombPosition();
          debugPrint(
            'Smart Flow [V3.0]: Discovered Bomb Position: $discoveredBombPos',
          );
          if (_shouldAbort(runToken)) break; // 🛑

          // Trigger Prediction update with actual bomb position for V3.0 Seed-Drift.
          // IMPORTANT: This branch is confirmed LOSS (m0Status == 'bet').
          String gemPos = 'Unknown';
          if (discoveredBombPos != null && discoveredBombPos != prediction) {
            final remaining = [
              'A',
              'B',
              'C',
            ].where((c) => c != prediction && c != discoveredBombPos).toList();
            if (remaining.isNotEmpty) {
              gemPos = remaining.first; // Accurately deduced real winner
            }
          }
          if (gemPos == 'Unknown') {
            gemPos = [
              'A',
              'B',
              'C',
            ].firstWhere((c) => c != prediction, orElse: () => 'A');
            debugPrint(
              'V15.2 [LOSS SAFETY]: Deduced safe gemPos $gemPos, avoiding Unknown matrix corruption.',
            );
          }

          await _sequenceAnalyzerViewModel.recordInput(
            gemPos,
            triggerId: targetMarker,
            actualBombPos: discoveredBombPos,
            multiplier: _betScale,
            selectedAction: prediction,
          );
          
          if (discoveredBombPos != null) {
            _bombHistory.add(discoveredBombPos);
            if (_bombHistory.length > 5) _bombHistory.removeAt(0); // Keep last 5
            
            // V103: Feed bomb position to prediction engine
            ProvablyFairEngine().recordBomb(discoveredBombPos);
            
            if (_isRecoveryUnlocked) {
               _recoveryBombHistory.add(discoveredBombPos);
               if (_recoveryBombHistory.length > 5) _recoveryBombHistory.removeAt(0);
            }
          }
          
          // V103: Record our losing pick in prediction engine
          ProvablyFairEngine().recordLoss(prediction);
          
          if (_shouldAbort(runToken)) break; // 🛑 STOP PROFIT CHECK

          // ═══════════════════════════════════════════════════════
          // V103: MATHEMATICAL RECOVERY — Loss Branch
          // ═══════════════════════════════════════════════════════

          double currentBetStr = await _getBetAmount();

          if (_lockedBaseBet != null && currentBetStr > _lockedBaseBet! + 0.000001) {
            _consecutiveRecoveryLosses++;
          }

          _consecutiveLossesStreak++;
          _justWonRecoveryBet = false;
          // Note: _totalAccumulatedLoss is automatically recalculated at the start of the next round using Peak Balance.

          // V103: Rotate seed after 3+ losses to break casino pattern lock
          if (_consecutiveLossesStreak >= 3) {
            ProvablyFairEngine().rotateSeed();
            debugPrint('[V103] 🔄 Loss Streak >= 3. Rotated seed. Bot continues playing.');
          }

          if (_consecutiveLossesStreak > _peakLossStreak) {
            _peakLossStreak =
                _consecutiveLossesStreak; // V16.1 Update peak streak
          }

          _recoveryWinsAchieved = 0; // Reset win counter on new loss
          _ghostSniperWinCount = 0; // V92.0: Reset Ghost Sniper consecutive wins
          
          // V97.0: Seed already rotated by V103 above for streak >= 3
          if (_consecutiveLossesStreak < 3) {
            debugPrint('[V97.0 PROVABLY FAIR] ⛓️ Loss Streak = $_consecutiveLossesStreak (<= 2). Kept the same seed.');
          }
          
          // ═══════════════════════════════════════════════════════
          // V98.0: AI-GOVERNED RECOVERY — Loss Branch
          // ═══════════════════════════════════════════════════════
          
          // Delegate entirely to V98.0 AI Policy
          await _executeM5RecoveryEscalation(runToken);
          if (_shouldAbort(runToken)) break;

          // V15.3: AUTHORITY FIX - Record the ACTUAL action that was clicked, not just the prediction intent.
          String actualClickedChar = (targetMarker == 'M1')
              ? 'A'
              : (targetMarker == 'M2' ? 'B' : 'C');
          _lossSequence.add(actualClickedChar);
          if (_lossSequence.length > 5) _lossSequence.removeAt(0);
          debugPrint(
            'V15.3 [LOCK/AUTHORITY]: 🛡️ RECORDED ACTUAL LOSS on $actualClickedChar. Sequence: $_lossSequence',
          );
        } else {
          final bool shouldRetryM0 = !_isWindowsDesktop || m0Retries % 5 == 0;
          if (shouldRetryM0) {
            // Guaranteed M0 PRO: Retry click if no clear status
            debugPrint(
              'Smart Flow: No clear status at M0 after $m0Retries scans. Retrying M0 once...',
            );
            await _performButtonAction('M0', strict: false);
            if (_shouldAbort(runToken)) break; // 🛑 STOP PROFIT CHECK
          } else {
            debugPrint(
              'Smart Flow: M0 still updating on Windows WebView. Waiting without retry ($m0Retries/$maxM0Retries).',
            );
          }
        }
      }

      // 🛑 EMERGENCY HALT: If M0 detection keeps failing, the game is stuck.
      if (!resolutionFound) {
        debugPrint(
          '🚨 [EMERGENCY HALT] Failed to detect outcome after $maxM0Retries retries. Network or Casino is unresponsive. Stopping sequence to prevent rogue bets.',
        );
        _sequenceAnalyzerViewModel.advice =
            "🚨 [TIMEOUT] Network/Casino is unresponsive. Bot halted for safety.";
        stopSequence();
        break;
      }
      if (_shouldAbort(runToken)) {
        break; // 🛑 STOP PROFIT CHECK after detection loop
      }

      // Small delay before next overall round starts
      // V29.0 Ghost Protocol: Randomized round delay (1.2s - 2.8s)
      int baseDelay = (1200 / _speedMultiplier).round();
      int jitterDelay = (Random().nextInt(1600) / _speedMultiplier).round(); // 0 to 1.6s jitter
      int totalDelay = baseDelay + jitterDelay;
      
      debugPrint('[V29.0 GHOST] 🕒 Round interval: ${totalDelay}ms');
      await Future.delayed(Duration(milliseconds: totalDelay));
    }
    _isRunning = false;
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  /// 🕒 Bot Detection Avoidance Logic
  /// Returns true if a break was taken, false otherwise.
  Future<bool> _handleSessionBreak(int runToken) async {
    if (_sessionStartTime == null || _shouldAbort(runToken)) return false;

    final Duration playDuration = DateTime.now().difference(_sessionStartTime!);

    // Check if we've played for more than 60 minutes
    if (playDuration.inMinutes >= 60) {
      debugPrint(
        '[SESSION BREAK] 🕒 Mandatory break triggered! Duration played: ${playDuration.inMinutes} mins',
      );

      // Calculate random break duration (8-16 minutes)
      final int breakMins = 8 + Random().nextInt(9); // 8 to 16
      _breakMinutesRemaining = breakMins;
      _isBreakActive = true;
      notifyListeners();

      _breakTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
        if (_shouldAbort(runToken)) {
          timer.cancel();
          return;
        }
        _breakMinutesRemaining--;
        if (_breakMinutesRemaining <= 0) {
          timer.cancel();
        }
        notifyListeners();
      });

      // Wait loop for the break duration
      while (_breakMinutesRemaining > 0 && !_shouldAbort(runToken)) {
        if (_sequenceAnalyzerViewModel != null) {
          _sequenceAnalyzerViewModel.advice =
              "☕ [PROTECTION] Taking a break... Resuming in $_breakMinutesRemaining mins";
        }
        // Wait 1 minute at a time
        await Future.delayed(const Duration(seconds: 60));
      }

      // Reset for next session
      _isBreakActive = false;
      _sessionStartTime = DateTime.now(); // Reset start time to current
      _breakTimer?.cancel();
      notifyListeners();

      if (_sequenceAnalyzerViewModel != null) {
        _sequenceAnalyzerViewModel.advice =
            "✅ Break complete! Session restarted.";
      }

      return true;
    }

    return false;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _sequenceRunToken++;
    _isRunning = false;
    _stopPnLMonitor();
    super.dispose();
  }

  /// Helper to perform a button action by its ID
  Future<void> _performButtonAction(
    String buttonId, {
    bool strict = true,
  }) async {
    // V29.0: Add human jitter before clicking
    await _humanJitter();

    final button = _buttons.firstWhere(
      (b) => b.id == buttonId,
      orElse: () => _buttons.first,
    );

    if (button.type == 'webview_click') {
      if (_webViewController != null && button.position != Offset.zero) {
        // --- Anti-Stuck: Capture Signature Before ---
        final String? beforeSig = await _getPageSignature();

        // Visual Feedback (Reduced for utility buttons)
        _activeButtonId = buttonId;
        notifyListeners();

        final bool isUtility = buttonId == 'M4' || buttonId == 'M5';
        await Future.delayed(Duration(milliseconds: ((isUtility ? 50 : 200) / _speedMultiplier).round()));

        final bool isSmall = buttonId == 'M4' || buttonId == 'M5';
        final double centerX = button.position.dx + (isSmall ? 16.0 : 24.0);
        final double centerY = button.position.dy + (isSmall ? 16.0 : 24.0);

        final double scale = _webViewTextZoom / 100.0;
        final int x = ((centerX - _webViewOffset.dx) / scale).toInt();
        final int y = ((centerY - _webViewOffset.dy) / scale).toInt();
        final int r = ((isSmall ? 16 : 24) / scale)
            .toInt(); // PRO: Scaled radius for M4/M5

        debugPrint(
          'Smart Clicking Marker $buttonId at Center ($x, $y) with radius $r',
        );

        // Increment Click Counter for M4/M5
        if (buttonId == 'M4' || buttonId == 'M5') {
          _clickCounts[buttonId] = (_clickCounts[buttonId] ?? 0) + 1;
          notifyListeners();
        }


        bool nativeClickHandled = false;
        if (_isWindowsDesktop) {
          debugPrint('[V26.0] 🖥️ Executing NATIVE click for $buttonId');
          nativeClickHandled = await _performWindowsNativeClick(centerX, centerY, buttonId);
        }

        if (!nativeClickHandled) {
          debugPrint('[V26.0] 🌐 Executing JS click fallback for $buttonId');
          final String clickScript =
              """
              (function(x, y, r, markerId) {
                function doClick(el, px = x, py = y) {
                  if (!el) return false;
                  const base = {
                    bubbles: true,
                    cancelable: true,
                    composed: true,
                    view: window,
                    clientX: px,
                    clientY: py,
                    screenX: window.screenX + px,
                    screenY: window.screenY + py,
                    pageX: px + window.scrollX,
                    pageY: py + window.scrollY,
                    button: 0
                  };
                  
                  const pointerDown = {...base, pointerId: 1, pointerType: 'touch', isPrimary: true, buttons: 1};
                  const pointerUp = {...base, pointerId: 1, pointerType: 'touch', isPrimary: true, buttons: 0};
                  const mDown = new MouseEvent('mousedown', { ...base, buttons: 1 });
                  const mUp = new MouseEvent('mouseup', { ...base, buttons: 0 });
                  const mClick = new MouseEvent('click', { ...base, buttons: 0 });

                  try { el.dispatchEvent(new PointerEvent('pointerover', pointerDown)); } catch(e){}
                  try { el.dispatchEvent(new PointerEvent('pointerenter', pointerDown)); } catch(e){}
                  
                  try { el.dispatchEvent(new PointerEvent('pointerdown', pointerDown)); } catch(e){}
                  try { el.dispatchEvent(mDown); } catch(e){}
                  
                  try { el.dispatchEvent(new PointerEvent('pointerup', pointerUp)); } catch(e){}
                  try { el.dispatchEvent(mUp); } catch(e){}
                  
                  // Primary click action
                  try { 
                    if (typeof el.click === 'function') {
                      el.click(); 
                    } else {
                      el.dispatchEvent(mClick);
                    }
                  } catch(e){
                    el.dispatchEvent(mClick);
                  }
                  
                  if (el.focus) el.focus();
                  return true;
                }

                // --- PRO: Specific Target Hunter for M4 (1/2) and M5 (2x) ---
                if (markerId === 'M4' || markerId === 'M5') {
                  const isM4 = markerId === 'M4';
                  const keywords = isM4 ? ['1/2', 'half'] : ['2x', 'x2', 'double'];

                  const checkMatch = (el) => {
                    if (!el) return false;
                    const t = (el.innerText || el.textContent || el.getAttribute('aria-label') || el.value || "").toLowerCase().trim();
                    for (let kw of keywords) {
                      if (t === kw || t.includes(kw)) return true;
                    }
                    return false;
                  };

                  // Search in a grid around (x, y) with a larger radius up to 80px
                  const huntRadius = 80;
                  for (let i = 0; i <= 5; i++) {
                    const currentR = (huntRadius * i) / 5;
                    const angles = i === 0 ? [0] : [0, 45, 90, 135, 180, 225, 270, 315];
                    
                    for (let angle of angles) {
                      const rad = (angle * Math.PI) / 180;
                      const sx = x + Math.cos(rad) * currentR;
                      const sy = y + Math.sin(rad) * currentR;
                      let el = document.elementFromPoint(sx, sy);
                      
                      if (el) {
                         // 1. Direct match
                         if (checkMatch(el)) return doClick(el, sx, sy);
                          
                          // 2. Parent match (if hitting an icon inside the button)
                          if (el.parentElement && checkMatch(el.parentElement)) return doClick(el.parentElement, sx, sy);

                         // 3. Scan nearby container
                         let container = el;
                         for (let j = 0; j < 3 && container; j++) {
                           let candidates = container.querySelectorAll('button, div.btn, span, a');
                           for (let cand of candidates) {
                             if (checkMatch(cand)) {
                               const rect = cand.getBoundingClientRect();
                                const dx = rect.left + rect.width/2 - x;
                                const dy = rect.top + rect.height/2 - y;
                                if (Math.sqrt(dx*dx + dy*dy) < 150) {
                                  return doClick(cand, rect.left + rect.width/2, rect.top + rect.height/2);
                                }
                              }
                            }
                           container = container.parentElement;
                         }
                      }
                    }
                  }
                }

                // --- PRO: Element Penetration (Anti-Input) Standard Logic ---
                const getActualTarget = (px, py) => {
                  let el = document.elementFromPoint(px, py);
                  let hiddenEls = [];
                  while (el && el.tagName && el.tagName.toLowerCase() === 'input' && (el.type === 'text' || el.type === 'number')) {
                    hiddenEls.push({ el: el, oldPointerEvents: el.style.pointerEvents });
                    el.style.pointerEvents = 'none';
                    el = document.elementFromPoint(px, py);
                  }
                  hiddenEls.forEach(item => item.el.style.pointerEvents = item.oldPointerEvents || '');
                  return el;
                };

                const isClickable = (el) => {
                  if (!el) return false;
                  const tag = el.tagName.toLowerCase();
                  const type = el.getAttribute('type')?.toLowerCase();
                  if (tag === 'input' && (type === 'text' || type === 'number')) return false; 
                  const style = window.getComputedStyle(el);
                  return ['button', 'a', 'select', 'canvas'].includes(tag) || 
                         (tag === 'input' && type !== 'text' && type !== 'number') || 
                         style.cursor === 'pointer' || 
                         el.onclick || 
                         el.getAttribute('role') === 'button' ||
                         el.classList.contains('btn') ||
                         el.classList.contains('clickable');
                };

                let target = getActualTarget(x, y);
                const findClickableAncestor = (el) => {
                   let current = el;
                   for (let i = 0; i < 4 && current && current !== document.body; i++) {
                      if (isClickable(current)) return current;
                      current = current.parentElement;
                   }
                   return null;
                };

                let clickableCenter = findClickableAncestor(target);
                if (clickableCenter) return doClick(clickableCenter, x, y);

                const steps = 4; 
                for (let i = 1; i <= steps; i++) {
                  const currentR = (r * i) / steps;
                  for (let angle = 0; angle < 360; angle += 45) {
                    const rad = (angle * Math.PI) / 180;
                    const sx = x + Math.cos(rad) * currentR;
                    const sy = y + Math.sin(rad) * currentR;
                    let el = getActualTarget(sx, sy);
                    let clickableEl = findClickableAncestor(el);
                    if (clickableEl && clickableEl !== target) {
                      return doClick(clickableEl, sx, sy);
                    }
                  }
                }
                return doClick(target, x, y);
              })($x, $y, $r, '$buttonId');
            """;

          final dynamic clickResult = await _webViewController!
              .evaluateJavascript(source: clickScript)
              .timeout(
                const Duration(seconds: 5),
                onTimeout: () {
                  debugPrint('⚠️ [TIMEOUT] Button click script timed out.');
                  return null;
                },
              );
          if (clickResult == false || clickResult?.toString() == 'false') {
            debugPrint(
              '⚠️ [CLICK MISS] No clickable target found for $buttonId at ($x, $y).',
            );
          }
        }

        await Future.delayed(Duration(milliseconds: ((isUtility ? 50 : 100) / _speedMultiplier).round()));
        _activeButtonId = null;
        notifyListeners();

        // --- Anti-Stuck PRO: Lightweight Page Change Detection ---
        // FIXED: Was 300 polls × 200ms = 60s freeze. Now capped at 15 polls (3s).
        // SmartFlow has its own detection loop — this is just a quick confirmation.
        // For SmartFlow calls (strict:false), skip polling entirely.
        final bool isStrict = strict && !isUtility;
        if (isStrict) {
          bool changed = false;
          int polls = 0;
          const int maxPolls = 15; // 15 × 200ms = 3s max

          while (_isRunning && !changed && polls < maxPolls) {
            await Future.delayed(
              Duration(milliseconds: (200 / _speedMultiplier).round()),
            );
            final String? afterSig = await _getPageSignature();
            if (afterSig != null && afterSig != beforeSig) {
              changed = true;
              debugPrint('[Anti-Stuck] Page changed after ${polls + 1} polls.');
            } else {
              polls++;
            }
          }
          if (!changed) {
            debugPrint(
              '[Anti-Stuck] Timeout after $maxPolls polls for $buttonId. Continuing anyway.',
            );
          }
        } else {
          // Utility/non-strict: just a tiny pause, no polling needed
          await Future.delayed(
            Duration(milliseconds: (100 / _speedMultiplier).round()),
          );
        }
      } else {
        debugPrint(
          '⚠️ [CLICK SKIP] $buttonId cannot click. WebView ready: ${_webViewController != null}, marker position: ${button.position}.',
        );
      }
    } else if (button.type == 'predictor') {
      if (_sequenceAnalyzerViewModel != null && button.predictorValue != null) {
        // Visual Feedback
        _activeButtonId = buttonId;
        notifyListeners();

        debugPrint('Triggering Predictor ${button.predictorValue}');
        await _sequenceAnalyzerViewModel.recordInput(
          button.predictorValue!,
          triggerId: buttonId,
        );

        await Future.delayed(const Duration(milliseconds: 300));
        _activeButtonId = null;
        notifyListeners();
      }
    }

    // Wait for the specified delay / speed multiplier
    int finalDelay = (button.delayMs / _speedMultiplier).round();
    await Future.delayed(Duration(milliseconds: finalDelay));
  }

  /// V26.0 Native Click Implementation for Windows
  Future<bool> _performWindowsNativeClick(
    double logicalX,
    double logicalY,
    String buttonId,
  ) async {
    _nativeClickPassthrough = true;
    notifyListeners();

    try {
      // 1. Pre-click grace period (Humanize)
      await Future.delayed(const Duration(milliseconds: 60));
      
      // 2. Invoke MethodChannel
      final bool? clicked = await _nativeInputChannel
          .invokeMethod<bool>('click', <String, double>{
            'x': logicalX,
            'y': logicalY,
          })
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () {
              debugPrint('⚠️ [NATIVE CLICK TIMEOUT] $buttonId');
              return false;
            },
          );
          
      // 3. Post-click grace period
      await Future.delayed(const Duration(milliseconds: 80));
      return clicked == true;
    } catch (e) {
      debugPrint('⚠️ [NATIVE CLICK FALLBACK] $buttonId failed: $e');
      return false;
    } finally {
      _nativeClickPassthrough = false;
      notifyListeners();
    }
  }


  /// Helper to get current bet amount from the WebView
  Future<double> _getBetAmount() async {
    if (_webViewController == null) return 0.0;
    try {
      final dynamic result = await _webViewController!
          .evaluateJavascript(
            source: """
          (function() {
            // Find input field for bet amount
            const selectors = [
              'input[type="number"]', 
              'input[placeholder*="bet"i]', 
              'input[aria-label*="bet"i]',
              'input.bet-input',
              '.bet-amount input'
            ];
            
            for (let s of selectors) {
              const el = document.querySelector(s);
              if (el && el.value) {
                const val = parseFloat(el.value);
                if (!isNaN(val) && val > 0) return val;
              }
            }
            
            // Generic scan for numbers in inputs
            const inputs = document.querySelectorAll('input');
            for (let input of inputs) {
              const val = parseFloat(input.value);
              if (!isNaN(val) && val > 0 && val < 1000) return val; // Heuristic for bet amount
            }
            
            return 0;
          })()
        """,
          )
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint('⚠️ [TIMEOUT] _getBetAmount script timed out.');
              return 0; // Return JS 0 not double 0.0 because dynamic result is used
            },
          );
      if (result == null) return 0.0;
      return double.tryParse(result.toString()) ?? 0.0;
    } catch (e) {
      debugPrint('Error getting bet amount: $e');
      return 0.0;
    }
  }

  /// V26.1: Helper to set bet amount via JS injection
  Future<void> _setBetAmount(double amount) async {
    if (_webViewController == null) return;
    try {
      final String amountStr = amount.toStringAsFixed(8);
      debugPrint('[V26.1] ⌨️ Setting bet amount to $amountStr');
      
      await _webViewController!.evaluateJavascript(
        source: """
          (function(val) {
            const selectors = [
              'input[type="number"]', 
              'input[placeholder*="bet"i]', 
              'input[aria-label*="bet"i]',
              'input.bet-input',
              '.bet-amount input'
            ];
            
            let input = null;
            for (let s of selectors) {
              const el = document.querySelector(s);
              if (el) { input = el; break; }
            }
            
            if (!input) {
              const inputs = document.querySelectorAll('input');
              for (let i of inputs) {
                if (i.type === 'number' || i.type === 'text') { input = i; break; }
              }
            }

            if (input) {
              // V26.2: High-Level State Hijack for React/Vue Compatibility
              const nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value").set;
              if (nativeInputValueSetter) {
                nativeInputValueSetter.call(input, val);
              } else {
                input.value = val;
              }
              
              // Dispatch full event chain to trigger internal app state updates
              input.dispatchEvent(new Event('input', { bubbles: true }));
              input.dispatchEvent(new Event('change', { bubbles: true }));
              input.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, key: 'Enter' }));
              input.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true, key: 'Enter' }));
              
              // Force blur to trigger final validation if any
              input.blur();
              return true;
            }
            return false;
          })('$amountStr')
        """,
      ).timeout(const Duration(seconds: 2));
      
      // V26.2: Essential safety delay to allow web framework to sync state
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      debugPrint('Error setting bet amount: $e');
    }
  }

  /// Gets a signature of the current page content to detect stuck screens
  Future<String?> _getPageSignature() async {
    if (_webViewController == null) return null;
    try {
      final result = await _webViewController!
          .evaluateJavascript(
            source: """
        (function() {
          const body = document.body;
          const text = body.innerText || "";
          const inputs = Array.from(document.querySelectorAll('input')).map(i => i.value).join('|');
          const digits = (text.match(/\\d/g) || []).length;
          // Combine length, digit count, and inputs to detect changes effectively
          return text.length + "_" + document.querySelectorAll('*').length + "_" + digits + "_" + inputs;
        })()
      """,
          )
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              return null;
            },
          );
      return result?.toString();
    } catch (_) {
      return null;
    }
  }

  // ===== Visual Detection & Analytics =====
  
  /// V25.0 Fortress: Verified detection using double-scan checksum
  Future<String> _detectVisualOutcomeWithVerification(String markerId) async {
    String firstScan = await _detectVisualOutcome(markerId);
    
    // Wait for animation to settle if status is detected
    if (firstScan != 'none') {
      await Future.delayed(Duration(milliseconds: (400 / _speedMultiplier).round()));
      String secondScan = await _detectVisualOutcome(markerId);
      
      if (firstScan == secondScan) {
        return firstScan;
      } else {
        debugPrint('[V25.0 CHECKSUM] ⚠️ Mismatch: $firstScan vs $secondScan. Retrying...');
        return 'none'; // Require stability
      }
    }
    return firstScan;
  }

  /// Detects visual outcome (color or image) at a specific marker's location
  Future<String> _detectVisualOutcome(String markerId) async {
    if (_webViewController == null) return 'none';

    final button = _buttons.firstWhere(
      (b) => b.id == markerId,
      orElse: () => _buttons.first,
    );
    if (button.position == Offset.zero) return 'none';

    final bool isSmall = markerId == 'M4' || markerId == 'M5';
    final double scale = _webViewTextZoom / 100.0;
    final int x =
        ((button.position.dx + (isSmall ? 16.0 : 24.0) - _webViewOffset.dx) /
                scale)
            .toInt();
    final int y =
        ((button.position.dy + (isSmall ? 16.0 : 24.0) - _webViewOffset.dy) /
                scale)
            .toInt();

    try {
      final dynamic result = await _webViewController!
          .evaluateJavascript(
            source:
                """
        (function(x, y) {
          function checkAtPoint(px, py) {
            const el = document.elementFromPoint(px, py);
            if (!el) return 'none';
            
            const text = (el.innerText || el.value || el.textContent || "").toUpperCase();
            const style = window.getComputedStyle(el);
            const bgColor = style.backgroundColor;
            const bgImg = style.backgroundImage.toLowerCase();
            const html = el.innerHTML.toLowerCase();
            
            // 1. Text Status Detection (High Priority for M0)
            if (text.includes('CASHOUT')) return 'cashout';
            if (text.includes('BET')) return 'bet';
            
            // 2. Keyword/Icon Detection
            if (bgImg.includes('bomb') || bgImg.includes('mine') || html.includes('bomb')) return 'bomb';
            if (bgImg.includes('diamond') || bgImg.includes('gem') || html.includes('diamond')) return 'diamond';
            
            // 3. Pixel Analysis (Dark sphere + Light spikes)
            try {
              const canvas = document.createElement('canvas');
              canvas.width = 30; canvas.height = 30;
              const ctx = canvas.getContext('2d');
              ctx.drawImage(document.body, px - 15, py - 15, 30, 30, 0, 0, 30, 30);
              const c1 = ctx.getImageData(15, 15, 1, 1).data;
              if (c1[0] < 40 && c1[1] < 40 && c1[2] < 60) {
                 const spikeData = ctx.getImageData(5, 5, 1, 1).data;
                 if (spikeData[0] > 100 || spikeData[1] > 100) return 'bomb';
              }
            } catch(e) {}
            
            if (bgColor.includes('244, 67, 54') || bgColor.includes('255, 0, 0')) return 'red';
            if (bgColor.includes('255, 255, 255')) return 'white';
            return 'none';
          }

          // Search center and small radius
          const radius = 8;
          const points = [[0,0], [0,-radius], [0,radius], [-radius,0], [radius,0]];
          
          for (let p of points) {
            const res = checkAtPoint(x + p[0], y + p[1]);
            if (res === 'cashout' || res === 'bet' || res === 'bomb' || res === 'diamond') return res;
          }
          return 'none';
        })($x, $y);
      """,
          )
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint('⚠️ [TIMEOUT] Visual detection script timed out.');
              return 'none';
            },
          );

      final String detection = result?.toString() ?? 'none';
      debugPrint('Visual Detection at $markerId: $detection');
      return detection;
    } catch (e) {
      debugPrint('Error in visual detection: $e');
      return 'none';
    }
  }

  // ===== Sequence Step Management =====
  void addStep(String buttonId) {
    _sequenceSteps.add(buttonId);
    _saveSequenceToStorage();
    notifyListeners();
  }

  void removeStep(int index) {
    if (index >= 0 && index < _sequenceSteps.length) {
      _sequenceSteps.removeAt(index);
      _saveSequenceToStorage();
      notifyListeners();
    }
  }

  void reorderSteps(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final String item = _sequenceSteps.removeAt(oldIndex);
    _sequenceSteps.insert(newIndex, item);
    _saveSequenceToStorage();
    notifyListeners();
  }

  void clearSequence() {
    _sequenceSteps.clear();
    _saveSequenceToStorage();
    notifyListeners();
  }

  Future<void> _saveSequenceToStorage() async {
    await _prefs.setString('marker_sequence_steps', jsonEncode(_sequenceSteps));
  }

  Future<void> loadSequenceFromStorage() async {
    final String? jsonStr = _prefs.getString('marker_sequence_steps');
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        _sequenceSteps = decoded.cast<String>();
        notifyListeners();
      } catch (e) {
        debugPrint('Error loading sequence: $e');
      }
    }
  }

  List<OverlayButtonModel> getRecordedButtons() {
    // ปุ่มที่มีตำแหน่งบันทึกไว้แล้ว (สำหรับ auto-click)
    return _buttons.where((btn) => btn.position != const Offset(0, 0)).toList();
  }

  Future<void> addButton(String id, String label, Color color) async {
    final newButton = OverlayButtonModel(id: id, label: label, color: color);
    _buttons.add(newButton);
    notifyListeners();
    await saveButtonPosition(id, const Offset(0, 0));
  }

  Future<void> removeButton(String buttonId) async {
    _buttons.removeWhere((btn) => btn.id == buttonId);

    final Map<String, dynamic> positions = {};
    for (var button in _buttons) {
      positions[button.id] = {'x': button.position.dx, 'y': button.position.dy};
    }

    await _prefs.setString(
      'overlay_buttons_positions',
      jsonEncode([positions]),
    );

    notifyListeners();
  }

  /// V29.0: Simulates human reaction time/jitter before a click
  Future<void> _humanJitter() async {
    int jitter = 50 + Random().nextInt(250); // 50ms to 300ms
    await Future.delayed(Duration(milliseconds: (jitter / _speedMultiplier).round()));
  }

  /// V29.0: Sets a randomized number of wins required for recovery (1-4)
  void _randomizeRhythm() {
    _recoveryWinsRequired = 1 + Random().nextInt(4); // 1, 2, 3, or 4
    debugPrint('[V29.0 GHOST] 🧬 Dynamic Rhythm set: ${_recoveryWinsRequired} wins required.');
  }

  void clearAllPositions() {
    for (var button in _buttons) {
      button.position = const Offset(0, 0);
    }
    _prefs.remove('overlay_buttons_positions');
    notifyListeners();
  }

  /// Helper to update the lowest observed bet for session memory
  Future<void> _updateLowestObservedBet() async {
    final double bet = await _getBetAmount();
    if (bet > 0) {
      if (_lowestObservedBet == null || bet < _lowestObservedBet!) {
        _lowestObservedBet = bet;
        debugPrint(
          'Smart Flow [PRO]: New Lowest Observed Bet Memory: $_lowestObservedBet',
        );
        notifyListeners();
      }
    }
  }

  /// V3.0: Finds which marker currently contains a bomb after a loss
  Future<String?> _findRevealedBombPosition() async {
    if (_webViewController == null) return null;

    // Check M1, M2, M3
    for (String mId in ['M1', 'M2', 'M3']) {
      String status = await _detectVisualOutcome(mId);
      if (status == 'bomb') {
        return mId == 'M1' ? 'A' : (mId == 'M2' ? 'B' : 'C');
      }
    }
    return null;
  }

  /// Helper to get current balance as a double
  double _getBalanceDouble() {
    if (_sequenceAnalyzerViewModel == null) return 0.0;
    String? balanceStr = _sequenceAnalyzerViewModel!.currentBalance;
    if (balanceStr == null) return 0.0;
    return double.tryParse(balanceStr.replaceAll(',', '').trim()) ?? 0.0;
  }

  /// V14.6: Ensure bet is at base level (lowest observed bet)
  /// Used during Stay-at-Base phases when recovery is not yet unlocked
  Future<void> _ensureBaseBet(int runToken) async {
    if (_lowestObservedBet == null) return;
    debugPrint('[V26.3] 🔄 Resetting to Base Bet: $_lowestObservedBet');
    await _setBetAmount(_lowestObservedBet!);
  }

  /// V103.5: Full Recovery with Smart Caps & Chain Recovery
  /// 
  /// Strategy: Always target 100% debt recovery, but strict bet caps prevent bankruptcy:
  /// - Max bet = 10% of balance (portfolio protection)
  /// - Small debts → recovered in 1 shot
  /// - Large debts → naturally split across multiple rounds by the caps
  /// - After 2 recovery losses → cool down at base bet
  /// - Balance < 20x base → survival mode
  Future<void> _executeM5RecoveryEscalation(int runToken) async {
    if (_lockedBaseBet == null) return;

    double balance = _getBalanceDouble();
    if (balance <= 0.0) return;

    // RULE: Survival Mode — if balance is critically low, base bet only
    if (balance < _lockedBaseBet! * 20.0) {
      debugPrint('[V103 SURVIVAL] 🛡️ Balance (${balance.toStringAsFixed(2)}) < 20x Base. Survival mode — base bet only.');
      await _ensureBaseBet(runToken);
      return;
    }

    // RULE: After 2 consecutive recovery losses, cool down
    if (_consecutiveRecoveryLosses >= _maxRecoveryLossesLimit) {
      debugPrint('[V103 COOLDOWN] ⛔ $_consecutiveRecoveryLosses consecutive recovery losses. Resetting to base.');
      _consecutiveRecoveryLosses = 0;
      _ghostSniperWinCount = 0;
      _justWonRecoveryBet = false;
      ProvablyFairEngine().rotateSeed();
      await _ensureBaseBet(runToken);
      return;
    }

    if (_totalAccumulatedLoss <= 0.0) {
      _consecutiveRecoveryLosses = 0;
      await _ensureBaseBet(runToken);
      return;
    }

    // Determine if we are allowed to recover right now
    bool canRecover = false;
    String recoveryReason = "";

    if (_consecutiveLossesStreak == 1) {
        canRecover = true; 
        recoveryReason = "Immediate Counter (Loss Streak 1)";
    } else if (_consecutiveLossesStreak >= 2) {
        // แพ้ 2+ ตา → กลับ Base Bet รอจนกว่าจะชนะ
        debugPrint('[V103.5] 👻 Loss Streak $_consecutiveLossesStreak: Back to base bet until we win.');
        await _ensureBaseBet(runToken);
        return;
    } else if (_consecutiveLossesStreak == 0) {
        if (_justWonRecoveryBet) {
            canRecover = true;
            recoveryReason = "Chain Recovery (Just won recovery but still in debt)";
        } else if (_ghostSniperWinCount >= 1) {
            canRecover = true;
            recoveryReason = "Post-Wait Strike (Ghost Win)";
        }
    }

    if (canRecover) {
       // V103.5: Target FULL debt recovery (caps will limit actual bet size)
       double targetLoss = _totalAccumulatedLoss;
       debugPrint('[V103.5 RECOVERY] 🎯 $recoveryReason. Full recovery target: ${targetLoss.toStringAsFixed(2)}');

       double requiredBet = (targetLoss + _lockedBaseBet!) / 0.42;

       // CAP: ทบไม่เกิน 10% ของเงินในบัญชี
       double maxCap = balance * 0.10;
       if (requiredBet > maxCap) {
          debugPrint('[V103.5 CAP] 🚨 Bet capped at 10% balance: ${maxCap.toStringAsFixed(2)}');
          requiredBet = maxCap;
       }
       
       // Casino hard limit
       if (requiredBet > 3000.0) {
           requiredBet = 3000.0;
       }

       double currentBet = await _getBetAmount();
       if (currentBet < requiredBet) {
          await _setBetAmount(requiredBet);
          debugPrint('[V103.5 RECOVERY] 🎯 Recovery Pulse: ${requiredBet.toStringAsFixed(2)}');
       }
    } else {
       debugPrint('[V103.5] 🤖 Waiting for condition before recovery... (Losses: $_consecutiveLossesStreak, Ghost Wins: $_ghostSniperWinCount)');
       await _ensureBaseBet(runToken);
    }
  }
}
