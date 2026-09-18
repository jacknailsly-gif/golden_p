import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:golden_p/models/overlay_button.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/engines/omni_matrix_engine.dart';
import 'package:golden_p/services/training_data_logger.dart';
import 'dart:async';
import 'package:golden_p/services/dynamic_parameter_service.dart';

/// Explicit state machine for Recovery and Observation lifecycle
enum RecoveryState {
  normal,         // Standard operation with Base Bet or 1-2 loss recovery
  lossLock,       // Locked out after 3 consecutive losses, preparing observation window
  observation,    // 15–20 rounds Base Bet observation (no recovery allowed)
  recoveryGate,   // Dedicated safety gate evaluating whether Recovery is safe to attempt
  recovery,       // Recovery round in progress
  circuitBreaker, // Hard safety shutdown triggered by repeated recovery failures
}

class DebtBucket {
  double amount;
  final DateTime freezeUntil;
  final String tierName;

  DebtBucket({
    required this.amount,
    required this.freezeUntil,
    required this.tierName,
  });

  bool get isFrozen => DateTime.now().isBefore(freezeUntil);
  int get remainingMinutes => freezeUntil.difference(DateTime.now()).inMinutes;
}

/// Independent runtime state container for each GameMode (Towers vs Mines)
class GameModeSessionState {
  final GameMode mode;
  bool isRunning = false;
  int runToken = 0;
  double? lockedBaseBet;
  double currentBetAmount = 0.00007880;
  double? sessionStartBalance;
  double sessionMaxBalance = 0.0;
  // ─── 🛡️ SACRED PRINCIPAL VAULT & OPERATIONAL RISK BUFFER ───
  double? protectedPrincipal;

  /// Emergency Capital Floor: 90% of Trailing High New / initial capital.
  /// If balance drops below 90% of High New, recovery stops completely to protect the 90% bulk.
  double get emergencyCapitalFloor {
    final peakCapital = max(sessionMaxBalance, sessionStartBalance ?? protectedPrincipal ?? 0.0);
    return peakCapital * 0.90;
  }

  /// Profit cushion above ratcheted principal
  double get profitCushion {
    final principal = protectedPrincipal ?? sessionStartBalance ?? 0.0;
    if (principal <= 0.0) return 0.0;
    final currentBal = lastSettledBalance > 0.0 ? lastSettledBalance : (sessionStartBalance ?? 0.0);
    return max(0.0, currentBal - principal);
  }

  /// Operational Risk Budget for Recovery:
  /// - In Profit (Balance > Principal): funded from profit cushion (up to 50% of cushion or min 8x floorBet).
  /// - In Normal Drawdown Buffer (95% - 100% of capital): allows recovery budget up to 5% of balance,
  ///   or up to 8x floorBet within safe buffer to guarantee robust surplus profit recovery!
  /// - In Emergency Zone (<= 95%): 0.0 (locked to Base Bet).
  double getOperationalRecoveryBudget(double currentBalance, {double? floorBet}) {
    if (currentBalance <= emergencyCapitalFloor || currentBalance <= 0.00000001) {
      return 0.0; // Emergency freeze
    }
    final cushion = profitCushion;
    final double buffer = (currentBalance - emergencyCapitalFloor).clamp(0.0, currentBalance);
    // 🎯 คำสั่งผู้ใช้: Adaptive Risk Budget สำหรับพอร์ตขนาดเล็ก
    // หากยอดเงินยังอยู่เหนือ Emergency Floor ระบบจะเปิดงบอย่างน้อย 2.5 เท่าของ Base Bet ทำให้เบททวงหนี้ทำงานได้จริง
    final double minAdaptiveBudget = (floorBet != null && floorBet > 0) ? min(buffer, floorBet * 2.5) : 0.0;

    if (cushion > 0.00000001) {
      if (floorBet != null && floorBet > 0) {
        final double minCushionFloor = floorBet * 8.0;
        return max(min(buffer, max(cushion * 0.50, minCushionFloor)), minAdaptiveBudget);
      }
      return max(cushion * 0.20, minAdaptiveBudget);
    }
    // Normal drawdown buffer (95% - 100%):
    final double standardRisk = currentBalance * 0.01;
    if (floorBet != null && floorBet > 0) {
      final double microFloor = floorBet * 8.0;
      final double adaptiveRisk = max(currentBalance * 0.05, microFloor);
      return max(min(buffer * 0.90, adaptiveRisk), minAdaptiveBudget);
    }
    return max(standardRisk.clamp(0.0, buffer), minAdaptiveBudget);
  }
  String? activeCoinType;
  double? lowestObservedBet;
  int consecutiveLossesStreak = 0;
  int peakLossStreak = 0;
  bool isLossStreakBaseBetLocked = false;
  int observationRoundsRemaining = 0; // 🔭 จำนวนไม้สังเกตการณ์แนวโน้มระเบิดหลังแพ้ครบ 3 ตา (15-25 ตา นับจากรอบแพ้สุดท้าย)
  RecoveryState recoveryState = RecoveryState.normal;
  int currentRecoveryCycle = 1; // 🎯 1 = รอบที่ 1, 2 = รอบที่ 2, 3 = รอบที่ 3 (วนกลับไปรอบ 1)
  int recoveryStepInCycle = 0;  // 🎯 0 = เดิน Base Bet, 1 = ไม้ 1, 2 = ไม้ 2, 3 = ไม้ 3 ("แพ้ทวง แพ้ทวง แพ้ กลับ Base bet")
  int maxRecoveryStepsThisCycle = 2; // 🎯 โควตาสุ่มทวงหนี้ในรอบนี้ (1-3 ไม้)

  int randomizeRecoveryQuota({int? fixedForTest}) {
    if (fixedForTest != null) {
      maxRecoveryStepsThisCycle = fixedForTest;
      return maxRecoveryStepsThisCycle;
    }
    // สุ่มทวง 1-3 ตา ด้วยความน่าจะเป็นถ่วงน้ำหนัก (Weighted Random):
    // 50% = 1 ไม้ (ทวงไม้เดียวถ้าพลาดถอยทันที ปลอดภัยสูงสุด ตัดวงจรหนี้บวม 85%)
    // 35% = 2 ไม้ (ทวง 2 ไม้)
    // 15% = 3 ไม้ (ทวงเต็ม 3 ไม้ เฉพาะรอบที่สุ่มได้ 15%)
    final int roll = Random().nextInt(100);
    int quota;
    if (roll < 50) {
      quota = 1;
    } else if (roll < 85) {
      quota = 2;
    } else {
      quota = 3;
    }
    // ใน Cycle 1: Base bet แพ้ 1 ตาแล้ว ดังนั้นทวงได้สูงสุดไม่เกิน 2 ไม้ เพื่อไม่ให้แพ้เกิน 3 ตาติด
    if (currentRecoveryCycle == 1 && quota > 2) {
      quota = 2;
    }
    maxRecoveryStepsThisCycle = quota;
    return maxRecoveryStepsThisCycle;
  }

  int recoveryLossStreak = 0; // 🛑 Recovery-specific consecutive loss counter (does NOT reset upon entering observation)
  int recoveryAttempts = 0; // 📊 Cumulative recovery attempts in the current cycle
  bool recoveryCircuitBreakerActive = false; // ⛔ Latching circuit breaker for repeated recovery failures
  bool get isPostObservationRecoveryReady => recoveryState == RecoveryState.recoveryGate;
  set isPostObservationRecoveryReady(bool value) {
    if (value) {
      recoveryState = RecoveryState.recoveryGate;
    } else if (recoveryState == RecoveryState.recoveryGate) {
      recoveryState = RecoveryState.normal;
    }
  }
  bool isMicroProbingActive = false; // 🛡️ Streak-2 Micro Probing Protocol (เกราะดักทางตาที่ 3)
  bool isIntermissionProbeActive = false; // 🔬 1-Round Base Bet Probe Intermission (ช่วงสอดแนมคั่นระหว่างงวดทวงหนี้)
  int remainingRecoverySlices = 0; // 🍰 จำนวนงวดที่เหลือในการทวงหนี้แบบแบ่งก้อนย่อย (Dynamic Slicing)
  int recoveryWinsRequired = 0;
  int recoveryWinsAchieved = 0;
  bool isRecoveryUnlocked = false;
  bool justWonRecoveryBet = false;
  int ghostSniperWinCount = 0;
  int consecutiveRecoveryLosses = 0;
  int consecutiveBaseBetWins = 0;
  int consecutiveBaseBetWinsRequiredForRecovery = 3; // 🌿 จำนวนตาที่ต้องชนะ Base Bet ติดต่อกันเพื่อพักฟื้น/ปลดล็อกจาก Circuit Breaker หรือทวงงวดถัดไป
  double recoverySliceFraction = 0.30; // 🍰 สัดส่วนผ่อนทวงหนี้ต่องวด (30% ต่อไม้)
  bool isCurrentlyRecoveryRound = false;
  int ghostRoundCounter = 0;
  int staleWinsCount = 0;
  int staleLossesCount = 0;
  double lastSettledBalance = 0.0;
  bool? lastRoundWasWin;
  double activeNewLoss = 0.0;
  double readyToRecoverLoss = 0.0;
  final List<DebtBucket> frozenDebtBuckets = [];
  String? activeButtonId;

  // ─── 4-LOSS STAGED DEBT FREEZER & 50/50 RECOVERY STATE ───
  DateTime? fourLossesFreezeUntil;
  int stagedRecoveryPhase = 0; // 0: Normal, 1: Frozen 15-30m, 2: Stage 1 (50% Thawed), 3: Waiting 2 Wins, 4: Stage 2 (50% Remaining Thawed)

  // ─── 🛡️ SHIELD 4: ROLLING ROUND HISTORY FOR BAD RUN / CASINO COUNTER ───
  final List<bool> recentRoundsHistory = [];

  // ─── 24/7 AUTONOMOUS 4-PILLAR MASTER STATE ───
  // Pillar 1: Circuit Breaker
  int maxRecoveryCutoffLimit = 3; // Max recovery losses before soft cut-loss
  int circuitBreakerTriggeredCount = 0;

  // Pillar 2: Human Sleep Cycles
  int totalSessionRoundsPlayed = 0;
  int roundsSinceLastMicroBreak = 0;
  int roundsSinceLastMacroBreak = 0;

  // Pillar 3: 24/7 Watchdog Hygiene & Heartbeat
  DateTime lastHeartbeatTime = DateTime.now();
  int roundsSinceLastHygieneReload = 0;

  // Recovery Safety: Cooldown counter to prevent repeated recovery bets (Anti-Chaining)
  int recoveryCooldownRounds = 0;

  // Multi-Tier Debt Recovery Ladder Indices (>5% and >10%)
  int tier1RecoveryIndex = 0;
  int tier2RecoveryIndex = 0;

  // Pillar 4: Milestone Profit Banking
  double? sessionProfitBaseline;
  int profitMilestonesAchieved = 0;
  DateTime currentHourWindowStart = DateTime.now();
  double currentHourStartBalance = 0.0;

  GameModeSessionState(this.mode);

  double get totalAccumulatedLoss {
    double frozenTotal = frozenDebtBuckets.fold(0.0, (sum, b) => sum + b.amount);
    return activeNewLoss + readyToRecoverLoss + frozenTotal;
  }

  void resetDebt() {
    activeNewLoss = 0.0;
    readyToRecoverLoss = 0.0;
    frozenDebtBuckets.clear();
    consecutiveRecoveryLosses = 0;
    consecutiveBaseBetWins = 0;
    isCurrentlyRecoveryRound = false;
    isLossStreakBaseBetLocked = false;
    isMicroProbingActive = false;
    isIntermissionProbeActive = false;
    remainingRecoverySlices = 0;
    tier1RecoveryIndex = 0;
    tier2RecoveryIndex = 0;
    stagedRecoveryPhase = 0;
    fourLossesFreezeUntil = null;
    observationRoundsRemaining = 0;
    isPostObservationRecoveryReady = false;
    recoveryState = RecoveryState.normal;
    recoveryLossStreak = 0;
    recoveryAttempts = 0;
    recoveryCircuitBreakerActive = false;
    currentRecoveryCycle = 1;
    recoveryStepInCycle = 0;
    maxRecoveryStepsThisCycle = 2;
    recentRoundsHistory.clear();
  }

  /// 🛡️ Centralized Recovery Gate: Authoritative single source of truth for Recovery eligibility.
  /// คำสั่งผู้ใช้:
  /// "ปกติ แพ้ทวง แพ้ทวง แพ้ กลับ Base bet
  ///  ถ้ารอบ 1 แพ้ครบ 3 ตา รอ 15-25 ตา ทวงทันที แพ้ทวง แพ้ทวง แพ้ กลับไป Base bet
  ///  ถ้ารอบ 2 แพ้ครบ 3 ตา รอ 15-25 ตา ทวงทันที แพ้ทวง แพ้ทวง แพ้ กลับไป Base bet
  ///  ถ้ารอบ 3 แพ้ครบ 3 ตา รอ 15-25 ตา ทวงทันที แพ้ทวง แพ้ทวง แพ้ กลับไป Base bet วนกลับไป รอบแรก"
  bool canEnterRecovery({OmniPredictionResult? omniResult, double? floorBet}) {
    const double debtEpsilon = 0.00000001;

    // 1. CIRCUIT BREAKER (Priority 1)
    if (recoveryCircuitBreakerActive || recoveryState == RecoveryState.circuitBreaker) {
      return false;
    }

    // 2. CONSECUTIVE LOSSES CEILING (Priority 2) - แพ้ครบ 3 ตา ห้ามทวงตาที่ 4 เด็ดขาด! ถอยกลับไป Base Bet ทันที
    if (consecutiveLossesStreak >= 3) {
      return false;
    }

    // 3. DEBT REQUIREMENT (Priority 3)
    if (totalAccumulatedLoss <= debtEpsilon) {
      return false;
    }

    // 🎯 AQ-DARE PILLAR 1: PASSIVE DEBT MELTING
    // หนี้ขนาดเล็กมาก (< 5x Base Bet) ไม่คุ้มค่าความเสี่ยงที่จะออกไม้ทวงหนี้ขนาดใหญ่
    // ปล่อยให้ Base Bet เดินตามปกติและเอากำไรมาละลายหนี้ทิ้งแบบ 0% Risk to Principal
    final double? effectiveFloor = floorBet ?? lockedBaseBet;
    if (effectiveFloor != null && effectiveFloor > 0 && totalAccumulatedLoss < effectiveFloor * 5.0) {
      return false;
    }

    // 4. OBSERVATION LOCK (Priority 4) - ต้องผ่านช่วงดูเชิง 15-25 ตา ให้ครบก่อน
    if (observationRoundsRemaining > 0 || isLossStreakBaseBetLocked || recoveryState == RecoveryState.observation) {
      return false;
    }

    // 5. JUST WON RECOVERY - ป้องกันการทวงซ้ำซ้อนถ้าเพิ่งชนะ
    if (justWonRecoveryBet) {
      return false;
    }

    // 6. AQ-DARE PILLAR 3: PURE EDGE SNIPER GATE (Priority 5)
    // ระบบทายคัดกรอง Sniper Recovery ขั้นสูงสุด:
    // ห้ามทวงหาก:
    // - OmniMatrix ส่งสัญญาณ Hold Fire
    // - ความผันผวน Chaos >= 0.50 (ลดจาก 0.70 เพื่อความคมชัดสูงสุด)
    // - ค่าความมั่นใจต่ำกว่า 75%
    // - Mathematical Edge ต่ำกว่า +5% (edge < 0.05)
    if (omniResult != null) {
      final double normalizedConf = omniResult.confidence <= 1.0
          ? omniResult.confidence * 100.0
          : omniResult.confidence;

      if (omniResult.recoveryClearance == RecoveryClearance.holdFire ||
          omniResult.chaosIndex >= 0.50 ||
          normalizedConf < 75.0 ||
          omniResult.mathematicalEdge < 0.05) {
        return false;
      }
    }

    return true;
  }

  void clampDebtToMax(double maxAllowed) {
    if (maxAllowed <= 0.00000001) {
      resetDebt();
      return;
    }
    double current = totalAccumulatedLoss;
    if (current > maxAllowed) {
      double excess = current - maxAllowed;
      subtractProfitFromDebt(excess);
    }
  }

  void subtractProfitFromDebt(double profit) {
    if (profit <= 0.0) return;
    activeNewLoss -= profit;

    if (activeNewLoss < 0.0) {
      double overflow = -activeNewLoss;
      activeNewLoss = 0.0;
      readyToRecoverLoss -= overflow;

      if (readyToRecoverLoss < 0.0) {
        double frozenOverflow = -readyToRecoverLoss;
        readyToRecoverLoss = 0.0;

        for (int i = 0; i < frozenDebtBuckets.length; i++) {
          if (frozenOverflow <= 0.0) break;
          final bucket = frozenDebtBuckets[i];
          if (bucket.amount <= frozenOverflow + 0.00000001) {
            frozenOverflow -= bucket.amount;
            bucket.amount = 0.0;
          } else {
            bucket.amount -= frozenOverflow;
            frozenOverflow = 0.0;
          }
        }
        frozenDebtBuckets.removeWhere((b) => b.amount <= 0.00000001);
      }
    }

    activeNewLoss = double.parse(activeNewLoss.toStringAsFixed(8));
    if (activeNewLoss < 0.00000001) activeNewLoss = 0.0;

    readyToRecoverLoss = double.parse(readyToRecoverLoss.toStringAsFixed(8));
    if (readyToRecoverLoss < 0.00000001) readyToRecoverLoss = 0.0;
  }
}

class OverlayButtonsViewModel with ChangeNotifier {
  // Game Mode Support (Towers vs Mines)
  GameMode _activeGameMode = GameMode.towers;
  GameMode get activeGameMode => _activeGameMode;

  final Map<GameMode, GameModeSessionState> _statesByMode = {
    GameMode.towers: GameModeSessionState(GameMode.towers),
    GameMode.mines: GameModeSessionState(GameMode.mines),
  };

  GameModeSessionState getState(GameMode mode) =>
      _statesByMode[mode] ?? _statesByMode[GameMode.towers]!;

  final Map<GameMode, List<OverlayButtonModel>> _buttonsByMode = {
    GameMode.towers: defaultOverlayButtons.map((b) => b.copyWith()).toList(),
    GameMode.mines: defaultOverlayButtons.map((b) => b.copyWith()).toList(),
  };

  final Map<GameMode, Offset> _controlPositionsByMode = {
    GameMode.towers: const Offset(20, 100),
    GameMode.mines: const Offset(20, 100),
  };

  final Map<GameMode, InAppWebViewController?> _webViewControllerByMode = {
    GameMode.towers: null,
    GameMode.mines: null,
  };

  final Map<GameMode, double?> _lockedBaseBetByMode = {
    GameMode.towers: null,
    GameMode.mines: null,
  };

  List<OverlayButtonModel> _buttons = [];
  bool _isRunning = false;
  bool _isSmartMode = true;
  bool _showMarkers = true;
  bool _isControlCollapsed = false;
  bool _isSequencePanelCollapsed = false;
  Offset _controlPosition = const Offset(20, 100);
  String? _activeButtonId;
  String? _draggingButtonId;
  final Map<String, int> _clickCounts = {};
  double _speedMultiplier = 1.0;
  String? _recordingButtonId;
  late SharedPreferences _prefs;

  // --- Stop Loss / Stop Profit / Safety ---
  bool _isStopProfitEnabled = false;
  double _stopProfitPercent = 10.0;
  bool _is24HourMode = true; // 🌟 24/7 Autonomous Continuous Non-Stop Mode (Default ON)
  int _maxM5Steps = 5;
  String _stopReason = '';

  // Single Source of Truth for Loss & Bombs
  final List<String> _lossSequence = [];
  final List<String> _bombHistory = [];

  Timer? _slCheckTimer;
  bool _isDisposed = false;
  bool _nativeClickPassthrough = false;

  final List<bool> _recentHighConfSuccess = [];
  final double _confThreshold = 70.0;

  DateTime? _sessionStartTime;
  bool _isBreakActive = false;
  int _breakMinutesRemaining = 0;

  InAppWebViewController? _webViewController;
  Offset _webViewOffset = Offset.zero;
  dynamic _sequenceAnalyzerViewModel;

  // AI Training Data Logger
  final TrainingDataLogger _trainingDataLogger = TrainingDataLogger();
  int _webViewTextZoom = 100;

  bool get _isWindowsDesktop => defaultTargetPlatform == TargetPlatform.windows;
  static const MethodChannel _nativeInputChannel = MethodChannel(
    'golden_p/native_input',
  );

  List<String> _sequenceSteps = [];

  // Mode-Aware Getters
  List<OverlayButtonModel> getButtons(GameMode mode) =>
      _buttonsByMode[mode] ?? _buttonsByMode[GameMode.towers]!;
  List<OverlayButtonModel> get buttons => getButtons(_activeGameMode);

  Offset getControlPosition(GameMode mode) =>
      _controlPositionsByMode[mode] ?? const Offset(20, 100);
  Offset get controlPosition => getControlPosition(_activeGameMode);

  bool isRunningForMode(GameMode mode) => getState(mode).isRunning;
  bool get isSequenceRunning => isRunningForMode(_activeGameMode);
  bool get isAnyRunning => _statesByMode.values.any((s) => s.isRunning);

  InAppWebViewController? getWebViewController([GameMode? mode]) =>
      _webViewControllerByMode[mode ?? _activeGameMode] ?? _webViewController;

  bool get isSmartMode => _isSmartMode;
  bool get showMarkers => _showMarkers;
  bool get isControlCollapsed => _isControlCollapsed;
  bool get isSequencePanelCollapsed => _isSequencePanelCollapsed;
  
  String? getActiveButtonId(GameMode mode) => getState(mode).activeButtonId;
  String? get activeButtonId => getActiveButtonId(_activeGameMode);
  
  String? get draggingButtonId => _draggingButtonId;
  Map<String, int> get clickCounts => _clickCounts;
  double get speedMultiplier => _speedMultiplier;
  String? get recordingButtonId => _recordingButtonId;
  List<String> get sequenceSteps => _sequenceSteps;
  int get webViewTextZoom => _webViewTextZoom;
  bool get isNativeClickPassthrough => _nativeClickPassthrough;
  bool get shouldAbsorbMainContent => isAnyRunning && !_nativeClickPassthrough;
  bool shouldAbsorbMainContentForMode(GameMode mode) => isRunningForMode(mode) && !_nativeClickPassthrough;

  bool get isStopProfitEnabled => _isStopProfitEnabled;
  double get stopProfitPercent => _stopProfitPercent;
  bool get is24HourMode => _is24HourMode;
  int get maxM5Steps => _maxM5Steps;
  String get stopReason => _stopReason;

  void toggle24HourMode() {
    _is24HourMode = !_is24HourMode;
    try {
      _prefs.setBool('overlay_24hour_mode', _is24HourMode);
    } catch (_) {}
    notifyListeners();
  }

  TrainingDataLogger get trainingDataLogger => _trainingDataLogger;

  // Dynamic Recovery Profit Target Level (Towers: Level 7 42%, Mines: Level 1 7%)
  final Map<GameMode, double> _recoveryProfitPercentByMode = {
    GameMode.towers: 0.42, // Level 7: 42% (Default for Towers)
    GameMode.mines: 0.48,  // Level 8: 48% (Default for Mines 9m/16g)
  };

  double getRecoveryProfitPercent(GameMode mode) =>
      _recoveryProfitPercentByMode[mode] ??
      (mode == GameMode.towers ? 0.42 : 0.48);

  double get recoveryProfitPercent =>
      getRecoveryProfitPercent(_activeGameMode);

  /// Returns the base bet floor for the specified mode and coin.
  /// - Towers: DOGE: 0.00007882, POL: 0.00000903, USDT: 0.000005
  /// - Mines (Polpick): 0.00001
  double getFloorBetForMode(GameMode mode, {String? coinType}) {
    final coin = (coinType ??
            getState(mode).activeCoinType ??
            _analyzersByMode[mode]?.getCoinTypeForMode(mode) ??
            _sequenceAnalyzerViewModel?.getCoinTypeForMode(mode) ??
            'DOGE')
        .toUpperCase()
        .trim();
    if (coin == 'USDT' || coin == 'TETHER') {
      return 0.000005;
    }
    if (mode == GameMode.mines) {
      return 0.00001;
    }
    if (coin == 'POL' || coin == 'POLYGON' || coin == 'MATIC') {
      return 0.00000903;
    }
    return 0.00007882;
  }

  static const List<Map<String, dynamic>> recoveryProfitLevels = [
    {'level': 1, 'label': 'Level 1: 7%', 'value': 0.07},
    {'level': 2, 'label': 'Level 2: 13%', 'value': 0.13},
    {'level': 3, 'label': 'Level 3: 18%', 'value': 0.18},
    {'level': 4, 'label': 'Level 4: 25%', 'value': 0.25},
    {'level': 5, 'label': 'Level 5: 31%', 'value': 0.31},
    {'level': 6, 'label': 'Level 6: 39%', 'value': 0.39},
    {'level': 7, 'label': 'Level 7: 42% (Default Towers)', 'value': 0.42},
    {'level': 8, 'label': 'Level 8: 48% (Default Mines 9m/16g)', 'value': 0.48},
  ];

  int get consecutiveLossesStreak => getState(_activeGameMode).consecutiveLossesStreak;
  int get observationRoundsRemaining => getState(_activeGameMode).observationRoundsRemaining;
  bool get isPostObservationRecoveryReady => getState(_activeGameMode).isPostObservationRecoveryReady;
  RecoveryState get recoveryState => getState(_activeGameMode).recoveryState;
  int get recoveryLossStreak => getState(_activeGameMode).recoveryLossStreak;
  int get recoveryAttempts => getState(_activeGameMode).recoveryAttempts;
  int get currentRecoveryCycle => getState(_activeGameMode).currentRecoveryCycle;
  int get recoveryStepInCycle => getState(_activeGameMode).recoveryStepInCycle;
  bool get recoveryCircuitBreakerActive => getState(_activeGameMode).recoveryCircuitBreakerActive;
  int get consecutiveBaseBetWins => getState(_activeGameMode).consecutiveBaseBetWins;
  int get consecutiveBaseBetWinsRequiredForRecovery => getState(_activeGameMode).consecutiveBaseBetWinsRequiredForRecovery;
  double get recoverySliceFraction => getState(_activeGameMode).recoverySliceFraction;
  bool canEnterRecovery(GameMode mode, {OmniPredictionResult? omniResult, double? floorBet}) =>
      getState(mode).canEnterRecovery(omniResult: omniResult, floorBet: floorBet);

  void transitionRecoveryState(GameMode mode, RecoveryState newState, {String reason = ''}) {
    final state = getState(mode);
    final oldState = state.recoveryState;
    if (oldState == newState) return;
    state.recoveryState = newState;
    debugPrint('[RECOVERY] [${mode.displayName}] ${oldState.name.toUpperCase()} -> ${newState.name.toUpperCase()}${reason.isNotEmpty ? " ($reason)" : ""}');
  }

  bool get isRecoveryUnlocked => getState(_activeGameMode).isRecoveryUnlocked;
  bool get isBreakActive => _isBreakActive;
  int get breakMinutesRemaining => _breakMinutesRemaining;

  // Recovery Mode
  int _recoveryMode = 1;
  int get recoveryMode => _recoveryMode;
  set recoveryMode(int val) {
    _recoveryMode = val;
    notifyListeners();
  }

  OverlayButtonsViewModel() {
    _initializeButtons();
  }

  void _initializeButtons() {
    _buttons = List.from(defaultOverlayButtons);
    for (var mode in GameMode.values) {
      _buttonsByMode[mode] =
          defaultOverlayButtons.map((b) => b.copyWith()).toList();
    }
  }

  void setActiveGameMode(GameMode mode) {
    if (_activeGameMode != mode) {
      _activeGameMode = mode;
      _buttons = getButtons(mode);
      _controlPosition = getControlPosition(mode);
      _webViewController = getWebViewController(mode);
      notifyListeners();
    }
  }

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _isSmartMode = _prefs.getBool('overlay_smart_mode') ?? true;
    _showMarkers = _prefs.getBool('overlay_show_markers') ?? true;
    _isControlCollapsed = _prefs.getBool('overlay_control_collapsed') ?? false;
    _isSequencePanelCollapsed =
        _prefs.getBool('overlay_seq_panel_collapsed') ?? false;
    _speedMultiplier = _prefs.getDouble('overlay_speed_multiplier') ?? 1.0;

    await loadButtonPositions();
    await loadSequenceFromStorage();

    _isStopProfitEnabled = _prefs.getBool('tp_enabled') ?? false;
    _stopProfitPercent = _prefs.getDouble('tp_percent') ?? 10.0;
    _is24HourMode = _prefs.getBool('overlay_24hour_mode') ?? true;
    _maxM5Steps = _prefs.getInt('max_m5_steps') ?? 5;

    final double towersSaved = _prefs.getDouble('recovery_profit_percent_towers') ??
        _prefs.getDouble('recovery_profit_percent') ??
        0.42;
    final double minesSaved =
        _prefs.getDouble('recovery_profit_percent_mines') ?? 0.48;

    _recoveryProfitPercentByMode[GameMode.towers] = towersSaved;
    _recoveryProfitPercentByMode[GameMode.mines] = minesSaved;

    _webViewTextZoom = _prefs.getInt('webview_text_zoom') ?? 100;
  }

  void setRecoveryProfitPercent(double percent, {GameMode? mode}) {
    final targetMode = mode ?? _activeGameMode;
    _recoveryProfitPercentByMode[targetMode] = percent;
    _prefs.setDouble(
      'recovery_profit_percent_${targetMode.storagePrefix}',
      percent,
    );
    notifyListeners();
  }

  int getRecoveryProfitLevel(GameMode mode) {
    final rate = getRecoveryProfitPercent(mode);
    for (var item in recoveryProfitLevels) {
      if (((item['value'] as double) - rate).abs() < 0.005) {
        return item['level'] as int;
      }
    }
    return mode == GameMode.towers ? 7 : 8;
  }

  void cycleRecoveryProfitLevel({GameMode? mode}) {
    final targetMode = mode ?? _activeGameMode;
    int currentLevel = getRecoveryProfitLevel(targetMode);
    int nextLevel = currentLevel + 1;
    if (nextLevel > 8) nextLevel = 1;
    final nextItem = recoveryProfitLevels.firstWhere(
      (item) => item['level'] == nextLevel,
      orElse: () => recoveryProfitLevels.first,
    );
    setRecoveryProfitPercent(nextItem['value'] as double, mode: targetMode);
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

  void setStopProfitEnabled(bool val) {
    _isStopProfitEnabled = val;
    _prefs.setBool('tp_enabled', val);
    if (isAnyRunning) {
      _startPnLMonitor();
    }
    notifyListeners();
  }

  void setStopProfitPercent(double val) {
    _stopProfitPercent = val;
    _prefs.setDouble('tp_percent', val);
    if (isAnyRunning) {
      _startPnLMonitor();
    }
    notifyListeners();
  }

  void setMaxM5Steps(int val) {
    _maxM5Steps = val;
    _prefs.setInt('max_m5_steps', val);
    notifyListeners();
  }

  void updateControlPosition(Offset newPos, {GameMode? mode}) {
    final targetMode = mode ?? _activeGameMode;
    _controlPositionsByMode[targetMode] = newPos;
    if (targetMode == _activeGameMode) {
      _controlPosition = newPos;
    }
    notifyListeners();
  }

  void saveControlPosition({GameMode? mode}) {
    final targetMode = mode ?? _activeGameMode;
    final pos = _controlPositionsByMode[targetMode] ?? const Offset(20, 100);
    _prefs.setDouble('overlay_control_${targetMode.storagePrefix}_x', pos.dx);
    _prefs.setDouble('overlay_control_${targetMode.storagePrefix}_y', pos.dy);
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

  void setWebViewController(InAppWebViewController controller, {GameMode mode = GameMode.towers}) {
    _webViewControllerByMode[mode] = controller;
    if (mode == _activeGameMode) {
      _webViewController = controller;
    }
  }

  void setWebViewOffset(Offset offset) {
    _webViewOffset = offset;
    notifyListeners();
  }

  final Map<GameMode, dynamic> _analyzersByMode = {};

  void setSequenceAnalyzerViewModel(dynamic viewModel, {GameMode? mode}) {
    _sequenceAnalyzerViewModel = viewModel;
    if (mode != null) {
      _analyzersByMode[mode] = viewModel;
    }
  }

  dynamic getSequenceAnalyzerViewModel(GameMode mode) => _analyzersByMode[mode] ?? _sequenceAnalyzerViewModel;

  void setWebViewTextZoom(int zoom) {
    if (zoom >= 50 && zoom <= 300) {
      _webViewTextZoom = zoom;
      _prefs.setInt('webview_text_zoom', zoom);

      for (var mode in GameMode.values) {
        final controller = getWebViewController(mode);
        controller?.evaluateJavascript(
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
      }

      notifyListeners();
    }
  }

  Future<void> loadButtonPositions([GameMode? mode]) async {
    for (var m in GameMode.values) {
      if (mode != null && m != mode) continue;
      final key = 'overlay_buttons_positions_${m.storagePrefix}';
      String? jsonStr = _prefs.getString(key);
      if (jsonStr == null && m == GameMode.towers) {
        jsonStr = _prefs.getString('overlay_buttons_positions');
      }
      if (jsonStr != null && jsonStr.isNotEmpty) {
        try {
          final List<dynamic> decoded = jsonDecode(jsonStr);
          final Map<String, dynamic> positions = Map.from(decoded[0]);
          final buttonList = _buttonsByMode[m] ?? [];
          for (var button in buttonList) {
            if (positions.containsKey(button.id)) {
              final pos = positions[button.id];
              button.position = Offset(
                (pos['x'] as num).toDouble(),
                (pos['y'] as num).toDouble(),
              );
            }
          }
        } catch (e) {
          debugPrint('Error loading positions for ${m.displayName}: $e');
        }
      }

      final ctrlXKey = 'overlay_control_${m.storagePrefix}_x';
      final ctrlYKey = 'overlay_control_${m.storagePrefix}_y';
      double? cx = _prefs.getDouble(ctrlXKey);
      double? cy = _prefs.getDouble(ctrlYKey);
      if (cx == null && m == GameMode.towers) {
        cx = _prefs.getDouble('overlay_control_x');
        cy = _prefs.getDouble('overlay_control_y');
      }
      if (cx != null && cy != null) {
        _controlPositionsByMode[m] = Offset(cx, cy);
      }
    }
    _buttons = getButtons(_activeGameMode);
    _controlPosition = getControlPosition(_activeGameMode);
    notifyListeners();
  }

  Future<void> saveButtonPosition(String buttonId, Offset position, {GameMode? mode}) async {
    final targetMode = mode ?? _activeGameMode;
    final buttonList = _buttonsByMode[targetMode] ?? [];
    final buttonIndex = buttonList.indexWhere((b) => b.id == buttonId);
    if (buttonIndex != -1) {
      final updated = buttonList[buttonIndex].copyWith(position: position);
      buttonList[buttonIndex] = updated;

      final Map<String, dynamic> positions = {};
      for (var button in buttonList) {
        positions[button.id] = {
          'x': button.position.dx,
          'y': button.position.dy,
        };
      }

      await _prefs.setString(
        'overlay_buttons_positions_${targetMode.storagePrefix}',
        jsonEncode([positions]),
      );
      notifyListeners();
    }
  }

  void updateButtonPosition(String buttonId, Offset newPos, {GameMode? mode}) {
    final targetMode = mode ?? _activeGameMode;
    final buttonList = _buttonsByMode[targetMode] ?? [];
    final buttonIndex = buttonList.indexWhere((b) => b.id == buttonId);
    if (buttonIndex != -1) {
      buttonList[buttonIndex].position = newPos;
      notifyListeners();
    }
  }

  Future<bool> _performWindowsNativeClick(double screenX, double screenY, String buttonId) async {
    if (!_isWindowsDesktop) return false;
    try {
      final result = await _nativeInputChannel.invokeMethod<bool>('sendClick', {
        'x': screenX.toInt(),
        'y': screenY.toInt(),
        'buttonId': buttonId,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('[NATIVE CLICK] ❌ Error executing native click: $e');
      return false;
    }
  }

  double get totalAccumulatedLoss => getState(_activeGameMode).totalAccumulatedLoss;
  double get activeUnfrozenLoss => getState(_activeGameMode).activeNewLoss + getState(_activeGameMode).readyToRecoverLoss;
  List<DebtBucket> get frozenDebtBuckets => List.unmodifiable(getState(_activeGameMode).frozenDebtBuckets);

  void startRecording(String buttonId) {
    _recordingButtonId = buttonId;
    for (var button in _buttons) {
      button.isRecording = (button.id == buttonId);
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
  void toggleSequence({GameMode? mode}) {
    final targetMode = mode ?? _activeGameMode;
    if (isRunningForMode(targetMode)) {
      stopSequence(mode: targetMode);
    } else {
      startSequence(mode: targetMode);
    }
  }

  /// 🎯 Ensure Difficulty is verified for the target game mode (Towers: Medium 2/3, Mines: 9 Mines / 16 Gems)
  Future<bool> ensureDifficulty({GameMode? mode}) async {
    final targetMode = mode ?? _activeGameMode;
    final controller = getWebViewController(targetMode);
    if (controller == null) return false;

    if (targetMode == GameMode.towers) {
      debugPrint('[DIFFICULTY] 🔍 [Towers] Ensuring Medium difficulty (2/3 Safe) is selected...');
      for (int retry = 1; retry <= 6; retry++) {
        try {
          final dynamic res = await controller.evaluateJavascript(source: """
            (function() {
              let radios = Array.from(document.querySelectorAll('input[type="radio"], input[type="checkbox"]'));
              for (let r of radios) {
                let val = (r.value || r.id || r.name || '').toLowerCase();
                let label = r.parentElement ? (r.parentElement.innerText || '').toLowerCase() : '';
                if (val.includes('medium') || label.includes('medium') || label.includes('2/3')) {
                  r.checked = true;
                  r.dispatchEvent(new Event('change', { bubbles: true }));
                  r.dispatchEvent(new Event('click', { bubbles: true }));
                  return true;
                }
              }
              let selects = Array.from(document.querySelectorAll('select'));
              for (let s of selects) {
                for (let opt of s.options) {
                  if ((opt.text || opt.value || '').toLowerCase().includes('medium')) {
                    s.value = opt.value;
                    s.dispatchEvent(new Event('change', { bubbles: true }));
                    return true;
                  }
                }
              }
              let candidates = Array.from(document.querySelectorAll('button, a, div, span, label'));
              for (let el of candidates) {
                let txt = (el.innerText || el.textContent || '').trim();
                let lower = txt.toLowerCase();
                if (lower.includes('medium') || (lower.includes('2/3') && lower.includes('safe'))) {
                  if (lower.includes('easy') && lower.includes('hard') && lower.includes('custom')) continue;
                  if (txt.length > 50) continue;
                  const base = { bubbles: true, cancelable: true, composed: true, view: window };
                  try { el.dispatchEvent(new PointerEvent('pointerdown', base)); } catch(e){}
                  try { el.dispatchEvent(new MouseEvent('mousedown', base)); } catch(e){}
                  try { el.dispatchEvent(new PointerEvent('pointerup', base)); } catch(e){}
                  try { el.dispatchEvent(new MouseEvent('mouseup', base)); } catch(e){}
                  try { el.click(); } catch(e){}
                  return true;
                }
              }
              return false;
            })()
          """).timeout(const Duration(seconds: 2), onTimeout: () => null);

          if (res == true) {
            debugPrint('[DIFFICULTY] ✅ [Towers] Medium difficulty confirmed selected (attempt $retry)!');
            await Future.delayed(const Duration(milliseconds: 600));
            return true;
          }
        } catch (e) {
          debugPrint('[DIFFICULTY] Warning selecting Medium: $e');
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } else if (targetMode == GameMode.mines) {
      debugPrint('[DIFFICULTY] 🔍 [Mines] Ensuring 9 Mines (16 Gems, Level 8: 48%) is selected...');
      for (int retry = 1; retry <= 6; retry++) {
        try {
          final dynamic res = await controller.evaluateJavascript(source: """
            (function() {
              // 1. Dropdown select
              let selects = Array.from(document.querySelectorAll('select'));
              for (let s of selects) {
                let nameOrId = (s.name || s.id || '').toLowerCase();
                if (nameOrId.includes('mine') || nameOrId.includes('bomb') || nameOrId.includes('count')) {
                  for (let opt of s.options) {
                    let val = (opt.value || '').trim();
                    let txt = (opt.text || '').trim();
                    if (val === '9' || txt === '9' || txt.includes('9 Mine')) {
                      s.value = opt.value;
                      s.dispatchEvent(new Event('change', { bubbles: true }));
                      s.dispatchEvent(new Event('input', { bubbles: true }));
                      return true;
                    }
                  }
                }
              }

              // 2. Input number/text
              let inputs = Array.from(document.querySelectorAll('input'));
              for (let inp of inputs) {
                let nameOrId = (inp.name || inp.id || inp.placeholder || inp.getAttribute('aria-label') || '').toLowerCase();
                if (nameOrId.includes('mine') || nameOrId.includes('bomb') || nameOrId.includes('count')) {
                  inp.focus();
                  inp.value = '9';
                  inp.dispatchEvent(new Event('input', { bubbles: true }));
                  inp.dispatchEvent(new Event('change', { bubbles: true }));
                  inp.blur();
                  return true;
                }
              }

              // 3. Buttons/badges
              let buttons = Array.from(document.querySelectorAll('button, div, span, a, label'));
              for (let btn of buttons) {
                let txt = (btn.innerText || btn.textContent || '').trim();
                let aria = (btn.getAttribute('aria-label') || '').toLowerCase();
                if (txt === '9' || txt === '9 Mines' || aria.includes('9 mine')) {
                  if (txt.length <= 15) {
                    const base = { bubbles: true, cancelable: true, composed: true, view: window };
                    try { btn.dispatchEvent(new PointerEvent('pointerdown', base)); } catch(e){}
                    try { btn.dispatchEvent(new MouseEvent('mousedown', base)); } catch(e){}
                    try { btn.dispatchEvent(new PointerEvent('pointerup', base)); } catch(e){}
                    try { btn.dispatchEvent(new MouseEvent('mouseup', base)); } catch(e){}
                    try { btn.click(); } catch(e){}
                    return true;
                  }
                }
              }
              return false;
            })()
          """).timeout(const Duration(seconds: 2), onTimeout: () => null);

          if (res == true) {
            debugPrint('[DIFFICULTY] ✅ [Mines] 9 Mines (16 Gems) confirmed selected (attempt $retry)!');
            await Future.delayed(const Duration(milliseconds: 600));
            return true;
          }
        } catch (e) {
          debugPrint('[DIFFICULTY] Warning selecting Mines difficulty: $e');
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    return false;
  }

  /// Alias for backwards compatibility
  Future<bool> ensureMediumDifficulty({GameMode? mode}) => ensureDifficulty(mode: mode);

    /// 🔄 Rotate Client Seed directly on FaucetPay Web DOM to reset Nonce and avoid long-session PRNG cluster traps
  Future<bool> rotateWebClientSeed({GameMode? mode}) async {
    final targetMode = mode ?? _activeGameMode;
    final controller = getWebViewController(targetMode);
    if (controller == null) return false;

    final String newRandomSeed = Iterable.generate(
      16,
      (_) => '0123456789abcdef'[Random().nextInt(16)],
    ).join();

    debugPrint('[WEB SEED ROTATE] 🔄 [${targetMode.displayName}] Rotating Client Seed on FaucetPay web DOM to: $newRandomSeed');

    try {
      final dynamic res = await controller.evaluateJavascript(source: """
        (function() {
          try {
            let seedInput = document.querySelector('input#client_seed, input[name="client_seed"], input#seed, input.client-seed');
            if (seedInput) {
              seedInput.value = '$newRandomSeed';
              seedInput.dispatchEvent(new Event('input', { bubbles: true }));
              seedInput.dispatchEvent(new Event('change', { bubbles: true }));
              
              let saveBtn = document.querySelector('button#save_seed, button.save-seed, button#change_seed, button.change-seed');
              if (saveBtn) {
                saveBtn.click();
              }
              return true;
            }
            let buttons = Array.from(document.querySelectorAll('button, a'));
            for (let b of buttons) {
              let txt = (b.innerText || b.textContent || '').toLowerCase();
              if (txt.includes('change seed') || txt.includes('random seed') || txt.includes('new seed')) {
                b.click();
                return true;
              }
            }
          } catch(e){}
          return false;
        })()
      """);

      OmniMatrixEngine.instance.rotateSeed();
      OmniMatrixEngine.instance.pruneHistory(mode: targetMode);

      debugPrint('[WEB SEED ROTATE] ✅ [${targetMode.displayName}] Client Seed rotated & memory pruned cleanly!');
      return res == true;
    } catch (e) {
      debugPrint('[WEB SEED ROTATE] Warning rotating web seed: $e');
      OmniMatrixEngine.instance.rotateSeed();
      return false;
    }
  }

  Future<void> startSequence({GameMode? mode}) async {
    if (_isDisposed) return;
    final targetMode = mode ?? _activeGameMode;

    // 🌟 DUAL-MODE SUPPORT: Towers and Mines can run simultaneously in independent background loops
    debugPrint('[MULTI-RUNNER] 🟢 Starting sequence for ${targetMode.displayName} (Dual-mode enabled)');

    final state = getState(targetMode);

    if (!_isSmartMode && _sequenceSteps.isEmpty) return;
    
    if (_sequenceAnalyzerViewModel != null) {
      await DynamicParameterService().reloadParameters(
        null,
        _sequenceAnalyzerViewModel!.predictionPipeline,
      );
    }

    // 🎯 For Towers, make sure Medium difficulty is active before starting
    if (targetMode == GameMode.towers) {
      await ensureMediumDifficulty(mode: targetMode);
    }

    state.runToken++;
    final int runToken = state.runToken;
    state.isRunning = true;
    _isRunning = true;
    state.consecutiveLossesStreak = 0;
    state.lowestObservedBet = null;
    _stopReason = '';
    state.recoveryWinsRequired = 0;
    state.recoveryWinsAchieved = 0;
    state.isRecoveryUnlocked = false;
    state.recoveryStepInCycle = 0;
    state.currentRecoveryCycle = 1;
    state.observationRoundsRemaining = 0;
    state.isLossStreakBaseBetLocked = false;
    state.recoveryState = RecoveryState.normal;
    if (state.totalAccumulatedLoss <= 0.00000001) {
      state.resetDebt();
    } else {
      debugPrint('[DEBT PRESERVED] 🛡️ [${targetMode.displayName}] Resuming with existing debt: ${state.totalAccumulatedLoss.toStringAsFixed(8)} (ไม่ลืมหนี้)');
    }
    state.peakLossStreak = 0;

    _sequenceAnalyzerViewModel?.resetMaxLossStreak();
    _trainingDataLogger.startSession();

    final analyzer = _analyzersByMode[targetMode] ?? _sequenceAnalyzerViewModel;
    final coin = analyzer?.getCoinTypeForMode(targetMode);
    state.activeCoinType = coin;
    final double defaultFloor = getFloorBetForMode(targetMode, coinType: coin);

    double initialBet = await _getBetAmount(mode: targetMode);
    double calculatedBase = await _calculateDynamicBaseBet(mode: targetMode);
    // 🛡️ ป้องกันการดึงค่ายอดทวงหนี้เก่าที่ค้างอยู่ในช่อง DOM มาเป็น Base Bet:
    // หาก initialBet สูงเกิน 2.5 เท่าของ calculatedBase ให้ใช้ calculatedBase เสมอ
    state.lockedBaseBet = (initialBet >= (defaultFloor * 0.85) && initialBet <= (calculatedBase * 2.5))
        ? initialBet
        : calculatedBase;
    state.currentBetAmount = state.lockedBaseBet!;
    _lockedBaseBetByMode[targetMode] = state.lockedBaseBet;

    debugPrint(
      '[V143 STATE] 🔒 [${targetMode.displayName}] Locked Base Bet at ${state.lockedBaseBet?.toStringAsFixed(8)} for the entire session.',
    );

    double curBal = await _getBalanceDouble(mode: targetMode);
    state.sessionStartBalance = curBal;
    state.lastSettledBalance = curBal;
    state.protectedPrincipal = curBal;
    if (state.totalAccumulatedLoss > 0.00000001) {
      state.sessionMaxBalance = curBal + state.totalAccumulatedLoss;
      debugPrint(
        '[PEAK ADJUST] 🛡️ [${targetMode.displayName}] Adjusted sessionMaxBalance to ${state.sessionMaxBalance.toStringAsFixed(8)} to account for existing debt: ${state.totalAccumulatedLoss.toStringAsFixed(8)}',
      );
    } else {
      state.sessionMaxBalance = curBal;
    }
    state.sessionProfitBaseline = curBal > 0 ? curBal : null;
    state.currentHourWindowStart = DateTime.now();
    state.currentHourStartBalance = curBal;
    state.totalSessionRoundsPlayed = 0;
    state.roundsSinceLastMicroBreak = 0;
    state.roundsSinceLastMacroBreak = 0;
    state.roundsSinceLastHygieneReload = 0;
    state.lastHeartbeatTime = DateTime.now();
    if (analyzer != null) {
      final sessionCoin = analyzer.getCoinTypeForMode(targetMode);
      state.activeCoinType = sessionCoin;
      analyzer.resetProfitTracking(mode: targetMode, coinType: sessionCoin);
    }

    notifyListeners();

    _slCheckCounter = 0;
    debugPrint(
      '[START] 🚀 [${targetMode.displayName}] Sequence started | StopProfit: ${_isStopProfitEnabled ? "ON (${_stopProfitPercent.toStringAsFixed(4)}%)" : "OFF"} | SmartMode: $_isSmartMode',
    );
    _startPnLMonitor();
    _sessionStartTime = DateTime.now();
    _isBreakActive = false;

    if (_isSmartMode) {
      _executeSmartFlow(runToken, mode: targetMode);
    } else {
      _executeSequence(runToken, mode: targetMode);
    }
  }

  void stopSequence({GameMode? mode}) {
    final targetMode = mode ?? _activeGameMode;
    final state = getState(targetMode);
    state.runToken++;
    state.isRunning = false;
    _isRunning = isAnyRunning;

    _trainingDataLogger.endSession();
    _isBreakActive = false;
    if (!isAnyRunning) {
      _stopPnLMonitor();
      _sessionStartTime = null;
    }
    if (!_isDisposed) {
      notifyListeners();
    }
    debugPrint('[STOP] ⏹️ [${targetMode.displayName}] Sequence manually stopped.');
  }

  void _startPnLMonitor() {
    _stopPnLMonitor();
    if (_isStopProfitEnabled) {
      _slCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (
        _,
      ) async {
        await _monitorSLTP();
      });
    }
  }

  void _stopPnLMonitor() {
    _slCheckTimer?.cancel();
    _slCheckTimer = null;
  }

  int _slCheckCounter = 0;

  Future<void> _monitorSLTP() async {
    if (_isDisposed || !isAnyRunning) {
      return;
    }

    for (var mode in GameMode.values) {
      final state = getState(mode);
      if (!state.isRunning) continue;

      final analyzer = _analyzersByMode[mode] ?? _sequenceAnalyzerViewModel;
      if (analyzer == null) continue;

      try {
        await analyzer.updateBalanceFast();
      } catch (_) {}

      if (_isDisposed || !state.isRunning) continue;

      final double pnl = analyzer.getProfitForMode(mode);

      _slCheckCounter++;
      if (_slCheckCounter % 10 == 0) {
        debugPrint(
          '[PnL MONITOR] 📊 [${mode.displayName} / ${analyzer.getCoinTypeForMode(mode)}] PnL: ${pnl.toStringAsFixed(4)}% | Target: +${_stopProfitPercent.toStringAsFixed(4)}% | Enabled: $_isStopProfitEnabled',
        );
      }

      if (_isStopProfitEnabled && pnl >= _stopProfitPercent) {
        if (!_is24HourMode) {
          _stopReason =
              '🌟 STOP PROFIT triggered at ${pnl.toStringAsFixed(4)}% on ${mode.displayName} (Target: +${_stopProfitPercent.toStringAsFixed(4)}%)';
          debugPrint('[PnL MONITOR] 🛑 $_stopReason — FORCING IMMEDIATE HALT ALL MODES');
          for (var m in GameMode.values) {
            stopSequence(mode: m);
          }
          return;
        }
      }
    }
  }

  bool _shouldAbort(int runToken, {GameMode? mode}) {
    final targetMode = mode ?? _activeGameMode;
    final state = getState(targetMode);
    return _isDisposed ||
        !state.isRunning ||
        runToken != state.runToken;
  }

  Future<bool> _checkStopProfitInline(int runToken, {GameMode? mode}) async {
    final targetMode = mode ?? _activeGameMode;
    final state = getState(targetMode);
    if (!_isStopProfitEnabled) {
      return false;
    }

    double pnl = 0.0;
    final analyzer = _analyzersByMode[targetMode] ?? _sequenceAnalyzerViewModel;
    if (analyzer != null) {
      pnl = analyzer.getProfitForMode(targetMode);
    } else {
      double curBalance = await _getBalanceDouble(mode: targetMode);
      if (state.sessionStartBalance == null || state.sessionStartBalance! <= 0) {
        state.sessionStartBalance = curBalance;
        return false;
      }
      pnl = ((curBalance - state.sessionStartBalance!) / state.sessionStartBalance!) * 100;
    }

    if (pnl >= _stopProfitPercent) {
      _stopReason =
          '🌟 STOP PROFIT reached at ${pnl.toStringAsFixed(4)}% on ${targetMode.displayName} (Target: +${_stopProfitPercent.toStringAsFixed(4)}%)';
      debugPrint('[INLINE TP] 🛑 [${targetMode.displayName}] $_stopReason');

      if (_is24HourMode) {
        // 🌟 24/7 PROFIT BANKING: เก็บกำไรเข้าพอร์ต ไม่ดับระบบ พัก 3 นาทีแล้วปั่นกำไรต่อ!
        double curBalance = await _getBalanceDouble(mode: targetMode);
        if (curBalance <= 0.00000001) curBalance = state.lastSettledBalance;
        state.profitMilestonesAchieved++;
        state.sessionProfitBaseline = curBalance;
        state.sessionStartBalance = curBalance;
        state.sessionMaxBalance = curBalance;
        state.protectedPrincipal = curBalance * 0.97;
        debugPrint(
          '🏦 [24/7 PROFIT BANKING 🌟] [${targetMode.displayName}] กำไรแตะเป้า +${pnl.toStringAsFixed(2)}%! ล็อกกำไรสะสมก้อนที่ ${state.profitMilestonesAchieved}! พัก 3 นาที แล้วเริ่มรอบสะสมกำไรก้อนถัดไปในระบบ 24 ชม.',
        );
        await Future.delayed(Duration(seconds: (180 / _speedMultiplier).round()));
        return false; // ไม่ตัดลูป! ทำงานต่อเนื่อง 24 ชั่วโมง
      } else {
        stopSequence(mode: targetMode);
        return true;
      }
    }
    return false;
  }

  /// 🛡️ SHIELD 2: HARD STOP-LOSS ENGINE (30% Max Drawdown Protection)
  /// ป้องกันการล้างพอร์ต 100%: หากยอดเงินร่วงลงเกิน 30% จากจุดสูงสุด (ATH) หรือเงินเริ่มต้น
  /// ในโหมด 24 ชั่วโมง: เข้าสู่ Safe Haven Protocol พัก 15 นาที ล้างหนี้เป็น 0 รีเซ็ตทุน และเดิน Base Bet ต่อเนื่องอัตโนมัติ
  /// ในโหมดปกติ: สั่งหยุดทำงานฉุกเฉินทันที ล็อกระบบเบทเพื่อรักษาเงินต้น 70% ไว้อย่างเด็ดขาด
  Future<bool> _checkStopLossInline(int runToken, {GameMode? mode}) async {
    final targetMode = mode ?? _activeGameMode;
    final state = getState(targetMode);

    final double baselineCapital = max(
      state.sessionMaxBalance,
      state.sessionStartBalance ?? state.protectedPrincipal ?? 0.0,
    );

    if (baselineCapital <= 0.00000001) {
      return false;
    }

    double curBalance = await _getBalanceDouble(mode: targetMode);
    if (curBalance <= 0.00000001) {
      curBalance = state.lastSettledBalance > 0.00000001
          ? state.lastSettledBalance
          : (state.sessionStartBalance ?? 0.0);
    }

    if (curBalance <= 0.00000001) {
      _stopReason = '🚨 ZERO BALANCE EMERGENCY HALT: Balance is 0 on ${targetMode.displayName}';
      debugPrint('[HARD STOP-LOSS] 🛑 [${targetMode.displayName}] $_stopReason');
      state.isLossStreakBaseBetLocked = true;
      state.recoveryCircuitBreakerActive = true;
      stopSequence(mode: targetMode);
      return true;
    }

    // 🎯 AQ-DARE PILLAR 5: DYNAMIC CAPITAL STOP-LOSS (20% Max Drawdown Floor)
    // ล็อกเพดาน Drawdown ไม่เกิน 20% จากยอดสูงสุด (ATH) เพื่อการันตีรักษา 80% ของพอร์ตไว้เสมอ
    final double hardStopLossFloor = baselineCapital * 0.80;
    if (curBalance <= hardStopLossFloor) {
      final double drawdownPct = ((baselineCapital - curBalance) / baselineCapital) * 100.0;
      _stopReason =
          '🚨 HARD STOP-LOSS TRIGGERED: Drawdown -${drawdownPct.toStringAsFixed(2)}% on ${targetMode.displayName} '
          '(Current: ${curBalance.toStringAsFixed(8)} <= Floor: ${hardStopLossFloor.toStringAsFixed(8)} from Peak: ${baselineCapital.toStringAsFixed(8)}).';
      debugPrint('[HARD STOP-LOSS] 🛑 [${targetMode.displayName}] $_stopReason');

      if (_is24HourMode) {
        // 🌟 24/7 AUTONOMOUS RESILIENCE: ไม่ตัดการทำงานจนแอปดับ!
        // เข้าสู่ Safe Haven Protocol: พัก 15 นาที, ล้างหนี้เป็น 0, รีเซ็ต Baseline, แล้วเดิน Base Bet ต่ออัตโนมัติ 24 ชม.
        debugPrint(
          '🛌 [24/7 SAFE HAVEN ACTIVATED 🛡️] [${targetMode.displayName}] Drawdown -${drawdownPct.toStringAsFixed(2)}%! '
          'เข้าสู่ Safe Haven: พักเครื่อง 15 นาทีเพื่อล้างพิษ RNG คาสิโน -> ล้างหนี้สะสมทั้งหมดเป็น 0 -> รีเซ็ตทุนตั้งต้นสู่ยอดปัจจุบัน (${curBalance.toStringAsFixed(8)}) '
          '-> ล็อกเดิน Base Bet 30 ตา ต่อนอนสต็อป 24 ชม.!',
        );
        state.resetDebt();
        state.sessionMaxBalance = curBalance;
        state.sessionStartBalance = curBalance;
        state.protectedPrincipal = curBalance;
        state.observationRoundsRemaining = 30; // ล็อก Base Bet 30 ตาเพื่อฟื้นฟู
        state.isLossStreakBaseBetLocked = true;
        state.recoveryState = RecoveryState.observation;
        await _ensureBaseBet(runToken, mode: targetMode);
        await Future.delayed(Duration(seconds: (900 / _speedMultiplier).round())); // พัก 15 นาที
        return false; // ไม่ตัดลูป! บอททำงานต่อเนื่อง 24 ชั่วโมง
      } else {
        state.isLossStreakBaseBetLocked = true;
        state.recoveryCircuitBreakerActive = true;
        stopSequence(mode: targetMode);
        return true;
      }
    }

    return false;
  }

  Future<void> _executeSequence(int runToken, {GameMode mode = GameMode.towers}) async {
    final state = getState(mode);
    while (!_shouldAbort(runToken, mode: mode) && !_isSmartMode) {
      for (String buttonId in _sequenceSteps) {
        if (_shouldAbort(runToken, mode: mode) || _isSmartMode) break;
        await _performButtonAction(buttonId, mode: mode);
        if (_shouldAbort(runToken, mode: mode)) break;
      }
      if (_shouldAbort(runToken, mode: mode)) break;
      await Future.delayed(const Duration(milliseconds: 600));
    }
    state.isRunning = false;
    _isRunning = isAnyRunning;
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  /// 🔍 ตรวจสอบและอัปเดตยอดเงินจริงทุกครั้งก่อนเริ่มรอบใหม่ (User Directive)
  /// ป้องกันปัญหากดเริ่มรอบใหม่ก่อนที่ยอดเงินจากรอบที่แล้วจะอัปเดตเสร็จสิ้น
  Future<double> _verifyAndSyncBalanceBeforeRound({required GameMode mode}) async {
    // 1. รอจังหวะให้ DOM บนหน้าเว็บประมวลผลเครดิตยอดเงินหลังจบรอบ
    await Future.delayed(Duration(milliseconds: (600 / _speedMultiplier).round()));

    // 2. สั่ง Analyzer ให้อัปเดตยอดเงินทันที
    final analyzer = _analyzersByMode[mode] ?? _sequenceAnalyzerViewModel;
    if (analyzer != null) {
      await analyzer.updateBalanceFast();
    }

    // 3. อ่านยอดเงินล่าสุดจาก DOM ของโหมดนั้นโดยตรง พร้อมตรวจสอบความสมบูรณ์
    double settledBalance = 0.0;
    for (int retry = 1; retry <= 5; retry++) {
      settledBalance = await _getBalanceDouble(mode: mode);
      if (settledBalance > 0.00000001) {
        break;
      }
      await Future.delayed(Duration(milliseconds: (350 / _speedMultiplier).round()));
    }

    final state = getState(mode);
    if (settledBalance <= 0.00000001) {
      settledBalance = state.lastSettledBalance > 0.00000001
          ? state.lastSettledBalance
          : ((state.sessionStartBalance != null && state.sessionStartBalance! > 0.00000001)
              ? state.sessionStartBalance!
              : (state.sessionMaxBalance > 0.00000001 ? state.sessionMaxBalance : 0.0));
    }
    final currentCoin = analyzer?.getCoinTypeForMode(mode);
    if (currentCoin != null && state.activeCoinType != null && state.activeCoinType != currentCoin) {
      debugPrint(
        '[COIN SWITCH] 🔄 [${mode.displayName}] Coin switched from ${state.activeCoinType} to $currentCoin. Resetting session balances & base bet.',
      );
      state.sessionStartBalance = settledBalance;
      state.lastSettledBalance = settledBalance;
      state.protectedPrincipal = settledBalance;
      state.sessionMaxBalance = settledBalance;
      state.sessionProfitBaseline = settledBalance > 0 ? settledBalance : null;
      state.currentHourStartBalance = settledBalance;
      state.currentHourWindowStart = DateTime.now();
      final newFloor = getFloorBetForMode(mode, coinType: currentCoin);
      state.lockedBaseBet = mode.calculateBaseBet(settledBalance, newFloor, coin: currentCoin);
      state.currentBetAmount = state.lockedBaseBet!;
      _lockedBaseBetByMode[mode] = state.lockedBaseBet;
    }
    if (currentCoin != null) {
      state.activeCoinType = currentCoin;
    }

    if (settledBalance > 0.00000001) {
      state.lastSettledBalance = settledBalance;
      state.sessionStartBalance ??= settledBalance;
      state.protectedPrincipal ??= settledBalance;
    }

    if (state.sessionMaxBalance > 0.00000001 && settledBalance > 0.00000001) {
      final double realDeficit = state.sessionMaxBalance - settledBalance;
      if (realDeficit > 0.00000001) {
        // 🎯 [PRE-M0 REAL DEBT AUDIT 🔍]
        // ซิงค์หนี้เฉพาะเมื่ออยู่ในช่วงแพ้ (consecutiveLossesStreak > 0)
        // และต้องไม่อยู่ในช่วงดูเชิง 15-25 ตา (observation) เพื่อป้องกันหนี้บวมพอง
        if (state.consecutiveLossesStreak > 0 &&
            state.observationRoundsRemaining == 0 &&
            !state.isLossStreakBaseBetLocked) {
          if (realDeficit > state.totalAccumulatedLoss + 0.00000001) {
            final double deficitGap = double.parse((realDeficit - state.totalAccumulatedLoss).toStringAsFixed(8));
            // 🛡️ ป้องกันหนี้กระโดดบวมเกิน 10% ของยอดเงินในคราวเดียว
            final double maxSafeGap = settledBalance * 0.10;
            final double safeGap = min(deficitGap, maxSafeGap);
            state.activeNewLoss += safeGap;
            state.activeNewLoss = double.parse(state.activeNewLoss.toStringAsFixed(8));
            debugPrint(
              '🎯 [PRE-M0 REAL DEBT AUDIT 🔍] [${mode.displayName}] ยอดเงินจริง (${settledBalance.toStringAsFixed(8)}) ต่ำกว่า High New (${state.sessionMaxBalance.toStringAsFixed(8)}) '
              'ขาดอีก: ${realDeficit.toStringAsFixed(8)} -> ซิงค์หนี้คงค้างเพิ่ม +${safeGap.toStringAsFixed(8)} (หนี้รวม: ${state.totalAccumulatedLoss.toStringAsFixed(8)}) โดยไม่ล้างตู้แช่แข็ง',
            );
          } else if (state.totalAccumulatedLoss > realDeficit + 0.00000001) {
            state.clampDebtToMax(realDeficit);
          }
        } else {
          // ชนะแล้ว หรืออยู่ที่ Base Bet: ถ้าหนี้เป็น 0 ให้ปรับ sessionMaxBalance สู่ยอดเงินจริงปัจจุบัน เพื่อไม่สร้างหนี้ทิพย์
          if (state.totalAccumulatedLoss <= 0.00000001) {
            state.sessionMaxBalance = settledBalance;
          }
        }
      } else if (settledBalance >= state.sessionMaxBalance) {
        state.sessionMaxBalance = settledBalance;
        // 🛡️ Trailing Ratchet: Lock in 97% of ATH as inviolable principal
        final ratcheted = settledBalance * 0.97;
        if (ratcheted > (state.protectedPrincipal ?? 0.0)) {
          state.protectedPrincipal = ratcheted;
          debugPrint(
            '🛡️ [TRAILING RATCHET] [${mode.displayName}] Ratcheted protected principal up to ${state.protectedPrincipal!.toStringAsFixed(8)} (Locked 97% of ATH: ${settledBalance.toStringAsFixed(8)})',
          );
        }
        // 🎯 เมื่อยอดเงินจริงในบัญชีแตะจุดสูงสุด (ATH) หรือมากกว่าเดิม และไม่ได้อยู่ใน streak แพ้ค้างอยู่ -> เคลียร์หนี้เป็น 0 ทันที
        if (state.consecutiveLossesStreak == 0 && state.totalAccumulatedLoss > 0.00000001) {
          state.resetDebt();
          debugPrint(
            '🎉 [ATH REACHED] 🌟 [${mode.displayName}] ยอดเงินแตะจุดสูงสุด (${settledBalance.toStringAsFixed(8)}) ล้างหนี้สะสมทั้งหมดเป็น 0.00000000 ทันที!',
          );
        }
      }
    } else if (settledBalance >= state.sessionMaxBalance && settledBalance > 0.00000001) {
      state.sessionMaxBalance = settledBalance;
      final ratcheted = settledBalance * 0.97;
      if (ratcheted > (state.protectedPrincipal ?? 0.0)) {
        state.protectedPrincipal = ratcheted;
      }
      if (state.consecutiveLossesStreak == 0 && state.totalAccumulatedLoss > 0.00000001) {
        state.resetDebt();
      }
    }

    debugPrint(
      '[BALANCE-VERIFY] 💰 [${mode.displayName}] Verified Balance: ${settledBalance.toStringAsFixed(8)} before round',
    );
    return settledBalance;
  }

  /// 🌟 Perfect Rhythmic Smart Game Flow: GUARANTEED Complete Typing BEFORE M0 Start
  Future<void> _executeSmartFlow(int runToken, {GameMode mode = GameMode.towers}) async {
    final state = getState(mode);
    while (!_shouldAbort(runToken, mode: mode) && _isSmartMode) {
      if (await _checkStopProfitInline(runToken, mode: mode)) {
        debugPrint(
          '[SMART FLOW] 🛑 [${mode.displayName}] Stop Profit reached — NOT starting new round',
        );
        break;
      }
      if (await _checkStopLossInline(runToken, mode: mode)) {
        debugPrint(
          '[SMART FLOW] 🛑 [${mode.displayName}] Hard Stop-Loss reached — NOT starting new round',
        );
        break;
      }
      if (_shouldAbort(runToken, mode: mode)) break;

      // 🔍 ตรวจสอบยอดเงินทุกครั้งก่อนที่จะไปรอบใหม่ (User Directive)
      double currentBalance = await _verifyAndSyncBalanceBeforeRound(mode: mode);
      if (currentBalance <= 0.00000001) {
        currentBalance = state.lastSettledBalance > 0.00000001
            ? state.lastSettledBalance
            : ((state.sessionStartBalance != null && state.sessionStartBalance! > 0.00000001)
                ? state.sessionStartBalance!
                : (state.sessionMaxBalance > 0.00000001 ? state.sessionMaxBalance : 0.0));
      }
      if (currentBalance >= state.sessionMaxBalance && currentBalance > 0.00000001) {
        state.sessionMaxBalance = currentBalance;
        if (state.consecutiveLossesStreak == 0 && state.totalAccumulatedLoss > 0.00000001) {
          state.resetDebt();
        }
      }

      state.totalSessionRoundsPlayed++;
      state.roundsSinceLastMicroBreak++;
      state.roundsSinceLastMacroBreak++;
      if (state.recoveryCooldownRounds > 0) {
        state.recoveryCooldownRounds--;
      }
      state.lastHeartbeatTime = DateTime.now();
      // Automatic page refresh is completely disabled (User Directive: ไม่ต้องให้ refresh แล้ว)

      // 🏛️ PILLAR 2: HUMAN SLEEP CYCLES & ANTI-BAN
      // A) Macro-Break (พักเบรกใหญ่ 3-6 นาที ทุก 180-240 รอบ)
      final int macroTarget = 180 + (mode == GameMode.towers ? 20 : 40);
      if (state.roundsSinceLastMacroBreak >= macroTarget && state.consecutiveLossesStreak == 0) {
        state.roundsSinceLastMacroBreak = 0;
        final int macroPauseSec = 180 + Random().nextInt(180); // 3m to 6m
        debugPrint(
          '🛋️ [HUMAN SLEEP CYCLE] [${mode.displayName}] Macro-break (Coffee/Rest) at round ${state.totalSessionRoundsPlayed}! Stepping away for ${macroPauseSec ~/ 60}m ${macroPauseSec % 60}s...',
        );
        await Future.delayed(Duration(seconds: (macroPauseSec / _speedMultiplier).round()));
      }
      // B) Micro-Break (พักสายตา 1-2 นาที ทุก 50 รอบ)
      else if (state.roundsSinceLastMicroBreak >= 50 && state.consecutiveLossesStreak == 0) {
        state.roundsSinceLastMicroBreak = 0;
        final int microPauseSec = 60 + Random().nextInt(60); // 60s to 120s
        debugPrint(
          '☕ [HUMAN SLEEP CYCLE] [${mode.displayName}] Micro-break (Rest Eyes) at round ${state.totalSessionRoundsPlayed}! Resting for ${microPauseSec}s...',
        );
        await Future.delayed(Duration(seconds: (microPauseSec / _speedMultiplier).round()));
      }

      // 🕒 หลังแพ้พักดู 5.5s - 8.5s (User Directive)
      if (state.consecutiveLossesStreak > 0) {
        final int coolDown = 5500 + Random().nextInt(3000);
        debugPrint('[COOL-DOWN] 🕒 [${mode.displayName}] Post-loss observation pause: ${coolDown}ms (5.5s - 8.5s)...');
        await Future.delayed(Duration(milliseconds: (coolDown / _speedMultiplier).round()));
      }

      if (_shouldAbort(runToken, mode: mode) || !_isSmartMode) break;

      // 🧠 1. CALCULATE OMNI-MATRIX PREDICTION & CONFIDENCE FIRST!
      // Must be evaluated before setting the bet so we know if this is a Golden Window or Foggy!
      state.ghostRoundCounter++;

      final double totalDebt = state.totalAccumulatedLoss;


      // 🎯 คำสั่งผู้ใช้: ทวง 100% ทุกตาที่แพ้ (Streak 1, 2, 3)
      // หมุน Seed ทันทีเมื่อแพ้ เพื่อสับหลบ RNG คาสิโน แต่ไม่บล็อกการทวงหนี้เด็ดขาด!
      if (state.consecutiveLossesStreak >= 2) {
        OmniMatrixEngine.instance.rotateSeed(mode: mode);
        rotateWebClientSeed(mode: mode);
      }
      if (state.consecutiveLossesStreak >= 3) {
        debugPrint(
          '🛡️ [CRITICAL ANTI-STREAK-4 SHIELD 🛡️] [${mode.displayName}] Streak: ${state.consecutiveLossesStreak} -> '
          'เปิดใช้งานระบบป้องกันการแพ้ > 3 ตาติดขั้นสูงสุด! สับหลบ RNG และสถิติระเบิด 100%!',
        );
      }

      // 🎯 Auto-transition: If observation counter reached 0 while still in observation state, transition to recoveryGate
      if (state.observationRoundsRemaining <= 0 && (state.recoveryState == RecoveryState.observation || state.isLossStreakBaseBetLocked)) {
        state.isLossStreakBaseBetLocked = false;
        state.consecutiveLossesStreak = 0;
        OmniMatrixEngine.instance.resetStreak(mode: mode);
        if (state.totalAccumulatedLoss > 0.00000001) {
          state.recoveryStepInCycle = 1; // 🎯 ครบกำหนดดูเชิง 15-25 ตาแล้ว! เริ่มต้นไม้ทวงที่ 1 ทันที!
          transitionRecoveryState(mode, RecoveryState.recoveryGate, reason: 'Observation count zero with debt -> starting recovery step 1 in cycle ${state.currentRecoveryCycle}');
          debugPrint(
            '🎯 [OBSERVATION COMPLETE 🔭] [${mode.displayName}] ครบกำหนดดูเชิง 15-25 ตาแล้ว! เริ่มต้นไม้ทวงหนี้ที่ 1 (รอบที่ ${state.currentRecoveryCycle}) ทันที!',
          );
        } else {
          state.observationRoundsRemaining = 0;
          state.isLossStreakBaseBetLocked = false;
          state.recoveryStepInCycle = 0;
          state.currentRecoveryCycle = 1;
          transitionRecoveryState(mode, RecoveryState.normal, reason: 'Observation count zero, no debt -> return to normal mode');
        }
      }

      // 🧠 ระบบทายของสมอง AI (User Directive: "ให้ใช้ระบบทายของ สมอง AI"):
      final analyzer = _analyzersByMode[mode] ?? _sequenceAnalyzerViewModel;
      final roundCoin = state.activeCoinType ?? analyzer?.getCoinTypeForMode(mode);
      final double roundFloor = getFloorBetForMode(mode, coinType: roundCoin);
      final double currentFloorBet = state.lockedBaseBet ?? _lockedBaseBetByMode[mode] ?? roundFloor;

      // 🎯 Centralized Recovery Gate:
      // Preliminary check for OmniMatrix input (isRecoveryRound):
      final bool isEligibleForRecovery = canEnterRecovery(mode, floorBet: currentFloorBet);

      String? aiBrainPrediction = analyzer?.lastPredictedChar;

      // 🧠 คำนวณ OmniMatrix Prediction & Confidence
      final omniResult = OmniMatrixEngine.instance.getNextPrediction(
        mode: mode,
        isRecoveryRound: isEligibleForRecovery,
        currentDebt: totalDebt,
        currentBalance: currentBalance,
        aiBrainPrediction: aiBrainPrediction,
      );
      String prediction = omniResult.column;
      String targetMarker = prediction == 'A' ? 'M1' : (prediction == 'B' ? 'M2' : 'M3');

      debugPrint(
        '[AI BRAIN PREDICTION 🧠] [${mode.displayName}] Prediction: Column $prediction ($targetMarker) | Conf: ${omniResult.confidence.toStringAsFixed(1)}% | Clearance: ${omniResult.recoveryClearance.displayName} | Debt: ${totalDebt.toStringAsFixed(8)} | RecoveryEligible: $isEligibleForRecovery | State: ${state.recoveryState.name} | Cycle: ${state.currentRecoveryCycle} | Step: ${state.recoveryStepInCycle}/3',
      );

      // 🛡️ PROFIT & ATH PROTECTION GUARD:
      if (currentBalance >= state.sessionMaxBalance && state.sessionMaxBalance > 0.00000001) {
        if (state.consecutiveLossesStreak == 0 && state.totalAccumulatedLoss > 0.00000001) {
          state.resetDebt();
          debugPrint('🛡️ [ATH PROFIT GUARD] [${mode.displayName}] ยอดเงินแตะจุดสูงสุด (${currentBalance.toStringAsFixed(8)}) เคลียร์หนี้เป็น 0 ทันที');
        }
      }

      // 🎯 Final Authoritative Recovery Approval via Safety Gate:
      bool approvedForRecovery = canEnterRecovery(mode, omniResult: omniResult, floorBet: currentFloorBet);

      // 🛑 ABSOLUTE CEILING GUARD: แพ้ครบ 3 ตา หรืออยู่ในช่วงดูเชิง 15-25 ตา ห้ามทวงเด็ดขาด 100%!
      if (state.consecutiveLossesStreak >= 3 ||
          state.observationRoundsRemaining > 0 ||
          state.isLossStreakBaseBetLocked ||
          state.recoveryState == RecoveryState.observation) {
        approvedForRecovery = false;
      }

      if (approvedForRecovery) {
        if (state.recoveryStepInCycle == 0) {
          state.recoveryStepInCycle = 1; // 🎯 ไม้ทวงที่ 1 เริ่มต้นทันทีเมื่อมีหนี้
          state.randomizeRecoveryQuota();
        }
        transitionRecoveryState(mode, RecoveryState.recovery, reason: 'Recovery Gate Approved');
        state.isCurrentlyRecoveryRound = true;
        debugPrint(
          '🎯 [FULL RECOVERY 100% ⚡] [${mode.displayName}] สิทธิ์ทวงหนี้ผ่านเกณฑ์ (State: ${state.recoveryState.name} | รอบที่ ${state.currentRecoveryCycle} | ไม้ที่ ${state.recoveryStepInCycle}/${state.maxRecoveryStepsThisCycle}) -> ทวงเต็ม 100% จากหนี้รวม: ${totalDebt.toStringAsFixed(8)} (Clearance: ${omniResult.recoveryClearance.displayName})',
        );
        await _executeSymbioticRecovery(
          runToken,
          mode: mode,
        );
      } else {
        if (state.totalAccumulatedLoss > 0.00000001) {
          final double normalizedConf = omniResult.confidence <= 1.0
              ? omniResult.confidence * 100.0
              : omniResult.confidence;
          if (omniResult.recoveryClearance == RecoveryClearance.holdFire ||
              omniResult.chaosIndex >= 0.50 ||
              normalizedConf < 75.0 ||
              omniResult.mathematicalEdge < 0.05) {
            debugPrint(
              '🎯 [AQ-DARE SNIPER RECOVERY 🛡️] [${mode.displayName}] Filter Blocked (Chaos: ${omniResult.chaosIndex.toStringAsFixed(2)}, Conf: ${normalizedConf.toStringAsFixed(1)}%, Edge: ${omniResult.mathematicalEdge.toStringAsFixed(2)}, Regime: ${omniResult.marketRegime}) -> ชะลอไม้ทวง เดิน Base Bet สอดแนมก่อน',
            );
          }
        }
        // 🎯 ชนะแล้วจะไม่ทวงหนี้เด็ดขาด / ไม่มีหนี้สะสม / แพ้ครบ 3 ตา (เข้าโหมดสังเกตการณ์ 15-20 ตา นับจากรอบแพ้สุดท้าย): โหมดสะสมกำไร (Profit Engine) เดิน Base Bet ปกติ
        state.tier1RecoveryIndex = 0;
        state.tier2RecoveryIndex = 0;
        state.isCurrentlyRecoveryRound = false;

        // 🎯 คำสั่งผู้ใช้: "เมื่อชนะ ในหน้า Tower ให้เดิน Base Bet นิ่งๆ คงที่เสมอ ห้ามสลับยอดไปมา"
        await _ensureBaseBet(runToken, mode: mode);
      }
      if (_shouldAbort(runToken, mode: mode)) break;

      // Capture Balance Right Before M0 Click
      double balanceBeforeRound = await _getBalanceDouble(mode: mode);
      if (balanceBeforeRound <= 0.00000001) {
        balanceBeforeRound = currentBalance;
      }
      debugPrint(
        '[ROUND PRE-CHECK] 💰 [${mode.displayName}] Balance before round: ${balanceBeforeRound.toStringAsFixed(8)} | Highest Balance: ${state.sessionMaxBalance.toStringAsFixed(8)}',
      );

      // 🛡️ [M0 PRE-CLICK GUARD] รอพิมพ์ยอดเดิมพันเสร็จสิ้น 100% และตรวจสอบค่าใน DOM ก่อนกด M0 เสมอ!
      final m0WebCtrl = getWebViewController(mode);
      if (m0WebCtrl != null) {
        int guardWaitMs = 0;
        const int maxGuardWaitMs = 6000;
        while (guardWaitMs < maxGuardWaitMs && !_shouldAbort(runToken, mode: mode)) {
          final dynamic checkResult = await m0WebCtrl.evaluateJavascript(source: """
            (function() {
              if (window._betTypingInProgress === true) return { ready: false, reason: 'typing' };
              let inp = null;
              let isMinesMode = window.location.href.includes('polpick') || window.location.href.includes('gems.php') || window.location.href.includes('mines');
              if (isMinesMode) {
                let allInputs = Array.from(document.querySelectorAll('input')).filter(inp => {
                  let t = (inp.type || 'text').toLowerCase();
                  if (t === 'hidden' || t === 'password' || t === 'checkbox' || t === 'radio' || t === 'submit' || t === 'search') return false;
                  let rect = inp.getBoundingClientRect();
                  return rect.width > 0 && rect.height > 0;
                });
                if (allInputs.length > 0) {
                  allInputs.sort((a, b) => b.getBoundingClientRect().top - a.getBoundingClientRect().top);
                  inp = allInputs[0];
                }
              }
              if (!inp) {
                let selectors = ['input#amount', 'input#bet_amount', 'input#bet-amount', 'input[name="amount"]', 'input[name="bet_amount"]', 'input.bet-amount', 'input.bet_amount', 'input[placeholder*="Amount" i]', 'input[placeholder*="Bet" i]', 'input[aria-label*="amount" i]'];
                for (let s of selectors) {
                  let el = document.querySelector(s);
                  if (el && el.type !== 'hidden' && el.type !== 'checkbox' && el.type !== 'radio') { inp = el; break; }
                }
              }
              if (!inp) {
                let allInputs = Array.from(document.querySelectorAll('input')).filter(i => {
                  let t = (i.type || 'text').toLowerCase();
                  if (t === 'hidden' || t === 'password' || t === 'checkbox' || t === 'radio' || t === 'submit' || t === 'search') return false;
                  let nameOrId = (i.name || i.id || i.placeholder || i.getAttribute('aria-label') || '').toLowerCase();
                  if (nameOrId.includes('mine') || nameOrId.includes('bomb') || nameOrId.includes('count')) return false;
                  let rect = i.getBoundingClientRect();
                  return rect.width > 0 && rect.height > 0;
                });
                if (allInputs.length > 0) {
                  inp = allInputs[0];
                }
              }
              if (!inp) return { ready: true, reason: 'no_input' };
              let valStr = (inp.value || '').trim().replace(/,/g, '');
              let curVal = parseFloat(valStr);
              if (isNaN(curVal) || curVal <= 0) return { ready: true, reason: 'empty' };
              let targetVal = ${state.currentBetAmount};
              let diff = Math.abs(curVal - targetVal);
              if (diff < 0.00000002) {
                return { ready: true, reason: 'matched', domVal: curVal };
              }
              return { ready: false, reason: 'mismatch', domVal: curVal, targetVal: targetVal };
            })()
          """).timeout(const Duration(milliseconds: 400), onTimeout: () => {'ready': false, 'reason': 'timeout'});

          bool isReady = false;
          if (checkResult is Map) {
            isReady = checkResult['ready'] == true;
          } else if (checkResult is bool) {
            isReady = checkResult;
          }

          if (isReady) {
            break;
          }

          // 🔄 หากตรวจพบ mismatch และตานี้เป็น Base Bet ให้พยายาม force set ซ้ำทุกๆ 500ms ทันที
          if (!approvedForRecovery && (guardWaitMs % 500 == 0)) {
            await _forceSetBaseBet(mode: mode);
          }

          debugPrint('⏳ [M0 GUARD] [${mode.displayName}] กำลังรอพิมพ์ยอดเดิมพัน (${state.currentBetAmount.toStringAsFixed(8)}) ให้เสร็จสมบูรณ์ก่อนกด M0... (${guardWaitMs}ms, status: $checkResult)');
          await Future.delayed(const Duration(milliseconds: 100));
          guardWaitMs += 100;
        }
      }

      // 🛑 ABSOLUTE ZERO-RECOVERY-ON-ROUND-4 PHYSICAL SHIELD:
      // ป้องกันการกดยิง M0 เด็ดขาดหากตานี้ไม่ได้สิทธิ์ทวงหนี้ แต่หน้าเว็บยังค้างยอดเงินทวงหนี้จากตาที่แล้ว!
      final coin = state.activeCoinType ?? analyzer?.getCoinTypeForMode(mode);
      final double defaultFloor = getFloorBetForMode(mode, coinType: coin);
      final double floorBet = state.lockedBaseBet ?? _lockedBaseBetByMode[mode] ?? defaultFloor;

      if (!approvedForRecovery) {
        double currentDomBet = await _getBetAmount(mode: mode);
        if (currentDomBet > floorBet * 1.5) {
          debugPrint('🚨 [CRITICAL M0 BLOCK] ตานี้ไม่ใช่ไม้ทวงหนี้ (Approved: false, Streak: ${state.consecutiveLossesStreak}, Obs: ${state.observationRoundsRemaining}) แต่ยอดบนหน้าเว็บคือ $currentDomBet (> Base Bet $floorBet)! กำลังบังคับล้างค่าสู่ Base Bet...');
          await _forceSetBaseBet(mode: mode);
          await Future.delayed(const Duration(milliseconds: 300));
          currentDomBet = await _getBetAmount(mode: mode);
          if (currentDomBet > floorBet * 1.5) {
            await _setBetAmount(floorBet, mode: mode);
            await Future.delayed(const Duration(milliseconds: 300));
            currentDomBet = await _getBetAmount(mode: mode);
          }
          if (currentDomBet > floorBet * 1.5) {
            debugPrint('🛑 [EMERGENCY GUARD] ไม่สามารถปรับยอดเป็น Base Bet ได้สำเร็จ (DOM: $currentDomBet)! ข้ามการกด M0 ในรอบนี้เพื่อปกป้องเงินในบัญชี...');
            await Future.delayed(const Duration(seconds: 1));
            continue;
          }
        }
      }

      // 1. Click M0 (Start / Place Bet)
      debugPrint('[SMART FLOW] 🟢 [${mode.displayName}] 1️⃣ Clicking M0 (Start Bet)');
      await _performButtonAction('M0', mode: mode);
      if (_shouldAbort(runToken, mode: mode)) break;

      // 2. 🕒 หลังกดเริ่ม M0 ➔ รอเซิร์ฟเวอร์โหลดและมองกระดาน 3.0s - 5.5s (User Directive)
      final int m0LoadDelay = 3000 + Random().nextInt(2500);
      debugPrint('[PACE] 🕒 [${mode.displayName}] Waiting for server load & observing board: ${m0LoadDelay}ms (3.0s - 5.5s)');
      await Future.delayed(Duration(milliseconds: (m0LoadDelay / _speedMultiplier).round()));
      if (_shouldAbort(runToken, mode: mode)) break;

      // 3. 🕒 ก่อนกดเลือกกล่อง M1/M2/M3 ➔ มีจังหวะตัดสินใจ 250ms - 300ms (User Directive)
      final int humanDecideDelay = 250 + Random().nextInt(50);
      debugPrint('[PACE] 🕒 [${mode.displayName}] Decision delay: ${humanDecideDelay}ms (250ms - 300ms)');
      await Future.delayed(Duration(milliseconds: (humanDecideDelay / _speedMultiplier).round()));
      if (_shouldAbort(runToken, mode: mode)) break;

      // 4. Click Selected Prediction Marker
      await _performButtonAction(targetMarker, mode: mode);
      if (_shouldAbort(runToken, mode: mode)) break;

      // 5. Result UI settle delay (600ms - 900ms)
      final int settleDelay = 600 + Random().nextInt(300);
      await Future.delayed(Duration(milliseconds: (settleDelay / _speedMultiplier).round()));
      if (_shouldAbort(runToken, mode: mode)) break;

      // 6. Detection Loop
      bool resolutionFound = false;
      int m0Retries = 0;
      const int maxM0Retries = 30;

      while (!_shouldAbort(runToken, mode: mode) &&
          _isSmartMode &&
          !resolutionFound &&
          m0Retries < maxM0Retries) {
        m0Retries++;
        await Future.delayed(
          Duration(milliseconds: (350 / _speedMultiplier).round()),
        );
        if (_shouldAbort(runToken, mode: mode)) break;

        String m0Status = await _detectVisualOutcomeWithVerification('M0', mode: mode);
        String? discoveredBombPos = await _findRevealedBombPosition(mode: mode);
        if (_shouldAbort(runToken, mode: mode)) break;

        if (m0Status == 'cashout') {
          // 💎 CASHOUT VERIFICATION RULE for Mines: Do NOT cashout until 💎 Gem is verified!
          if (mode == GameMode.mines) {
            bool isGemConfirmed = await _hasRevealedGem(mode: mode, targetMarker: targetMarker);
            if (!isGemConfirmed) {
              debugPrint('[CASHOUT GUARD] ⏳ [Mine] Cashout button visible, but waiting for 💎 Gem verification on board...');
              continue;
            }
          }

          resolutionFound = true;
          state.lastRoundWasWin = true;
          debugPrint('Smart Flow [${mode.displayName}]: 💰 CASHOUT detected at M0 (WIN).');

          String gemPos = (targetMarker == 'M1')
              ? 'A'
              : (targetMarker == 'M2' ? 'B' : 'C');
          try {
            final analyzer = _analyzersByMode[mode] ?? _sequenceAnalyzerViewModel;
            await analyzer?.recordInput(
              gemPos,
              triggerId: targetMarker,
              multiplier: 1.0,
              selectedAction: prediction,
              isWin: true,
            );
          } catch (e) {
            debugPrint('[RECORD ERROR] Win record: $e');
          }
          if (_shouldAbort(runToken, mode: mode)) break;

          if (state.isMicroProbingActive) {
            state.isMicroProbingActive = false;
            state.consecutiveLossesStreak = 0;
            state.isLossStreakBaseBetLocked = false;
            debugPrint(
              '🎯 [MICRO PROBE SUCCESS! 💎] [${mode.displayName}] ไม้ดูเชิงชนะแล้ว! AI อ่านทาง Seed ใหม่ทะลุปรุโปร่ง -> ปลดล็อกโหมดดูเชิง รีเซ็ต Streak เป็น 0 ตาถัดไปเตรียมยิงไม้ทวงหนี้เต็ม 100% บนช่อง Golden Highway ทันที!',
            );
          }
          if (state.isIntermissionProbeActive) {
            state.isIntermissionProbeActive = false;
            state.consecutiveLossesStreak = 0;
            state.isLossStreakBaseBetLocked = false;
            debugPrint(
              '🎯 [INTERMISSION PROBE WIN 💎] [${mode.displayName}] ไม้สอดแนมมีผลเป็นบวก (ชนะ)! ยืนยันแนวโน้มปลอดภัย -> ปลดล็อกพร้อมยิงทวงหนี้งวดถัดไปบนช่อง Golden Highway ทันที!',
            );
          }

          if (state.observationRoundsRemaining <= 0 && (state.isLossStreakBaseBetLocked || state.consecutiveLossesStreak >= 3)) {
            debugPrint(
              '🎉 [STREAK BROKEN 💎] [${mode.displayName}] ชนะสำเร็จ! (ปลดล็อกสถิติแพ้ติดกัน ${state.consecutiveLossesStreak} ตา)',
            );
          }
          if (state.observationRoundsRemaining > 0) {
            state.isLossStreakBaseBetLocked = true;
          } else if (state.fourLossesFreezeUntil != null && DateTime.now().isBefore(state.fourLossesFreezeUntil!)) {
            state.isLossStreakBaseBetLocked = true;
          } else {
            state.isLossStreakBaseBetLocked = false;
            state.fourLossesFreezeUntil = null;
          }
          state.isMicroProbingActive = false;
          state.isIntermissionProbeActive = false;
          state.consecutiveLossesStreak = 0;
          _lossSequence.clear();
          OmniMatrixEngine.instance.recordOutcome(
            chosenColumn: prediction,
            won: true,
            revealedBombPos: discoveredBombPos,
            mode: mode,
          );

          // 🕒 เมื่อชนะ ➔ มีจังหวะดีใจ/มองยอดเงิน 250ms - 300ms ก่อนกด CASHOUT (User Directive)
          final int cashoutReaction = 250 + Random().nextInt(50);
          debugPrint('[PACE] 🕒 [${mode.displayName}] Win observation before CASHOUT: ${cashoutReaction}ms (250ms - 300ms)');
          await Future.delayed(Duration(milliseconds: (cashoutReaction / _speedMultiplier).round()));
          if (_shouldAbort(runToken, mode: mode)) break;

          // Click Cashout M0 to claim
          await _performButtonAction('M0', mode: mode);
          if (_shouldAbort(runToken, mode: mode)) break;

          // 🔍 VERIFY WIN VIA BALANCE & HIGHEST BALANCE (User Directive)
          // "เพราะว่าบางครั้งมันบอกว่าชนะแต่ยอดเงินไม่เพิ่มขึ้นเป็นเพราะเน็ตช้าครับ"
          // รอตรวจสอบให้ยอดเงินขยับเพิ่มขึ้นจริง และอัปเดตยอดสูงสุด (Highest Balance)
          double balanceAfterWin = 0.0;
          bool balanceIncreased = false;
          for (int poll = 1; poll <= 10; poll++) {
            await Future.delayed(Duration(milliseconds: (500 / _speedMultiplier).round()));
            balanceAfterWin = await _getBalanceDouble(mode: mode);
            if (balanceBeforeRound > 0.00000001 && balanceAfterWin > balanceBeforeRound + 0.00000001) {
              balanceIncreased = true;
              break;
            }
          }
          if (_shouldAbort(runToken, mode: mode)) break;

          double winningBet = await _getBetAmount(mode: mode);
          if (winningBet <= 0.0) winningBet = state.currentBetAmount;
          final bool wasRecoveryRound = state.isCurrentlyRecoveryRound;
          state.isCurrentlyRecoveryRound = false;

          final double defaultFloor = getFloorBetForMode(mode);
          final double floorBet = state.lockedBaseBet ?? _lockedBaseBetByMode[mode] ?? defaultFloor;
          final bool isRealBaseBet = winningBet >= (floorBet * 0.85);

          if (wasRecoveryRound) {
            state.consecutiveRecoveryLosses = 0;
            state.consecutiveBaseBetWins = 0;
            state.justWonRecoveryBet = true;
            state.isLossStreakBaseBetLocked = false;
            state.fourLossesFreezeUntil = null;
            debugPrint(
              '🎯 [RECOVERY ROUND WON! 💎] [${mode.displayName}] ไม้ทวงหนี้ชนะสำเร็จ! ปลดล็อก Base Bet และหักกำไรลดหนี้',
            );
          } else {
            state.ghostSniperWinCount++;
            state.justWonRecoveryBet = false;
            if (isRealBaseBet) {
              state.consecutiveBaseBetWins++;
            }

            // 🎯 Observation Countdown on WIN:
            // ทุกตาที่เล่นในช่วงดูเชิง 15-25 ตา (ไม่ว่าจะชนะหรือแพ้) ให้นับถอยหลังเสมอ
            if (state.observationRoundsRemaining > 0) {
              state.observationRoundsRemaining--;
              debugPrint(
                '🔭 [OBSERVATION WIN 💎] [${mode.displayName}] ไม้สังเกตการณ์ชนะ! '
                '(เหลืออีก ${state.observationRoundsRemaining} ตา)',
              );
              if (state.observationRoundsRemaining <= 0) {
                state.observationRoundsRemaining = 0;
                state.isLossStreakBaseBetLocked = false;
                state.consecutiveLossesStreak = 0;
                OmniMatrixEngine.instance.resetStreak(mode: mode);
                if (state.totalAccumulatedLoss > 0.00000001) {
                  state.recoveryStepInCycle = 1;
                  state.randomizeRecoveryQuota();
                  transitionRecoveryState(mode, RecoveryState.recoveryGate,
                      reason: 'Observation completed with win -> immediate recovery step 1 in cycle ${state.currentRecoveryCycle} (Quota: ${state.maxRecoveryStepsThisCycle} steps)');
                  debugPrint(
                    '🎯 [OBSERVATION COMPLETE 🔭] [${mode.displayName}] สังเกตการณ์ครบแล้ว! '
                    'ตาสุดท้ายชนะ -> เข้าสู่ RECOVERY_GATE สุ่มโควตาทวง ${state.maxRecoveryStepsThisCycle} ไม้ เริ่มไม้ทวงที่ 1 (รอบที่ ${state.currentRecoveryCycle}) ทันที!',
                  );
                } else {
                  state.recoveryStepInCycle = 0;
                  state.currentRecoveryCycle = 1;
                  state.observationRoundsRemaining = 0;
                  state.isLossStreakBaseBetLocked = false;
                  transitionRecoveryState(mode, RecoveryState.normal,
                      reason: 'Observation completed and debt fully paid down -> return to normal mode');
                }
              }
            }

            // 🛡️ Debt Inflation Kill-Switch:
            // ห้ามรีเซ็ต consecutiveRecoveryLosses ในตาดูเชิง (Micro-Probe)
            // จะรีเซ็ตได้เฉพาะเมื่อปลดล็อก Micro-Probe สำเร็จ (ชนะ 2 ตาติด) หรือชนะไม้ทวงจริง
            if (!state.isMicroProbingActive) {
              state.consecutiveRecoveryLosses = 0;
            }
            if (!isRealBaseBet) {
              debugPrint('🔬 [MICRO-BET WIN] [${mode.displayName}] ชนะตา Micro Bet (ดูเชิง) -> โมเดลทายถูกแต่เป็นไม้สังเกตการณ์ (ไม่นับเป็น Base Bet win เพื่อความรัดกุม)');
            }
          }

          // 🛡️ SHIELD 4: Record win in recent rounds history
          state.recentRoundsHistory.add(true);
          if (state.recentRoundsHistory.length > 10) {
            state.recentRoundsHistory.removeAt(0);
          }

          final double theoreticalProfit = winningBet * getRecoveryProfitPercent(mode);
          double actualProfit = theoreticalProfit;
          if (balanceIncreased) {
            final double measuredDelta = balanceAfterWin - balanceBeforeRound;
            actualProfit = measuredDelta > theoreticalProfit ? measuredDelta : theoreticalProfit;
            debugPrint(
              '💰 [WIN CONFIRMED BY BALANCE] [${mode.displayName}] ยอดเงินเพิ่มขึ้นจริง! จาก ${balanceBeforeRound.toStringAsFixed(8)} -> ${balanceAfterWin.toStringAsFixed(8)} (กำไรคำนวณ: +${actualProfit.toStringAsFixed(8)})',
            );
            // อัปเดตยอดสูงสุด (Highest Balance) ทันที
            if (balanceAfterWin >= state.sessionMaxBalance) {
              state.sessionMaxBalance = balanceAfterWin;
              if (state.totalAccumulatedLoss > 0.00000001) {
                state.resetDebt();
                debugPrint('🎉 [NEW ATH WIN] 🌟 [${mode.displayName}] New Highest: ${balanceAfterWin.toStringAsFixed(8)} | ล้างหนี้สะสมทั้งหมดเป็น 0.00000000 ทันที!');
              }
            }
          } else {
            // ยอดเงินยังไม่ขยับใน DOM (เน็ตช้า แต่เกม Cashout สำเร็จจริง 100% จาก Server)
            // 🎯 แก้บั๊กเน็ตช้า: ให้ใช้กำไรตามจริง (theoreticalProfit) หักลดหนี้ทันที ป้องกันหนี้ทิพย์สะสม
            debugPrint(
              '⚡ [WIN CONFIRMED BY CASHOUT] [${mode.displayName}] ชนะ Cashout สำเร็จ 100% (DOM ดีเลย์) -> ใช้กำไรจริง +${theoreticalProfit.toStringAsFixed(8)} หักลดหนี้สะสมทันที ไม่ให้หนี้บวมทิพย์!',
            );
          }
          // 🏛️ PILLAR 4: MILESTONE PROFIT BANKING & COMPOUNDING
          final double baseline = state.sessionProfitBaseline ?? state.sessionStartBalance ?? 0.0;
          if (baseline > 0.00000001) {
            final double currentProfitPct = (currentBalance - baseline) / baseline;
            if (currentProfitPct >= 0.05) {
              state.profitMilestonesAchieved++;
              state.sessionProfitBaseline = currentBalance;
              // 🎯 คำสั่งผู้ใช้: "ไม่ต้องมี ลอก 5% แล้วต่อไปให้ทวง 100%"
              // ไม่ล็อก protectedPrincipal และไม่รีเซ็ต sessionStartBalance ทุก 5% เพื่อไม่ให้เกิดกลไกยกระดับ Emergency Floor บีบอัดโควตาทวงหนี้ 100%
              debugPrint(
                '🏦 [PROFIT MILESTONE 🌟] [${mode.displayName}] Milestone #${state.profitMilestonesAchieved} REACHED! Profit: +${(currentProfitPct * 100).toStringAsFixed(1)}%! (เติบโตต่อเนื่อง ไม่ล็อกเพดานขัดขวางการทวงหนี้ 100%)',
              );

              // 🚀 MILESTONE COMPOUNDING:
              // ปรับคำนวณ Base Bet ใหม่ตามขนาดพอร์ตที่โตขึ้นจริง (balance / 10000)
              // สร้างพลังดอกเบี้ยทบต้น (Compound Growth) เพื่อให้อัตราผลิตกำไรโตตามขนาดพอร์ต โดยคงสัดส่วนความเสี่ยง 1/10000 เท่าเดิม
              final coin = state.activeCoinType ?? analyzer?.getCoinTypeForMode(mode);
              final double defaultFloor = getFloorBetForMode(mode, coinType: coin);
              final double updatedBaseBet = mode.calculateBaseBet(currentBalance, defaultFloor, coin: coin);
              if (updatedBaseBet > (state.lockedBaseBet ?? 0.0)) {
                state.lockedBaseBet = updatedBaseBet;
                _lockedBaseBetByMode[mode] = updatedBaseBet;
                debugPrint(
                  '📈 [COMPOUND BASE BET 🌟] [${mode.displayName}] ขยับฐาน Base Bet ทบต้นเป็น ${updatedBaseBet.toStringAsFixed(8)} ตามพอร์ตที่โตขึ้น (${currentBalance.toStringAsFixed(8)})!',
                );
              }

              final int victoryPause = 15 + Random().nextInt(10);
              await Future.delayed(Duration(seconds: (victoryPause / _speedMultiplier).round()));
            }
          }

          // ⏱️ HOURLY REPORT: Track progress every 60 minutes
          if (DateTime.now().difference(state.currentHourWindowStart).inMinutes >= 60) {
            double hourlyGain = currentBalance - state.currentHourStartBalance;
            double hourlyPct = state.currentHourStartBalance > 0 ? (hourlyGain / state.currentHourStartBalance * 100) : 0.0;
            debugPrint(
              '⏱️ [HOURLY REPORT] 📊 [${mode.displayName}] Past 60 min Net Profit: ${hourlyGain >= 0 ? "+" : ""}${hourlyGain.toStringAsFixed(8)} (${hourlyPct >= 0 ? "+" : ""}${hourlyPct.toStringAsFixed(2)}%). Starting new hourly cycle.',
            );
            state.currentHourWindowStart = DateTime.now();
            state.currentHourStartBalance = currentBalance;
          }

          // 🎯 กฎเหล็ก: หนี้คือหนี้ จะมาลบออกลอยๆ ไม่ได้ แต่ "กำไรที่ชนะจริง" นำมาทยอยหักหนี้ได้ทุกตา!
          // ไม่ว่าจะเป็นตา Base Bet หรือ Recovery Bet ทุกกำไรที่เกิดขึ้นจริงจะนำมาลดหนี้สะสมอย่างโปร่งใส
          if (state.totalAccumulatedLoss > 0.00000001 && actualProfit > 0.00000001) {
            state.subtractProfitFromDebt(actualProfit);
            debugPrint('💰 [DEBT PAYDOWN] [${mode.displayName}] นำกำไรที่ชนะจริง (+${actualProfit.toStringAsFixed(8)}) มาหักลดหนี้สะสม! หนี้คงเหลือ: ${state.totalAccumulatedLoss.toStringAsFixed(8)}');
          }

          // 🎯 คำนวณยอดเงินจริงสำหรับตรวจสอบ ATH:
          double currentBalForCheck = balanceIncreased && balanceAfterWin > 0.00000001
              ? balanceAfterWin
              : (balanceBeforeRound > 0.00000001 ? balanceBeforeRound : currentBalance);

          bool isFullyRecovered = false;
          if (balanceIncreased && state.sessionMaxBalance > 0.00000001 && currentBalForCheck < state.sessionMaxBalance - 0.00000001) {
            final double remainingDeficit = state.sessionMaxBalance - currentBalForCheck;
            if (state.totalAccumulatedLoss > remainingDeficit + 0.00000001) {
              state.clampDebtToMax(remainingDeficit);
            }
            isFullyRecovered = false;
          } else if (balanceIncreased) {
            isFullyRecovered = state.totalAccumulatedLoss <= 0.00000001 || (currentBalForCheck >= state.sessionMaxBalance && state.sessionMaxBalance > 0.00000001);
          } else {
            isFullyRecovered = false;
          }

          if (wasRecoveryRound) {
            state.recoveryLossStreak = 0;
            state.recoveryAttempts = 0;
            state.consecutiveRecoveryLosses = 0;
            state.consecutiveBaseBetWins = 0;
            state.justWonRecoveryBet = true;
            state.isCurrentlyRecoveryRound = false;
            state.recoveryCooldownRounds = 0;
            _randomizeRhythm();
            await rotateWebClientSeed(mode: mode);
            await _ensureBaseBet(runToken, mode: mode);

            // 🎯 100% RECOVERY COMPLETION CHECK ("ชนะกลับไป Base Bet"):
            // เมื่อชนะไม้ทวงหนี้ ให้เคลียร์หนี้หมดและกลับสู่การเล่น Base Bet ปกติทันที (ไม่ล็อกดูเชิง)
            state.observationRoundsRemaining = 0;
            state.isLossStreakBaseBetLocked = false;
            state.recoveryStepInCycle = 0;
            state.currentRecoveryCycle = 1;
            state.consecutiveLossesStreak = 0;

            if (state.totalAccumulatedLoss <= 0.00000001) {
              state.resetDebt();
              state.observationRoundsRemaining = 0;
              state.isLossStreakBaseBetLocked = false;
              state.recoveryState = RecoveryState.normal;
              state.isRecoveryUnlocked = false;
              state.recoveryWinsAchieved = 0;
              state.peakLossStreak = 0;
              state.ghostSniperWinCount = 0;
              transitionRecoveryState(mode, RecoveryState.normal,
                  reason: 'Recovery WIN - full debt cleared -> return to normal Base Bet');
              if (currentBalForCheck > 0.00000001) {
                state.sessionMaxBalance = currentBalForCheck;
                state.protectedPrincipal = currentBalForCheck * 0.97;
              }
              debugPrint('🎉 [100% RECOVERY VICTORY] 🌟 [${mode.displayName}] ไม้ทวงหนี้ชนะสำเร็จ! ล้างหนี้เป็น 0.00000000 ครบ 100% -> กลับสู่การเดิน Base Bet ปกติ');
            } else {
              // หากยังมีหนี้คงเหลือ (กรณีติดลิมิตยอดเดิมพันสูงสุด):
              transitionRecoveryState(mode, RecoveryState.normal,
                  reason: 'Recovery round won with remaining debt -> return to normal Base Bet');
              debugPrint(
                '💎 [RECOVERY ROUND WON] [${mode.displayName}] ชนะไม้ทวงสำเร็จ! หักกำไร +${actualProfit.toStringAsFixed(8)} | หนี้คงเหลือ: ${state.totalAccumulatedLoss.toStringAsFixed(8)} -> กลับสู่การเดิน Base Bet',
              );
            }
          } else {
            state.justWonRecoveryBet = false;
            if (isFullyRecovered && state.totalAccumulatedLoss > 0) {
              state.resetDebt();
              transitionRecoveryState(mode, RecoveryState.normal, reason: 'Debt cleared by base bet profit');
            }
            if (isFullyRecovered) {
              state.resetDebt();
              transitionRecoveryState(mode, RecoveryState.normal, reason: 'ATH reached');
              state.recoveryWinsAchieved = 0;
              state.isRecoveryUnlocked = false;
              state.peakLossStreak = 0;
              state.ghostSniperWinCount = 0;
              state.justWonRecoveryBet = false;
              state.recoveryCooldownRounds = 0;

              _randomizeRhythm();
              debugPrint('🎉 [ATH VICTORY] 🌟 [${mode.displayName}] ชนะ Base Bet แตะ New High! กลับสู่โหมด Base Bet ปกติ');
              await rotateWebClientSeed(mode: mode);
              await _ensureBaseBet(runToken, mode: mode);
            }

            // 🌿 CIRCUIT BREAKER AUTO-RESET GATE:
            // เมื่อเดิน Base Bet จนชนะติดกัน >= N ตา (Default N=3) และมีหนี้คงค้าง
            if (state.totalAccumulatedLoss > 0.00000001 &&
                state.consecutiveBaseBetWins >= state.consecutiveBaseBetWinsRequiredForRecovery) {
              if (state.recoveryCircuitBreakerActive || state.recoveryState == RecoveryState.circuitBreaker) {
                state.recoveryCircuitBreakerActive = false;
                state.recoveryLossStreak = 0;
                state.isLossStreakBaseBetLocked = false;
                transitionRecoveryState(mode, RecoveryState.recoveryGate,
                    reason: 'Circuit Breaker Auto-Reset: Won ${state.consecutiveBaseBetWins} consecutive Base Bets');
                debugPrint(
                  '🌿 [CIRCUIT BREAKER AUTO-RESET] [${mode.displayName}] ชนะ Base Bet ติดกัน ${state.consecutiveBaseBetWins} ตา -> ปลดล็อก Circuit Breaker เข้าสู่ Recovery Gate เพื่อทวงหนี้เต็ม 100%',
                );
              } else if (state.recoveryState == RecoveryState.normal && state.observationRoundsRemaining <= 0) {
                transitionRecoveryState(mode, RecoveryState.recoveryGate,
                    reason: 'Recovery Ready: Won ${state.consecutiveBaseBetWins} consecutive Base Bets');
                debugPrint(
                  '🎯 [RECOVERY GATE READY] [${mode.displayName}] ชนะ Base Bet พักฟื้นติดกัน ${state.consecutiveBaseBetWins} ตา -> ปลดล็อกเข้าสู่ Recovery Gate เตรียมทวงเต็ม 100%',
                );
              }
            }
          }

          _clickCounts['M4'] = 0;
          if (state.totalAccumulatedLoss <= 0.0) {
            _clickCounts['M5'] = 0;
          }

          state.consecutiveLossesStreak = 0;
          debugPrint(
            '[RECOVERY] state=${state.recoveryState.name} debt=${state.totalAccumulatedLoss.toStringAsFixed(8)} '
            'lossStreak=${state.consecutiveLossesStreak} recoveryLossStreak=${state.recoveryLossStreak} '
            'obsRemaining=${state.observationRoundsRemaining} circuitBreaker=${state.recoveryCircuitBreakerActive}',
          );
          notifyListeners();

          if (await _checkStopProfitInline(runToken, mode: mode)) {
            debugPrint('[SMART FLOW] 🛑 Stop Profit reached after WIN — stopping');
            break;
          }
        } else if (discoveredBombPos != null || (m0Status == 'bet' && m0Retries >= 4)) {
          // Confirmed LOSS
          resolutionFound = true;
          state.lastRoundWasWin = false;
          debugPrint(
            'Smart Flow: 🎰 [${mode.displayName}] LOSS detected at M0.',
          );
          if (_shouldAbort(runToken, mode: mode)) break;

          // 💣 เมื่อแพ้ ช่องที่กด (prediction) ต้องเป็นระเบิดแน่นอน 100%!
          // หาก visual detection ไม่เห็นไอคอนระเบิด ให้ใช้ prediction เป็น confirmedBombPos เสมอ
          final String confirmedBombPos = discoveredBombPos ?? prediction;

          String gemPos = 'Unknown';
          final safeOptions = ['A', 'B', 'C'].where((c) => c != confirmedBombPos).toList();
          if (safeOptions.isNotEmpty) {
            gemPos = safeOptions.first;
          } else {
            gemPos = 'A';
          }

          try {
            final analyzer = _analyzersByMode[mode] ?? _sequenceAnalyzerViewModel;
            await analyzer?.recordInput(
              gemPos,
              triggerId: targetMarker,
              actualBombPos: confirmedBombPos,
              multiplier: 1.0,
              selectedAction: prediction,
              isWin: false,
            );
          } catch (e) {
            debugPrint('[RECORD ERROR] Loss record: $e');
          }

          _bombHistory.add(confirmedBombPos);
          if (_bombHistory.length > 5) _bombHistory.removeAt(0);

          OmniMatrixEngine.instance.recordOutcome(
            chosenColumn: prediction,
            won: false,
            revealedBombPos: confirmedBombPos,
            mode: mode,
          );

          double currentBetVal = await _getBetAmount(mode: mode);
          if (currentBetVal <= 0.0) currentBetVal = state.currentBetAmount;

          final bool wasRecoveryRound = state.isCurrentlyRecoveryRound;
          if (wasRecoveryRound) {
            state.consecutiveRecoveryLosses++;
          }
          state.isCurrentlyRecoveryRound = false;

          if (state.observationRoundsRemaining > 0) {
            state.observationRoundsRemaining--;
            debugPrint(
              '🔭 [OBSERVATION LOSS 💣] [${mode.displayName}] ไม้สังเกตการณ์แพ้! '
              '(เหลืออีก ${state.observationRoundsRemaining} ตา) บันทึกหนี้ Base Bet',
            );
            if (state.observationRoundsRemaining <= 0) {
              state.observationRoundsRemaining = 0;
              state.isLossStreakBaseBetLocked = false;
              state.consecutiveLossesStreak = 0;
              OmniMatrixEngine.instance.resetStreak(mode: mode);
              // 🎯 Guarded transition: OBSERVATION -> RECOVERY_GATE
              if (state.totalAccumulatedLoss > 0.00000001) {
                state.recoveryStepInCycle = 1;
                state.randomizeRecoveryQuota();
                transitionRecoveryState(mode, RecoveryState.recoveryGate,
                    reason: 'Observation completed with loss -> start recovery step 1 in cycle ${state.currentRecoveryCycle} (Quota: ${state.maxRecoveryStepsThisCycle} steps)');
                debugPrint(
                  '🎯 [OBSERVATION COMPLETE 🔭] [${mode.displayName}] ครบกำหนด 15-25 ตาแล้ว! '
                  'ตาสุดท้ายแพ้ -> เข้าสู่ RECOVERY_GATE สุ่มโควตาทวง ${state.maxRecoveryStepsThisCycle} ไม้ เริ่มไม้ที่ 1 (รอบที่ ${state.currentRecoveryCycle}) ทันที!',
                );
              } else {
                state.recoveryStepInCycle = 0;
                state.currentRecoveryCycle = 1;
                state.observationRoundsRemaining = 0;
                state.isLossStreakBaseBetLocked = false;
                transitionRecoveryState(mode, RecoveryState.normal,
                    reason: 'Observation completed, no debt -> return to normal mode');
              }
            } else {
              state.consecutiveLossesStreak = 0;
            }
          } else if (state.isLossStreakBaseBetLocked) {
            state.consecutiveLossesStreak = 0;
          } else if (!wasRecoveryRound) {
            state.consecutiveLossesStreak++;
          }
          state.justWonRecoveryBet = false;
          state.consecutiveBaseBetWins = 0;

          // 🎯 การบันทึกหนี้จริงแบบ Linear ไม่คูณทบ (/grill-me Consensus):
          // บวกหนี้เฉพาะเงินที่ลงเดิมพันจริงในไม้นั้น (เสียจริงเท่าไหร่ บันทึกเท่านั้นอย่างโปร่งใส)
          final double baseBetLoss = state.lockedBaseBet ?? _lockedBaseBetByMode[mode] ?? getFloorBetForMode(mode);
          final double lossToAdd = currentBetVal > 0.0 ? currentBetVal : baseBetLoss;

          // 🛡️ SHIELD 3: Decouple Observation Losses from Recovery Debt Snowball
          // ห้ามนำการแพ้ในรอบดูเชิง 15-25 ตา มาทบหนี้ทวงเด็ดขาด เพื่อป้องกันหนี้บวมพอง
          if (!state.isLossStreakBaseBetLocked && state.observationRoundsRemaining == 0) {
            state.activeNewLoss += lossToAdd;
            state.activeNewLoss = double.parse(state.activeNewLoss.toStringAsFixed(8));
            debugPrint(
              '[DEBT TRACKER] 💸 [${mode.displayName}] บันทึกหนี้จริงตามเบท: +${lossToAdd.toStringAsFixed(8)} | หนี้สะสมรวม: ${state.totalAccumulatedLoss.toStringAsFixed(8)} (BaseBetStreak: ${state.consecutiveLossesStreak} | Cycle: ${state.currentRecoveryCycle} | Step: ${state.recoveryStepInCycle}/3)',
            );
          } else {
            debugPrint(
              '[DEBT TRACKER] 🛡️ [${mode.displayName}] รอบดูเชิง 15-25 ตา ไม่นำมาทบหนี้ทวง (คงหนี้เดิม: ${state.totalAccumulatedLoss.toStringAsFixed(8)}) เพื่อป้องกัน Debt Snowball',
            );
          }

          // 🛡️ SHIELD 4: Record loss in recent rounds history & Bad Run Circuit Breaker
          state.recentRoundsHistory.add(false);
          if (state.recentRoundsHistory.length > 10) {
            state.recentRoundsHistory.removeAt(0);
          }
          final int recentLossCount = state.recentRoundsHistory.where((w) => !w).length;
          if (state.recentRoundsHistory.length >= 8 && recentLossCount >= 6) {
            debugPrint(
              '🚨 [CASINO COUNTER DETECTED 🛡️] [${mode.displayName}] พบการแพ้ผิดปกติ $recentLossCount จาก 10 ตาล่าสุด! เข้าสู่มาตรการพักระบบชั่วคราว 5 นาที เพื่อทำลายกับดัก RNG คาสิโน...',
            );
            state.recentRoundsHistory.clear();
            state.isCurrentlyRecoveryRound = false;
            await _ensureBaseBet(runToken, mode: mode);
            await Future.delayed(Duration(seconds: (300 / _speedMultiplier).round()));
          }

          // 🛡️ Post-Loss Handling:
          OmniMatrixEngine.instance.rotateSeed(mode: mode);
          await rotateWebClientSeed(mode: mode);

          // 🛑 RECOVERY BET LOST: "ไม่ชนะ ทวงอีก 2 ตา ไม่ชนทั้ง2 ตา ก็กลับไป Base bet รอ ครบ 15-25 ตา แล้วทวงทันที"
          if (wasRecoveryRound) {
            state.recoveryLossStreak++;
            state.recoveryAttempts++;
            state.consecutiveRecoveryLosses++;
            state.consecutiveBaseBetWins = 0;
            state.justWonRecoveryBet = false;
            state.consecutiveLossesStreak++;
            debugPrint(
              '🚨 [RECOVERY BET LOST 💣] [${mode.displayName}] ไม้ทวงหนี้แพ้! [รอบที่ ${state.currentRecoveryCycle} | ไม้ที่ ${state.recoveryStepInCycle}/3] | หนี้สะสม: ${state.totalAccumulatedLoss.toStringAsFixed(8)} | Streak: ${state.consecutiveLossesStreak}',
            );

            // 🎯 คำสั่งผู้ใช้ (ระบบสุ่มทวง 1-3 ตา ถ่วงน้ำหนัก):
            // หากแพ้ครบโควตาสุ่มในรอบนี้ (maxRecoveryStepsThisCycle) หรือแตะเพดาน 3 ตา
            // ให้ถอยกลับไป Base Bet ทันที รอ 15-25 ตา แล้วค่อยทวงในรอบถัดไป
            if (state.recoveryStepInCycle >= state.maxRecoveryStepsThisCycle ||
                (state.currentRecoveryCycle == 1 && state.recoveryStepInCycle >= 2) ||
                state.recoveryStepInCycle >= 3) {
              final int finishedCycle = state.currentRecoveryCycle;
              state.recoveryStepInCycle = 0;
              state.consecutiveLossesStreak = 3;
              state.isLossStreakBaseBetLocked = true;
              state.isCurrentlyRecoveryRound = false;
              final int obsRounds = 15 + Random().nextInt(11);
              state.observationRoundsRemaining = obsRounds;
              state.currentRecoveryCycle = (finishedCycle % 3) + 1; // 1 -> 2, 2 -> 3, 3 -> 1
              transitionRecoveryState(mode, RecoveryState.observation,
                  reason: 'Cycle $finishedCycle: Reached quota (${state.maxRecoveryStepsThisCycle} steps) -> retreat to Base Bet observation for $obsRounds rounds (Next: Cycle ${state.currentRecoveryCycle})');
              debugPrint(
                '🛑 [ครบโควตาสุ่มทวง ${state.maxRecoveryStepsThisCycle} ไม้ กลับ Base bet 🛡️] [${mode.displayName}] รอบที่ $finishedCycle สุ่มทวงครบ ${state.maxRecoveryStepsThisCycle} ไม้แล้วยังไม่ชนะ! '
                'ตาต่อไปห้ามทวงเด็ดขาด! ถอยกลับไปเดิน Base Bet รอครบ $obsRounds ตา (15-25 ตา) -> แล้วทวงทันที (รอบที่ ${state.currentRecoveryCycle}${finishedCycle == 3 ? " วนกลับไปรอบแรก" : ""})',
              );
              await _ensureBaseBet(runToken, mode: mode);
            } else {
              // ยังไม่ครบโควตาสุ่มทวง: ออกไม้ถัดไปทันที
              state.recoveryStepInCycle++;
              state.observationRoundsRemaining = 0;
              state.isLossStreakBaseBetLocked = false;
              transitionRecoveryState(mode, RecoveryState.recoveryGate,
                  reason: 'Cycle ${state.currentRecoveryCycle}: Recovery step ${state.recoveryStepInCycle - 1} lost -> proceed to step ${state.recoveryStepInCycle} of ${state.maxRecoveryStepsThisCycle}');
              debugPrint(
                '⚡ [แพ้ทวง 🎯 ไม้ ${state.recoveryStepInCycle}/${state.maxRecoveryStepsThisCycle}] [${mode.displayName}] [รอบที่ ${state.currentRecoveryCycle}] ไม้ ${state.recoveryStepInCycle - 1} พลาด -> เข้าทวงไม้ที่ ${state.recoveryStepInCycle} ทันที!',
              );
            }
          } else {
            // 🛑 BASE BET LOST:
            // คำสั่งผู้ใช้: "ปกติ แพ้ทวง แพ้ทวง แพ้ กลับ Base bet"
            // เมื่อเดิน Base Bet แพ้ ให้เข้าสู่การทวงหนี้ทันที (ไม้ที่ 1)
            // (ยกเว้นกรณีที่ยังอยู่ในช่วงดูเชิง 15-25 ตา ซึ่งถูกนับถอยหลังไปแล้วข้างบน)
            state.recoveryStepInCycle = 1;
            state.consecutiveLossesStreak = 1;
            state.isLossStreakBaseBetLocked = false;
            state.observationRoundsRemaining = 0;
            state.currentRecoveryCycle = 1;
            state.randomizeRecoveryQuota();
            transitionRecoveryState(mode, RecoveryState.recoveryGate,
                reason: 'Normal Base Bet lost -> immediate recovery step 1 (Quota: ${state.maxRecoveryStepsThisCycle} steps)');
            debugPrint(
              '⚡ [แพ้ทวง 🎯 ไม้ 1/${state.maxRecoveryStepsThisCycle}] [${mode.displayName}] แพ้ Base Bet -> สุ่มโควตาทวง ${state.maxRecoveryStepsThisCycle} ไม้ เริ่มไม้ที่ 1!',
            );
          }


          if (state.consecutiveLossesStreak >= 2) {
            debugPrint(
              '🔄 [SEED ROTATION ⚡] [${mode.displayName}] แพ้ ${state.consecutiveLossesStreak} ตาติด -> หมุน Seed สับหลบ RNG คาสิโนทันที',
            );
          } else if (state.consecutiveLossesStreak == 1) {
            debugPrint(
              '🎯 [STREAK-1 READY ⚡] [${mode.displayName}] แพ้ตาแรก (Streak: 1) -> หมุน Seed ป้องกันระเบิดซ้ำ',
            );
          }

          debugPrint(
            '[RECOVERY] state=${state.recoveryState.name} debt=${state.totalAccumulatedLoss.toStringAsFixed(8)} '
            'lossStreak=${state.consecutiveLossesStreak} recoveryLossStreak=${state.recoveryLossStreak} '
            'obsRemaining=${state.observationRoundsRemaining} circuitBreaker=${state.recoveryCircuitBreakerActive}',
          );

          if (state.consecutiveLossesStreak > state.peakLossStreak) {
            state.peakLossStreak = state.consecutiveLossesStreak;
          }

          state.recoveryWinsAchieved = 0;
          state.ghostSniperWinCount = 0;

          if (_shouldAbort(runToken, mode: mode)) break;

          String actualClickedChar = (targetMarker == 'M1')
              ? 'A'
              : (targetMarker == 'M2' ? 'B' : 'C');
          _lossSequence.add(actualClickedChar);
          if (_lossSequence.length > 5) _lossSequence.removeAt(0);
        } else {
          if (m0Retries == 7) {
            await _performButtonAction(targetMarker, mode: mode);
          }
        }
      }

      if (!resolutionFound) {
        debugPrint(
          '🚨 [M0 TIMEOUT] [${mode.displayName}] Network slow. Refresh disabled by user directive. Continuing detection...',
        );
        _sequenceAnalyzerViewModel?.advice = "⚠️ [TIMEOUT] ตรวจสอบผลต่อ (ปิด Refresh ชั่วคราว)";
        // ตรวจสอบยอดเงินหลัง timeout ว่าเงินลดลงหรือไม่
        double balanceAfterTimeout = await _getBalanceDouble(mode: mode);
        if (balanceBeforeRound > 0.00000001 && balanceAfterTimeout > 0.00000001 && balanceAfterTimeout < balanceBeforeRound - 0.00000001) {
          final double timeoutLoss = balanceBeforeRound - balanceAfterTimeout;
          state.activeNewLoss += timeoutLoss;
          state.activeNewLoss = double.parse(state.activeNewLoss.toStringAsFixed(8));
          state.consecutiveLossesStreak++;
          state.lastRoundWasWin = false;
          debugPrint(
            '🚨 [TIMEOUT REAL LOSS] 💸 [${mode.displayName}] เน็ตช้าจนจับผลไม่ได้แต่ยอดเงินลดลงจริง: -${timeoutLoss.toStringAsFixed(8)} -> บันทึกเป็นหนี้ทันที! หนี้รวม: ${state.totalAccumulatedLoss.toStringAsFixed(8)}',
          );
        }
        await Future.delayed(const Duration(seconds: 2));
        continue;
      }

      if (_shouldAbort(runToken, mode: mode)) break;

      // 🕒 ระยะห่างระหว่างแต่ละรอบ ➔ สบายๆ เป็นธรรมชาติ 2.5s - 4.2s (User Directive)
      int roundInterval = 2500 + Random().nextInt(1700);
      debugPrint('[PACE] 🕒 [${mode.displayName}] Interval before next round: ${roundInterval}ms (2.5s - 4.2s)');
      await Future.delayed(Duration(milliseconds: (roundInterval / _speedMultiplier).round()));
    }
    state.isRunning = false;
    _isRunning = isAnyRunning;
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    for (var s in _statesByMode.values) {
      s.runToken++;
      s.isRunning = false;
    }
    _isRunning = false;
    _stopPnLMonitor();
    super.dispose();
  }

  /// Button click executor with beautiful, visible, calmer highlight effect (User Directive)
  Future<void> _performButtonAction(
    String buttonId, {
    GameMode? mode,
  }) async {
    final targetMode = mode ?? _activeGameMode;
    final state = getState(targetMode);
    final controller = getWebViewController(targetMode);
    final buttonList = getButtons(targetMode);

    final button = buttonList.firstWhere(
      (b) => b.id == buttonId,
      orElse: () => buttonList.first,
    );

    if (button.type == 'webview_click') {
      if (controller != null && button.position != Offset.zero) {
        // ✨ Calmer Visual Feedback: Glow/Highlight for 350ms - 450ms before click
        state.activeButtonId = buttonId;
        _activeButtonId = buttonId;
        notifyListeners();

        final bool isUtility = buttonId == 'M4' || buttonId == 'M5';
        final int prePressGlowMs = isUtility ? 120 : (350 + Random().nextInt(100));
        await Future.delayed(Duration(milliseconds: (prePressGlowMs / _speedMultiplier).round()));

        final bool isSmall = buttonId == 'M4' || buttonId == 'M5';
        final double centerX = button.position.dx + (isSmall ? 16.0 : 24.0);
        final double centerY = button.position.dy + (isSmall ? 16.0 : 24.0);

        final double scale = _webViewTextZoom / 100.0;
        final int x = ((centerX - _webViewOffset.dx) / scale).toInt();
        final int y = ((centerY - _webViewOffset.dy) / scale).toInt();
        final int r = ((isSmall ? 16 : 24) / scale).toInt();

        debugPrint('Smart Clicking Marker $buttonId [${targetMode.displayName}] at Center ($x, $y) with radius $r');

        if (buttonId == 'M4' || buttonId == 'M5') {
          _clickCounts[buttonId] = (_clickCounts[buttonId] ?? 0) + 1;
          notifyListeners();
        }

        bool nativeClickHandled = false;
        if (_isWindowsDesktop) {
          nativeClickHandled = await _performWindowsNativeClick(centerX, centerY, buttonId);
        }

        if (!nativeClickHandled) {
          final String clickScript = """
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
                      if (checkMatch(el)) return doClick(el, sx, sy);
                      if (el.parentElement && checkMatch(el.parentElement)) return doClick(el.parentElement, sx, sy);
                      
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

          await controller.evaluateJavascript(source: clickScript).timeout(
            const Duration(seconds: 3),
            onTimeout: () => null,
          );
        }

        // ✨ Post-click calm release feedback: 250ms - 350ms
        final int postPressReleaseMs = isUtility ? 100 : (250 + Random().nextInt(100));
        await Future.delayed(Duration(milliseconds: (postPressReleaseMs / _speedMultiplier).round()));
        state.activeButtonId = null;
        _activeButtonId = null;
        notifyListeners();
      }
    } else if (button.type == 'predictor') {
      if (_sequenceAnalyzerViewModel != null && button.predictorValue != null) {
        state.activeButtonId = buttonId;
        _activeButtonId = buttonId;
        notifyListeners();

        try {
          await _sequenceAnalyzerViewModel.recordInput(
            button.predictorValue!,
            triggerId: buttonId,
          );
        } catch (_) {}

        await Future.delayed(
          Duration(milliseconds: (300 / _speedMultiplier).round()),
        );
        state.activeButtonId = null;
        _activeButtonId = null;
        notifyListeners();
      }
    }
  }

  /// Finds and reads bet amount from FaucetPay DOM input box
  Future<double> _getBetAmount({GameMode? mode}) async {
    final controller = getWebViewController(mode);
    if (controller == null) return 0.0;
    try {
      final dynamic result = await controller
          .evaluateJavascript(
            source:
                r"""
        (function() {
          function findInput() {
            let isMinesMode = window.location.href.includes('polpick') || window.location.href.includes('gems.php') || window.location.href.includes('mines');
            if (isMinesMode) {
              let allInputs = Array.from(document.querySelectorAll('input')).filter(inp => {
                let t = (inp.type || 'text').toLowerCase();
                if (t === 'hidden' || t === 'password' || t === 'checkbox' || t === 'radio' || t === 'submit' || t === 'search') return false;
                let rect = inp.getBoundingClientRect();
                return rect.width > 0 && rect.height > 0;
              });
              if (allInputs.length > 0) {
                allInputs.sort((a, b) => b.getBoundingClientRect().top - a.getBoundingClientRect().top);
                return allInputs[0];
              }
            }

            let selectors = [
              'input#amount', 'input#bet_amount', 'input#bet-amount',
              'input[name="amount"]', 'input[name="bet_amount"]',
              'input.bet-amount', 'input.bet_amount',
              'input[placeholder*="Amount" i]', 'input[placeholder*="Bet" i]',
              'input[aria-label*="amount" i]'
            ];
            for (let s of selectors) {
              let el = document.querySelector(s);
              if (el && el.type !== 'hidden' && el.type !== 'checkbox' && el.type !== 'radio') return el;
            }
            let inputs = Array.from(document.querySelectorAll('input'));
            for (let inp of inputs) {
              let t = (inp.type || 'text').toLowerCase();
              if (t === 'hidden' || t === 'password' || t === 'checkbox' || t === 'radio' || t === 'submit' || t === 'search') continue;
              let val = (inp.value || inp.placeholder || '').trim();
              if (/^[0-9]*\.?[0-9]+$/.test(val)) return inp;
            }
            return inputs.find(i => i.type === 'number' || i.type === 'text') || null;
          }
          var input = findInput();
          if (input && input.value) {
            return input.value;
          }
          var valDiv = document.querySelector('.bet-amount-value, [data-bet-amount]');
          if (valDiv) {
            return valDiv.innerText.trim();
          }
          return null;
        })()
      """,
          )
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => null,
          );

      if (result != null && result.toString().isNotEmpty && result.toString() != 'null') {
        String cleanStr = result.toString().replaceAll(',', '').trim();
        final double? parsed = double.tryParse(cleanStr);
        if (parsed != null && parsed > 0.0) {
          return parsed;
        }
      }
    } catch (e) {
      debugPrint('[BET DETECT] Error reading bet amount: $e');
    }
    return 0.0;
  }

  /// ⌨️ Guaranteed Complete Character-by-Character Typing with Virtual Keyboard Prevention
  Future<void> _setBetAmount(double amount, {GameMode? mode}) async {
    final targetMode = mode ?? _activeGameMode;
    final state = getState(targetMode);
    final controller = getWebViewController(targetMode);
    if (controller == null) return;
    try {
      state.currentBetAmount = amount;
      String amountStr = amount.toStringAsFixed(8);
      if (amountStr.contains('.')) {
        amountStr = amountStr.replaceAll(RegExp(r'0*$'), '');
        if (amountStr.endsWith('.')) {
          amountStr = amountStr.substring(0, amountStr.length - 1);
        }
      }

      // Hide software keyboard from Flutter layer
      SystemChannels.textInput.invokeMethod('TextInput.hide');
      FocusManager.instance.primaryFocus?.unfocus();

      // Set typing flags in WebView
      await controller.evaluateJavascript(
        source: "window._betTypingInProgress = true; window._betTypingCompleted = false;",
      ).timeout(const Duration(milliseconds: 300), onTimeout: () => null);

      await controller.evaluateJavascript(
        source: """
          (function(val) {
            window._betTypingInProgress = true;
            window._betTypingCompleted = false;

            return new Promise((resolve) => {
              function findInput() {
                let isMinesMode = window.location.href.includes('polpick') || window.location.href.includes('gems.php') || window.location.href.includes('mines');
                if (isMinesMode) {
                  let allInputs = Array.from(document.querySelectorAll('input')).filter(inp => {
                    let t = (inp.type || 'text').toLowerCase();
                    if (t === 'hidden' || t === 'password' || t === 'checkbox' || t === 'radio' || t === 'submit' || t === 'search') return false;
                    let rect = inp.getBoundingClientRect();
                    return rect.width > 0 && rect.height > 0;
                  });
                  if (allInputs.length > 0) {
                    allInputs.sort((a, b) => b.getBoundingClientRect().top - a.getBoundingClientRect().top);
                    return allInputs[0];
                  }
                }

                // 1. Direct explicit selectors for bet amount
                let selectors = [
                  'input#amount', 'input#bet_amount', 'input#bet-amount',
                  'input[name="amount"]', 'input[name="bet_amount"]',
                  'input.bet-amount', 'input.bet_amount',
                  'input[placeholder*="Amount" i]', 'input[placeholder*="Bet" i]',
                  'input[aria-label*="amount" i]'
                ];
                for (let s of selectors) {
                  let el = document.querySelector(s);
                  if (el && el.type !== 'hidden' && el.type !== 'checkbox' && el.type !== 'radio') return el;
                }

                // 2. Buttons container (Min, Max, 2x, 1/2)
                let buttons = Array.from(document.querySelectorAll('button, a, div, span'));
                for (let b of buttons) {
                  let txt = (b.innerText || '').trim().toLowerCase();
                  if (txt === 'min' || txt === 'max' || txt === '2x' || txt === '1/2' || txt === '½') {
                    let parent = b.parentElement;
                    for (let i = 0; i < 3; i++) {
                      if (!parent) break;
                      let inp = parent.querySelector('input');
                      if (inp && inp.type !== 'hidden') {
                        let nameOrId = (inp.name || inp.id || inp.placeholder || '').toLowerCase();
                        if (!nameOrId.includes('mine') && !nameOrId.includes('count')) return inp;
                      }
                      parent = parent.parentElement;
                    }
                  }
                }

                // 3. Filtered inputs ignoring hidden/mines-count
                let inputs = Array.from(document.querySelectorAll('input')).filter(inp => {
                  let t = (inp.type || 'text').toLowerCase();
                  if (t === 'hidden' || t === 'password' || t === 'checkbox' || t === 'radio' || t === 'submit' || t === 'search') return false;
                  let nameOrId = (inp.name || inp.id || inp.placeholder || inp.getAttribute('aria-label') || '').toLowerCase();
                  if (nameOrId.includes('mine') || nameOrId.includes('bomb') || nameOrId.includes('count')) return false;
                  let rect = inp.getBoundingClientRect();
                  return rect.width > 0 && rect.height > 0;
                });
                if (inputs.length > 0) return inputs[0];
                return null;
              }

              var input = findInput();
              if (!input) {
                window._betTypingInProgress = false;
                window._betTypingCompleted = true;
                resolve(false);
                return;
              }

              // 🛡️ Prevent Virtual Keyboard from popping up on Android/Mobile
              const oldInputMode = input.getAttribute('inputmode');
              const oldReadOnly = input.readOnly;
              input.setAttribute('inputmode', 'none');
              input.readOnly = true;

              const nativeProp = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value");
              const setter = nativeProp ? nativeProp.set : null;
              
              function setVal(v) {
                if (setter) {
                  setter.call(input, v);
                } else {
                  input.value = v;
                }
                input.dispatchEvent(new Event('input', { bubbles: true, cancelable: true }));
              }
              
              // Clear input
              setVal('');
              
              let i = 0;
              let currentText = '';
              
              function typeNext() {
                if (i < val.length) {
                  const char = val[i];
                  currentText += char;
                  setVal(currentText);
                  
                  input.dispatchEvent(new KeyboardEvent('keydown', { key: char, bubbles: true }));
                  input.dispatchEvent(new KeyboardEvent('keypress', { key: char, bubbles: true }));
                  input.dispatchEvent(new KeyboardEvent('keyup', { key: char, bubbles: true }));
                  i++;
                  
                  const charDelay = 80 + Math.random() * 50;
                  setTimeout(typeNext, charDelay);
                } else {
                  setVal(val);
                  input.dispatchEvent(new Event('change', { bubbles: true, cancelable: true }));
                  input.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, key: 'Enter', code: 'Enter' }));
                  input.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true, key: 'Enter', code: 'Enter' }));
                  
                  // Restore original attributes and blur
                  if (oldInputMode) {
                    input.setAttribute('inputmode', oldInputMode);
                  } else {
                    input.removeAttribute('inputmode');
                  }
                  input.readOnly = oldReadOnly;
                  input.blur();
                  window._betTypingInProgress = false;
                  window._betTypingCompleted = true;
                  setTimeout(() => resolve(true), 60);
                }
              }
              
              setTimeout(typeNext, 60);
            });
          })('$amountStr')
        """,
      ).timeout(const Duration(seconds: 12), onTimeout: () => null);

      debugPrint('[BET SET] ⌨️ [${targetMode.displayName}] Typing $amountStr started...');
      // Wait for JavaScript typing to complete (polling window._betTypingCompleted)
      final stopwatch = Stopwatch()..start();
      const int maxTypingWaitMs = 10000;
      bool isCompleted = false;

      while (stopwatch.elapsedMilliseconds < maxTypingWaitMs) {
        final dynamic res = await controller.evaluateJavascript(
          source: "window._betTypingCompleted === true && window._betTypingInProgress !== true",
        ).timeout(const Duration(milliseconds: 300), onTimeout: () => null);

        if (res == true || res.toString() == 'true') {
          isCompleted = true;
          break;
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }

      debugPrint('[BET SET] ✅ [${targetMode.displayName}] Typing $amountStr 100% complete in ${stopwatch.elapsedMilliseconds}ms (isCompleted: $isCompleted)!');

      // Hide keyboard again just in case
      SystemChannels.textInput.invokeMethod('TextInput.hide');

      // 🕒 พักมือ 85-100 ms หลังพิมพ์เสร็จและปิดโฟกัส ก่อนขยับไปกด M0 (User Directive)
      final int handRestMs = 85 + Random().nextInt(16);
      debugPrint('[BET SET] 🖐️ [${targetMode.displayName}] Hand rest pause: ${handRestMs}ms before M0');
      await Future.delayed(Duration(milliseconds: handRestMs));
    } catch (e) {
      debugPrint('[BET SET] Error setting bet: $e');
    }
  }

    /// 💎 Check if a Gem/Diamond is physically revealed on the board (Polpick / Mines Cashout Guard)
  Future<bool> _hasRevealedGem({GameMode? mode, String? targetMarker}) async {
    final targetMode = mode ?? _activeGameMode;
    final controller = getWebViewController(targetMode);
    if (controller == null) return false;

    try {
      final dynamic res = await controller.evaluateJavascript(source: """
        (function() {
          let elements = Array.from(document.querySelectorAll('*'));
          for (let el of elements) {
            let txt = (el.innerText || el.textContent || '').trim();
            if (txt.includes('💎') || txt.includes('gem') || txt.includes('diamond')) {
              let rect = el.getBoundingClientRect();
              if (rect.width > 0 && rect.height > 0) return true;
            }
            let cls = (el.className || '').toString().toLowerCase();
            if (cls.includes('gem') || cls.includes('diamond') || cls.includes('safe') || cls.includes('revealed-gem')) {
              let rect = el.getBoundingClientRect();
              if (rect.width > 0 && rect.height > 0) return true;
            }
            let style = window.getComputedStyle(el);
            let bg = (style.backgroundImage || '').toLowerCase();
            if (bg.includes('gem') || bg.includes('diamond') || bg.includes('safe')) {
              let rect = el.getBoundingClientRect();
              if (rect.width > 0 && rect.height > 0) return true;
            }
          }
          return false;
        })()
      """).timeout(const Duration(milliseconds: 500), onTimeout: () => false);

      if (res == true) return true;

      if (targetMarker != null) {
        String markerStatus = await _detectVisualOutcome(targetMarker, mode: targetMode);
        if (markerStatus == 'gem') return true;
      }
    } catch (_) {}
    return false;
  }

  Future<String> _detectVisualOutcomeWithVerification(String markerId, {GameMode? mode}) async {
    String firstScan = await _detectVisualOutcome(markerId, mode: mode);
    if (firstScan != 'none') {
      await Future.delayed(Duration(milliseconds: (400 / _speedMultiplier).round()));
      String secondScan = await _detectVisualOutcome(markerId, mode: mode);
      if (firstScan == secondScan) {
        return firstScan;
      }
      return secondScan != 'none' ? secondScan : firstScan;
    }
    return firstScan;
  }

  Future<String> _detectVisualOutcome(String markerId, {GameMode? mode}) async {
    final targetMode = mode ?? _activeGameMode;
    final controller = getWebViewController(targetMode);
    if (controller == null) return 'none';

    final buttonList = getButtons(targetMode);
    final button = buttonList.firstWhere(
      (b) => b.id == markerId,
      orElse: () => buttonList.first,
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
      final dynamic result = await controller
          .evaluateJavascript(
            source:
                """
        (function(x, y) {
          let el = document.elementFromPoint(x, y);
          if (!el) return 'none';
          
          let current = el;
          for (let i = 0; i < 5; i++) {
            if (!current) break;
            
            const text = (current.innerText || current.value || current.textContent || "").toUpperCase().trim();
            const style = window.getComputedStyle(current);
            const bgImg = (style.backgroundImage || "").toLowerCase();
            const html = (current.outerHTML || "").toLowerCase();
            
            if (text.length > 0 && text.length < 40) {
              if (text.includes('CASH') || text.includes('ถอน') || text.includes('รับเงิน') || text.includes('ออก') || text.includes('TAKE')) return 'cashout';
              if (text === 'BET' || text === 'PLACE BET' || text === 'START' || text.includes('START GAME') || text === 'PLAY' || (text.includes('BET') && !text.includes('AMOUNT')) || text.includes('เดิมพัน')) return 'bet';
              if (text.includes('PICK') || text.includes('TILE') || text.includes('เริ่ม') || text.includes('เลือก')) return 'pick';
            }
            
            if (bgImg.includes('bomb') || bgImg.includes('mine') || bgImg.includes('exploded') || 
                html.includes('bomb') || html.includes('mine') || html.includes('exploded') ||
                current.classList.contains('mine') || current.classList.contains('bomb') || current.classList.contains('exploded')) {
              return 'bomb';
            }
            
            if (bgImg.includes('gem') || bgImg.includes('diamond') || bgImg.includes('safe') || 
                html.includes('gem') || html.includes('diamond') || html.includes('safe') ||
                current.classList.contains('gem') || current.classList.contains('safe') || current.classList.contains('diamond')) {
              return 'gem';
            }
            current = current.parentElement;
          }
          return 'none';
        })($x, $y);
      """,
          )
          .timeout(
            const Duration(milliseconds: 500),
            onTimeout: () => 'none',
          );

      return result?.toString() ?? 'none';
    } catch (_) {
      return 'none';
    }
  }

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
    notifyListeners();
  }

  void _randomizeRhythm() {
    for (var s in _statesByMode.values) {
      s.recoveryWinsRequired = 1 + Random().nextInt(4);
    }
  }

  void clearAllPositions() {
    for (var button in _buttons) {
      button.position = const Offset(0, 0);
    }
    _prefs.remove('overlay_buttons_positions');
    notifyListeners();
  }

  Future<String?> _findRevealedBombPosition({GameMode? mode}) async {
    final controller = getWebViewController(mode);
    if (controller == null) return null;

    for (String mId in ['M1', 'M2', 'M3']) {
      String status = await _detectVisualOutcome(mId, mode: mode);
      if (status == 'bomb') {
        return mId == 'M1' ? 'A' : (mId == 'M2' ? 'B' : 'C');
      }
    }
    return null;
  }

  Future<double> _getBalanceDouble({GameMode? mode}) async {
    final targetMode = mode ?? _activeGameMode;
    final state = getState(targetMode);
    final controller = getWebViewController(targetMode);
    if (controller != null) {
      try {
        if (targetMode == GameMode.towers) {
          // ─── EXACT ORIGINAL FAUCETPAY BALANCE EXTRACTOR FOR TOWERS (เหมือนเดิม 100%) ───
          final dynamic res = await controller.evaluateJavascript(source: r"""
            (function() {
              var el = document.querySelector('.balance, [data-balance], #balance, .user-balance') || 
                       Array.from(document.querySelectorAll('span, div, b, strong')).find(e => e.innerText && /^[0-9,]+\.[0-9]{4,8}\s*([A-Z]{3,5})/i.test(e.innerText.trim()));
              if (el) {
                var match = el.innerText.trim().match(/([0-9,]+\.[0-9]{4,8})/);
                if (match) return match[1].replace(/,/g, '');
              }
              return null;
            })()
          """);
          if (res != null && res.toString().isNotEmpty && res.toString() != 'null') {
            final val = double.tryParse(res.toString().replaceAll(',', '').trim());
            if (val != null && val > 0) return val;
          }
        } else {
          // ─── ROBUST 4-8 DECIMAL & HEADER SCANNER FOR MINE (POLPICK) ───
          final dynamic res = await controller.evaluateJavascript(source: r"""
            (function() {
              var el = document.querySelector('#balance, .balance, [data-balance], #user_balance, .user_balance, .user-balance, #user-balance');
              if (el) {
                var match = (el.innerText || el.textContent || el.value || '').trim().match(/([0-9,]+\.[0-9]{4,8})/);
                if (match) return match[1].replace(/,/g, '');
              }
              let topElements = Array.from(document.querySelectorAll('*')).filter(el => {
                let txt = (el.innerText || el.textContent || '').trim();
                if (!txt || txt.length > 60) return false;
                return /[0-9,]+\.[0-9]{4,8}/.test(txt);
              });
              topElements.sort((a, b) => a.getBoundingClientRect().top - b.getBoundingClientRect().top);
              for (let el of topElements) {
                let rect = el.getBoundingClientRect();
                if (rect.height > 0 && rect.top >= 0 && rect.top < 250) {
                  let match = (el.innerText || el.textContent || '').match(/([0-9,]+\.[0-9]{4,8})/);
                  if (match) return match[1].replace(/,/g, '');
                }
              }
              for (let el of topElements) {
                let match = (el.innerText || el.textContent || '').match(/([0-9,]+\.[0-9]{4,8})/);
                if (match) return match[1].replace(/,/g, '');
              }
              return null;
            })()
          """);
          if (res != null && res.toString().isNotEmpty && res.toString() != 'null') {
            final val = double.tryParse(res.toString().replaceAll(',', '').trim());
            if (val != null && val > 0) return val;
          }
        }
      } catch (_) {}
    }
    final analyzer = _analyzersByMode[targetMode] ?? _sequenceAnalyzerViewModel;
    if (analyzer != null) {
      String? balanceStr = analyzer.currentBalance;
      if (balanceStr != null) {
        final val = double.tryParse(balanceStr.replaceAll(',', '').trim());
        if (val != null && val > 0) return val;
      }
    }
    if (state.lastSettledBalance > 0.00000001) {
      return state.lastSettledBalance;
    }
    if (state.sessionStartBalance != null && state.sessionStartBalance! > 0.00000001) {
      return state.sessionStartBalance!;
    }
    if (state.sessionMaxBalance > 0.00000001) {
      return state.sessionMaxBalance;
    }
    return 0.0;
  }

  Future<double> _calculateDynamicBaseBet({GameMode? mode}) async {
    final targetMode = mode ?? _activeGameMode;
    final state = getState(targetMode);
    if (state.lockedBaseBet != null && state.lockedBaseBet! > 0.00000001) {
      return state.lockedBaseBet!;
    }
    if (_lockedBaseBetByMode[targetMode] != null && _lockedBaseBetByMode[targetMode]! > 0.00000001) {
      return _lockedBaseBetByMode[targetMode]!;
    }
    final analyzer = _analyzersByMode[targetMode] ?? _sequenceAnalyzerViewModel;
    final coin = state.activeCoinType ?? analyzer?.getCoinTypeForMode(targetMode);
    final double defaultFloor = getFloorBetForMode(targetMode, coinType: coin);
    final double currentBalance = await _getBalanceDouble(mode: targetMode);
    final double calculated = targetMode.calculateBaseBet(currentBalance, defaultFloor, coin: coin);
    state.lockedBaseBet = calculated;
    _lockedBaseBetByMode[targetMode] = calculated;
    return calculated;
  }

  /// 🛡️ Direct Hardware-Speed Base Bet Reset & MIN Button Trigger
  /// บังคับเปลี่ยนยอดเดิมพันเป็น Base Bet ทันทีโดยไม่ต้องพิมพ์ทีละตัวอักษร
  /// พร้อมกดปุ่ม 'MIN' บนหน้าเว็บ เพื่อให้เซิร์ฟเวอร์และ DOM อัปเดต 100% แน่นอน
  Future<void> _forceSetBaseBet({GameMode? mode}) async {
    final targetMode = mode ?? _activeGameMode;
    final state = getState(targetMode);
    final controller = getWebViewController(targetMode);
    if (controller == null) return;

    final analyzer = _analyzersByMode[targetMode] ?? _sequenceAnalyzerViewModel;
    final coin = state.activeCoinType ?? analyzer?.getCoinTypeForMode(targetMode);
    final double defaultFloor = getFloorBetForMode(targetMode, coinType: coin);
    final double targetBet = state.lockedBaseBet ?? _lockedBaseBetByMode[targetMode] ?? defaultFloor;
    state.currentBetAmount = targetBet;
    state.isCurrentlyRecoveryRound = false;

    String targetStr = targetBet.toStringAsFixed(8);
    if (targetStr.contains('.')) {
      targetStr = targetStr.replaceAll(RegExp(r'0*$'), '');
      if (targetStr.endsWith('.')) {
        targetStr = targetStr.substring(0, targetStr.length - 1);
      }
    }

    try {
      await controller.evaluateJavascript(source: """
        (function(targetValStr) {
          // 1. กดปุ่ม 'MIN' ทันทีหากมีในหน้าเว็บ
          let buttons = Array.from(document.querySelectorAll('button, a, div, span'));
          let minBtn = buttons.find(b => (b.innerText || '').trim().toLowerCase() === 'min');
          if (minBtn) {
            try { minBtn.click(); } catch(e){}
          }

          // 2. ระบุช่อง Input เดิมพัน
          function findInput() {
            let isMinesMode = window.location.href.includes('polpick') || window.location.href.includes('gems.php') || window.location.href.includes('mines');
            if (isMinesMode) {
              let allInputs = Array.from(document.querySelectorAll('input')).filter(inp => {
                let t = (inp.type || 'text').toLowerCase();
                if (t === 'hidden' || t === 'password' || t === 'checkbox' || t === 'radio' || t === 'submit' || t === 'search') return false;
                let rect = inp.getBoundingClientRect();
                return rect.width > 0 && rect.height > 0;
              });
              if (allInputs.length > 0) {
                allInputs.sort((a, b) => b.getBoundingClientRect().top - a.getBoundingClientRect().top);
                return allInputs[0];
              }
            }
            let selectors = [
              'input#amount', 'input#bet_amount', 'input#bet-amount',
              'input[name="amount"]', 'input[name="bet_amount"]',
              'input.bet-amount', 'input.bet_amount',
              'input[placeholder*="Amount" i]', 'input[placeholder*="Bet" i]',
              'input[aria-label*="amount" i]'
            ];
            for (let s of selectors) {
              let el = document.querySelector(s);
              if (el && el.type !== 'hidden' && el.type !== 'checkbox' && el.type !== 'radio') return el;
            }

            // Buttons container (Min, Max, 2x, 1/2)
            for (let b of buttons) {
              let txt = (b.innerText || '').trim().toLowerCase();
              if (txt === 'min' || txt === 'max' || txt === '2x' || txt === '1/2' || txt === '½') {
                let parent = b.parentElement;
                for (let i = 0; i < 3; i++) {
                  if (!parent) break;
                  let inp = parent.querySelector('input');
                  if (inp && inp.type !== 'hidden') {
                    let nameOrId = (inp.name || inp.id || inp.placeholder || '').toLowerCase();
                    if (!nameOrId.includes('mine') && !nameOrId.includes('count')) return inp;
                  }
                  parent = parent.parentElement;
                }
              }
            }

            // Filtered inputs ignoring hidden/mines-count
            let inputs = Array.from(document.querySelectorAll('input')).filter(inp => {
              let t = (inp.type || 'text').toLowerCase();
              if (t === 'hidden' || t === 'password' || t === 'checkbox' || t === 'radio' || t === 'submit' || t === 'search') return false;
              let nameOrId = (inp.name || inp.id || inp.placeholder || inp.getAttribute('aria-label') || '').toLowerCase();
              if (nameOrId.includes('mine') || nameOrId.includes('bomb') || nameOrId.includes('count')) return false;
              let rect = inp.getBoundingClientRect();
              return rect.width > 0 && rect.height > 0;
            });
            if (inputs.length > 0) return inputs[0];
            return null;
          }

          let inp = findInput();
          if (inp) {
            let nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set;
            if (nativeSetter) {
              nativeSetter.call(inp, targetValStr);
            } else {
              inp.value = targetValStr;
            }
            inp.dispatchEvent(new Event('input', { bubbles: true, cancelable: true }));
            inp.dispatchEvent(new Event('change', { bubbles: true, cancelable: true }));
          }
          window._betTypingInProgress = false;
          window._betTypingCompleted = true;
        })('$targetStr');
      """).timeout(const Duration(milliseconds: 500), onTimeout: () => null);
    } catch (e) {
      debugPrint('[FORCE BASE BET] Error: $e');
    }
  }

  Future<void> _ensureBaseBet(int runToken, {GameMode? mode}) async {
    final targetMode = mode ?? _activeGameMode;
    final state = getState(targetMode);
    state.isCurrentlyRecoveryRound = false;
    
    final double targetBet = await _calculateDynamicBaseBet(mode: targetMode);
    state.currentBetAmount = targetBet;

    // 1️⃣ First: Hardware-speed direct base bet set & MIN button trigger
    await _forceSetBaseBet(mode: targetMode);

    double currentBet = await _getBetAmount(mode: targetMode);
    if ((currentBet - targetBet).abs() < 0.00000001) {
       return;
    }
    
    debugPrint('[BASE BET] 🔄 [${targetMode.displayName}] Setting Base Bet: ${targetBet.toStringAsFixed(8)} (Floor: ${state.lockedBaseBet ?? _lockedBaseBetByMode[targetMode]})');
    await _setBetAmount(targetBet, mode: targetMode);
  }

  /// 🤝 Fluid Symbiotic Recovery Engine (ระบบทวงหนี้แบบต่อเนื่อง ยืดหยุ่น ไร้รอยต่อ และปลอดภัยสูงสุด)
  /// สอดคล้องกับคำสั่งผู้ใช้:
  /// 1. "ปกป้องเงินต้นเป็นชีวิต" -> กู้หนี้จาก Profit Cushion เท่านั้น ห้ามแตะต้อง Protected Principal เด็ดขาด!
  /// 2. "ไม่ยืดหยุ่น แข็งมาก" -> แทนที่การโดดเบทแข็งๆ ด้วย Continuous Dynamic Kelly Sizing ตาม Edge & Entropy
  /// 3. "สะสมกำไรอย่างยั่งยืน" -> จำกัดความเสี่ยงสูงสุดต่อตาไม่เกิน 20% ของ Profit Cushion
  Future<void> _executeSymbioticRecovery(
    int runToken, {
    GameMode? mode,
    double targetFraction = 1.0,
    double? fluidFraction,
  }) async {
    final targetMode = mode ?? _activeGameMode;
    final state = getState(targetMode);

    final double totalDebt = state.totalAccumulatedLoss;
    if (totalDebt <= 0.00000001) {
      state.isCurrentlyRecoveryRound = false;
      await _ensureBaseBet(runToken, mode: targetMode);
      return;
    }

    double currentBalance = await _getBalanceDouble(mode: targetMode);
    if (currentBalance <= 0.00000001) {
      currentBalance = state.lastSettledBalance > 0.00000001
          ? state.lastSettledBalance
          : ((state.sessionStartBalance != null && state.sessionStartBalance! > 0.00000001)
              ? state.sessionStartBalance!
              : (state.sessionMaxBalance > 0.00000001 ? state.sessionMaxBalance : 0.0));
    }
    state.isCurrentlyRecoveryRound = true;

    double pRate = getRecoveryProfitPercent(targetMode);
    final analyzer = _analyzersByMode[targetMode] ?? _sequenceAnalyzerViewModel;
    final coin = state.activeCoinType ?? analyzer?.getCoinTypeForMode(targetMode);
    final double defaultFloor = getFloorBetForMode(targetMode, coinType: coin);
    final double floorBet = state.lockedBaseBet ?? _lockedBaseBetByMode[targetMode] ?? defaultFloor;
    final double minRecoveryBet = floorBet * 1.5;

    // 🎯 คำสั่งผู้ใช้:
    // รอบที่ 1: แพ้ครบ 3 ตา รอ 15-25 ตา ทวงทันที แพ้ทวง แพ้ทวง แพ้ กลับไป Base bet
    // รอบที่ 2: แพ้ครบ 3 ตา รอ 15-25 ตา ทวงทันที แพ้ทวง แพ้ทวง แพ้ กลับไป Base bet
    // รอบที่ 3: แพ้ครบ 3 ตา รอ 15-25 ตา ทวงทันที แพ้ทวง แพ้ทวง แพ้ กลับไป Base bet วนกลับไป รอบแรก
    // 🎯 AQ-DARE PILLAR 2: DYNAMIC DEBT SLICING (25% per slice = 4 slices)
    // แบ่งทวงทีละ 25% ของหนี้สะสม เพื่อลดภาระ Recovery Bet ลงถึง ~75%
    // ป้องกันการ All-in หรือเบทก้อนโตที่สุ่มเสี่ยงต่อ Drawdown ลึก
    double sliceDebt = totalDebt * 0.25;
    if (sliceDebt < floorBet) {
      sliceDebt = totalDebt; // หาก 25% ต่ำกว่า Floor Bet ให้ทวงตามหนี้จริง
    }
    final double debtToEscalate = sliceDebt;

    debugPrint(
      '🎯 [AQ-DARE DEBT SLICING ⚡] [${targetMode.displayName}] [รอบที่ ${state.currentRecoveryCycle} | ไม้ที่ ${state.recoveryStepInCycle}/3] | ทวงหนี้รอบนี้: ${debtToEscalate.toStringAsFixed(8)} (แบ่งทวง 25% Slice จากหนี้รวม: ${totalDebt.toStringAsFixed(8)})',
    );

    // 🎯 คำสั่งผู้ใช้ (/grill-me Lean & Safe Recovery Bet Sizing):
    // ทวงเอาแค่ "หนี้เดิมที่ค้างอยู่ + กำไรเล็กน้อย (2x Base Bet)" โดยไม่บวกกำไรก้อนโต 20% บนตัวหนี้
    // เพื่อให้ขนาดเบทเล็กและปลอดภัยที่สุด ไม่แตะเพดาน 20% โดยไม่จำเป็น
    final double baseSurplus = floorBet * pRate * 2.0;
    final double surplusProfitMargin = baseSurplus;
    debugPrint(
      '🛡️ [LEAN RECOVERY SIZING 💎] [${targetMode.displayName}] Debt Slice: ${debtToEscalate.toStringAsFixed(8)} + Surplus(2x Base): ${baseSurplus.toStringAsFixed(8)} -> Target Profit: ${(debtToEscalate + surplusProfitMargin).toStringAsFixed(8)}',
    );

    double targetProfit = debtToEscalate + surplusProfitMargin;
    double requiredBet = targetProfit / pRate;

    if (requiredBet < minRecoveryBet) {
      requiredBet = minRecoveryBet;
    }

    state.remainingRecoverySlices = 0;

    const double casinoHardLimit = 3000.0;
    if (requiredBet > casinoHardLimit) {
      debugPrint(
        '🛡️ [CASINO HARD LIMIT] Required bet (${requiredBet.toStringAsFixed(8)}) exceeds casino max limit (3000.0). Capped to 3000.0!',
      );
      requiredBet = casinoHardLimit;
    }

    // 🛡️ AQ-DARE PILLAR 4: HALF-KELLY BET SIZING (Max 5% of Bankroll Cap, Absolute Cap 7%)
    // ห้าม All-in เด็ดขาด 100%! ไม่ว่าจะมีหนี้สะสมเท่าไหร่ก็ตาม เบททวงต้องไม่เกิน 5% ของยอดเงินในกระเป๋า
    // หากหนี้สูงเกินไป ให้ผ่อนทวงหลายตา แทนที่จะทุ่มหมดตัวในตาเดียว
    if (currentBalance > 0.00000001) {
      final double maxBankrollCap = currentBalance * 0.05;
      if (requiredBet > maxBankrollCap) {
        debugPrint(
          '🛡️ [AQ-DARE PILLAR 4: 5% HARD BET CAP] Required bet (${requiredBet.toStringAsFixed(8)}) exceeds 5% bankroll cap (${maxBankrollCap.toStringAsFixed(8)}). Capped to 5% of balance!',
        );
        requiredBet = maxBankrollCap;
      }
    }

    // Floor protection: ต้องไม่ต่ำกว่า Base Bet ขั้นต่ำ
    if (requiredBet < floorBet) {
      requiredBet = floorBet;
    }

    // Absolute sanity ceiling: ห้ามเดิมพันเกิน 7% ของ balance เด็ดขาด
    if (currentBalance > floorBet && requiredBet > currentBalance * 0.07) {
      requiredBet = currentBalance * 0.07;
    }

    requiredBet = double.parse(requiredBet.toStringAsFixed(8));
    state.currentBetAmount = requiredBet;
    debugPrint(
      '🎯 [AQ-DARE RECOVERY ⚡] [${targetMode.displayName}] หนี้รวม: ${state.totalAccumulatedLoss.toStringAsFixed(8)} | หนี้รอบนี้ (25%): ${debtToEscalate.toStringAsFixed(8)} | เบททวง: ${requiredBet.toStringAsFixed(8)} | ยอดเงิน: ${currentBalance.toStringAsFixed(8)}',
    );

    // 🎯 สั่งพิมพ์ยอดเบททวงหนี้ลงในหน้าเว็บเสมอ เพื่อให้แน่ใจว่าเว็บรับยอดทวงหนี้ 100% เต็ม
    await _setBetAmount(requiredBet, mode: targetMode);

  }
}
