import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../services/websocket_service.dart';

import '../models/history_entry.dart';
import '../engines/advanced_rules_engine.dart';
import '../engines/algolithone_engine.dart';
import '../engines/meta_learning_engine.dart';
import '../engines/v13_engine.dart';
import '../engines/n_gram_engine.dart';
import '../engines/time_series_engine.dart';
import '../engines/markov_engine.dart';
import '../engines/entropy_scanner.dart';
import '../engines/shadow_hunter_engine.dart';

import '../models/decision_entry.dart';
import '../models/prediction_context.dart';
import '../models/prediction_result.dart';
import '../services/prediction_pipeline_service.dart';

class SequenceAnalyzerViewModel extends ChangeNotifier {
  // --- WebView Controller ---
  InAppWebViewController? _webViewController;
  SharedPreferences? _prefs;

  // --- Server URL Management ---
  Future<void> updateServerUrl(String newUrl) async {
    _serverUrl = newUrl;
    await _prefs?.setString('ai_server_url', newUrl);
    notifyListeners();
    debugPrint("🌐 Server URL Updated to: $_serverUrl");
  }

  // --- State for UI ---
  final List<String> buttonValues = ['A', 'B', 'C'];
  final Queue<HistoryEntry> _inputs = Queue<HistoryEntry>();
  String? _penultimatePredictedChar; // Stores the prediction from two turns ago
  String? _lastPredictedChar;
  String _advice = 'Hybrid AI Ready. Waiting for input...';
  double _confidence = 0.0;
  int _totalPredictions = 0;
  int _correctPredictions = 0;
  String? _lastUsedTriggerId; // 🔄 Tracks Ma, Mb, or Mc

  // --- Cognitive 3.0 Data Structures ---
  final List<MapEntry<String, bool>> _triggerSessionHistory =
      []; // Momentum: List of (TriggerId, WasCorrect)
  final Map<String, Map<String, int>> _triggerContextMemory =
      {}; // Context: HistoryPattern -> {TriggerId: NetWinScore}

  bool _isCalculating = false; // For locking UI during computation
  String? _currentBalance; // For Smart Balance Tracking
  int _predictionCount = 0; // Counts predictions made
  String? _initialBalance;
  double _profitPercentage = 0.0;
  bool _isUpdatingBalance = false; // Guard for concurrent updateBalance calls
  bool _isUpdatingBalanceFast = false; // Separate guard for fast updates
  bool _isDisposed = false;

  // --- Cognitive 5.0: Anti-Streak Architecture State ---
  String _activeHypothesis = 'Statistical';
  final Map<String, int> _hypothesisBlacklist = {}; // Hypothesis -> ExpiryRound
  double _predictabilityScore = 0.0; // 0.0 (Chaotic) to 1.0 (Fixed Pattern)
  int _consecutiveHypothesisFailures = 0;

  // --- Deep Scan V2.2 & V3.0: Neural-Inverse Logic State ---
  List<String> _lastBombChars = []; // Recency Bias (RB)
  final Map<String, int> _consecutiveGemsPerPos = {
    'A': 0,
    'B': 0,
    'C': 0,
  }; // Saturation Point (SP)
  final Map<String, double> _deepScanSafetyScores = {
    'A': 0.0,
    'B': 0.0,
    'C': 0.0,
  };

  // V3.0 Predator State
  final List<String> _bombMigrationTrack =
      []; // History of actual bomb positions
  int _ghostBetCounter = 0;
  bool _isTrapModeDetected = false;
  // V19: _isMissRecoveryApplied removed (unused)
  final MarkovEngine _markovEngine = MarkovEngine();
  final V13Engine _v13Engine = V13Engine();
  int _roundCounter = 0;

  // --- V8.0 Adaptive Intelligence Engine State ---
  GamePhase _currentPhase = GamePhase.chaos;
  double _streakRisk = 0.0;
  double _normalizedEntropy = 0.0;
  String _decisionType = 'Execute'; // 'Execute' / 'Skip' / 'Ghost'
  int _ghostCyclesRemaining = 0; // Cognitive v6.0: Ghost Bet counter
  int _cooldownCyclesRemaining = 0; // Cognitive v6.0: Cooldown counter
  final List<Map<String, dynamic>> _stateMemory =
      []; // Enhanced Memory: last 100 states
  static const int _maxStateMemory = 100;
  final List<String> _decisionSequence =
      []; // Predator v4.0: track decision sequence
  static const int _maxDecisionSequence = 10;
  int _patternFlipCount = 0; // Predator v4.0: pattern flip frequency

  // --- V9.0 Reactive Learning AI Engine State ---
  String? _lastFailureCause; // Trap / Bias / Weak Rule / Overconfidence / None
  String? _correctionStrategyApplied; // Reverse / Change / Reduce Risk / None
  String? _lastFailedPrediction;
  final Map<String, Map<String, String>> _counterMoveMemory =
      {}; // Pattern -> Wrong Move -> Correct Move
  final Map<String, int> _consecutiveFailuresPerAction =
      {}; // For Anti-Repetition Guard
  final List<String> _lossSequence = []; // 🛡️ V15.0: Track exact losing actions

  final bool _isSupremeShieldActive = false;
  late final ShadowHunterEngine _shadowHunter;

  // --- Flow Intelligence Legacy (Used as fallback/context) ---
  final List<String> _lossStreakWinningChars =
      []; // Tracks what won while we lost
  final List<bool> _recentResults =
      []; // Fixed-size window for Anti-Resistance (last 10)
  double _antiResistanceAccuracy = 0.5;

  // --- Trackers ---
  int _correctStreak = 0;
  int _incorrectStreak = 0; 
  String _clientSeed = 'TITANIUM_INITIAL_SEED_001';
  bool _isV1EngineDominant = false;

  // --- Balance Warning & Lock System ---
  bool _isWebViewLocked = false;
  DateTime? _lockStartTime;
  final Duration _lockDuration = const Duration(minutes: 5);
  Timer? _lockTimer;
  Timer? _balanceTimer; // Live balance auto-polling timer
  Timer? _learningSaveDebounceTimer;
  // Persistent lock state keys
  static const String _lockStateKey = 'webview_lock_state';
  static const String _lockStartTimeKey = 'webview_lock_start_time';

  // --- Coin Type Tracking ---
  String? _detectedCoinType; // All FaucetPay coins: BTC, ETH, DOGE, LTC, BCH, DASH, DGB, TRX, USDT, FEY, ZEC, BNB, SOL, XRP, POL, ADA, TON, XLM, USDC, XMR, TARA
  final Map<String, String> _initialBalances =
      {}; // Track initial balance per coin type
  final Map<String, String> _highestBalances =
      {}; // Track highest balance per coin type
  String?
  _overallHighestBalance; // Track overall highest balance across all coins
  String? _overallHighestCoin; // Track which coin has overall highest balance

  // Getters for balance warning system
  bool get isWebViewLocked => _isWebViewLocked;
  String? get lockStartTime => _lockStartTime?.toIso8601String();
  Duration get lockDuration => _lockDuration;
  int get remainingLockSeconds => _lockStartTime != null
      ? (_lockDuration - DateTime.now().difference(_lockStartTime!)).inSeconds
            .clamp(0, _lockDuration.inSeconds)
      : 0;
  String? get detectedCoinType => _detectedCoinType;
  Map<String, String> get initialBalances => _initialBalances;
  Map<String, String> get highestBalances => _highestBalances;
  String? get overallHighestBalance => _overallHighestBalance;
  String? get overallHighestCoin => _overallHighestCoin;

  // --- Hybrid AI Components ---
  Interpreter? _interpreter;

  // Server Configuration for Retraining
  String _serverUrl = 'https://ventricle-overdrawn-ocelot.ngrok-free.dev';
  
  // Getter for UI
  String get serverUrl => _serverUrl;

  // Active Learning Layer (On-Device Training)
  // Context -> {NextChar: Count}
  final Map<String, Map<String, int>> _learningMemory = {};

  // Trackers (Redundant moved up)

  // 🔄 Copy User / AI Model Switching
  String _predictionMode = 'copy_user'; // 'copy_user' or 'ai_model'
  String get predictionMode => _predictionMode;

  // 💣 Bomb Follower Mode
  bool _bombFollowerMode = true; // Auto-follow revealed bomb after a loss
  bool get bombFollowerMode => _bombFollowerMode;
  void toggleBombFollowerMode(bool value) {
    _bombFollowerMode = value;
    notifyListeners();
  }
  // --- Adaptive Flex-Response State ---
  final Map<String, dynamic> _flexInternalState = {
    'trend': 'Neutral',
    'volatility': 'Low',
    'bias': <String, double>{'A': 0.0, 'B': 0.0, 'C': 0.0},
    'consistency': 0.0,
  };

  // 2. Flex Response Options
  String _primaryPrediction = 'A'; // Default start
  List<String> _backupOptions = [];

  // 🎯 Adaptive Strategy Switcher (Phase 11)
  String _currentStrategy = 'anti_loop'; // 'anti_loop' or 'anti_sequence'
  // V16.3: Cleaned up unused pattern fields

  // --- Advanced Rules Engine ---
  late final AdvancedRulesEngine _rulesEngine;
  late final TimeSeriesEngine _timeSeriesEngine;
  late final NGramEngine _nGramEngine; // 🧠 Smart N-Gram Engine (WSLS)
  late final MetaLearningEngine
  _metaLearningEngine; // 🧬 Adaptive Meta-Learning
  late final AlgolithoneEngine
  _algolithoneEngine; // ⚙️ Algolithone Risk & Mode Engine
  List<String> _futureForecast = []; // Stores next 3-5 predicted steps

  String? _lastRuleName; // Tracks which rule was used for the last prediction
  String? _lastTsReasoning; // Tracks the reasoning from TimeSeriesEngine v1.0

  final PredictionPipelineService _predictionPipeline = PredictionPipelineService();

  // --- 🧠 Adaptive Decision Intelligence System (ADIS) v2.0 ---
  // ignore: unused_field
  String _adisMode = 'Balanced';
  int _adisLevel = 0; // 0: Stable, 1: Yellow, 2: Red, 3: Black
  String _decisionSource = 'None'; // Tracks which logic made the final call
  final Map<String, double> _adisProbabilities = {'A': 0.0, 'B': 0.0, 'C': 0.0};

  // ADIS v2.0 Tools
  final Map<String, int> _banList = {'A': 0, 'B': 0, 'C': 0};

  // Scoring Helpers for Module 2
  Map<String, double> _baseRateScores = {'A': 0.33, 'B': 0.33, 'C': 0.33};
  Map<String, double> _recentSuccessScores = {'A': 0.0, 'B': 0.0, 'C': 0.0};
  Map<String, double> _patternAvoidanceScores = {'A': 1.0, 'B': 1.0, 'C': 1.0};

  // --- 🧠 Think System v2.3.2 (Constraint-Based Decision Making) ---
  final List<DecisionEntry> _decisionHistory = [];
  final Map<String, dynamic> _efficiencyMetrics = {
    'totalDecisions': 0,
    'avgSuccessRate': 0.0,
    'consecutiveWhiteCount': 0,
    'avgConfidence': 0.0,
  };
  static const int _maxDecisionHistory = 50; // Keep last 50 decisions
  // Removed _strategySelector
  
  DateTime? _lastInteractionTime;

  // --- Getters for UI ---
  bool get isCalculating => _isCalculating;
  Queue<HistoryEntry> get inputs => _inputs;
  /// V17.3: UI Mapping - Always show the absolute prediction on the buttons
  String? get lastPredictedChar => getAbsolutePrediction();
  
  /// V18: Check if Shadow Hunter detected a hunt
  bool get isHuntDetected => _shadowHunter.huntCertainty > 0.8;
  bool get isEmergencyResetRequired => _shadowHunter.isEmergencyResetRequired();

  /// V19: Clean Brain - Return the AI's calculated prediction directly.
  /// No more forced-A loop. The decision logic in _generateHybridResponse handles everything.
  String getAbsolutePrediction() {
    return _lastPredictedChar ?? 'A';
  }

  /// V59.0: Smart Pivot (Safest Option)
  /// Scans the last 50 rounds and returns the option with the fewest bombs.
  String getSafestOption(List<String> options) {
    if (options.isEmpty) return 'A';
    if (options.length == 1) return options.first;

    Map<String, int> recentBombsCount = {'A': 0, 'B': 0, 'C': 0};
    final List<HistoryEntry> recentInputs = _inputs.toList();
    int scanLen = recentInputs.length < 50 ? recentInputs.length : 50;
    for (int i = recentInputs.length - scanLen; i < recentInputs.length; i++) {
      if (recentInputs[i].actualBombPos != null) {
        recentBombsCount[recentInputs[i].actualBombPos!] =
            (recentBombsCount[recentInputs[i].actualBombPos!] ?? 0) + 1;
      }
    }

    String safest = options.first;
    int minBombs = 9999;
    for (String opt in options) {
      int count = recentBombsCount[opt] ?? 0;
      if (count < minBombs) {
        minBombs = count;
        safest = opt;
      }
    }
    return safest;
  }

  /// V37.1: Confirm the current prediction was actually used in a round.
  /// This advances the alternator so the next prediction will be different.
  void confirmPick() {
    _predictionPipeline.confirmPick();
  }
  String get advice => _advice;
  
  set advice(String value) {
    _advice = value;
    notifyListeners();
  }

  double get confidence => _confidence;
  String get accuracyPercentage => _totalPredictions == 0
      ? 'N/A'
      : (_correctPredictions * 100 / _totalPredictions).toStringAsFixed(1);
  List<String> get futureForecast => _futureForecast;
  String? get currentBalance => _currentBalance;
  int get predictionCount => _predictionCount;
  double get profitPercentage => _profitPercentage;

  // --- Analytics Getters ---
  int get totalPredictions => _totalPredictions;
  int get correctPredictions => _correctPredictions;
  
  double get profitLossValue {
    if (_detectedCoinType == null) return 0.0;
    String? initStr = _initialBalances[_detectedCoinType];
    String? currStr = _currentBalance;
    if (initStr == null || currStr == null) return 0.0;
    
    double initial = double.tryParse(initStr.replaceAll(',', '')) ?? 0.0;
    double current = double.tryParse(currStr.replaceAll(',', '')) ?? 0.0;
    return current - initial;
  }

  // --- Analysis Output ---

  /// Reset profit tracking — call this when bot starts
  /// so profit% is calculated from CURRENT balance, not app startup balance.
  void resetProfitTracking() {
    _initialBalances.clear();
    _initialBalance = null;
    _profitPercentage = 0.0;
    debugPrint('[PROFIT TRACKER] 🔄 Reset! Next balance read will be the new baseline.');
  }

  /// V39.0: Brain Clean Engine
  /// Wipes the machine learning memory entirely (used during Stop-Loss Breaks)
  void cleanBrainEngine() {
    _learningMemory.clear();
    _saveLearningMemory(); // Save the wiped state to disk
    debugPrint('[BRAIN CLEAN ENGINE] 🧠 Memory wiped clean!');
  }

  // --- V8.0 Getters for UI ---
  String get currentPhase => _currentPhase.toString().split('.').last;
  double get normalizedEntropy => _normalizedEntropy;
  double get streakRisk => _streakRisk;
  String get decisionType => _decisionType;
  int get ghostCyclesRemaining => _ghostCyclesRemaining;

  // Legacy V12 Trigger removed

  /// Core Logical Re-Analysis (Flow 5.0): Triggered after every result
  void _analyzeGameLogic(String lastResult, bool wasHypothesisCorrect) {
    _updatePredictabilityScore();

    // --- BLS: Break Losing Streak (Hypothesis Death) ---
    if (!wasHypothesisCorrect && _lastPredictedChar != null) {
      _consecutiveHypothesisFailures++;

      // Aggressive Blacklist: Disable this hypothesis for 5 rounds if it fails ONCE
      if (_consecutiveHypothesisFailures >= 1) {
        _hypothesisBlacklist[_activeHypothesis] = _predictionCount + 5;
        debugPrint(
          '[BLS 5.0] 💀 AGGRESSIVE DEATH: "$_activeHypothesis" blacklisted for 5 rounds.',
        );
      }

      // Immediate Invalidation: Force a re-analysis
      _activeHypothesis = 'Statistical';
    } else {
      _consecutiveHypothesisFailures = 0;
    }

    // --- Deep Scan V2.2: Neural-Inverse Logic Update ---
    _updateDeepScanScores();

    if (_inputs.length < 5) return;
    List<String> hist = _inputs.map((e) => e.value).toList();

    // Choose next hypothesis based on recent trends, avoiding blacklisted ones
    List<String> candidates = [];

    // 1. Repetition Meta-Pattern (last 2 same)
    if (hist.last == hist[hist.length - 2]) candidates.add('Repetition');

    // 2. Oscillation Meta-Pattern (ABAB)
    if (hist.length >= 4 &&
        hist.last == hist[hist.length - 3] &&
        hist[hist.length - 2] == hist[hist.length - 4]) {
      candidates.add('Oscillation');
    }

    // 3. Contextual Pattern Match (High accuracy)
    if (_antiResistanceAccuracy > 0.65) candidates.add('PatternMatch');

    // Filter by blacklist
    candidates.removeWhere(
      (h) =>
          _hypothesisBlacklist.containsKey(h) &&
          _hypothesisBlacklist[h]! > _predictionCount,
    );

    if (candidates.isNotEmpty) {
      _activeHypothesis = candidates.last; // Prio newest detected pattern
    } else {
      _activeHypothesis = 'Statistical';
    }

    debugPrint(
      '[COGNITIVE 5.0] Logic Updated: $_activeHypothesis (Blacklisted: ${_hypothesisBlacklist.keys.length})',
    );
  }

  /// Calculates how "fixed" the current game pattern is (0.0 to 1.0)
  void _updatePredictabilityScore() {
    if (_inputs.length < 10) return;
    List<String> hist = _inputs
        .map((e) => e.value)
        .toList()
        .sublist(_inputs.length - 10);

    // Simple entropy: how many unique 2-char transitions exist?
    Set<String> transitions = {};
    for (int i = 0; i < hist.length - 1; i++) {
      transitions.add(hist[i] + hist[i + 1]);
    }

    // Fewer transitions = higher predictability
    _predictabilityScore = (1.0 - (transitions.length / 9.0)).clamp(0.0, 1.0);
  }

  /// Deep Scan V3.0: The Predator Protocol Implementation
  /// Formula: P(Success) = (1/|Hist10|) * Sum(Location * EntropyWeight) - TrapBias
  void _updateDeepScanScores() {
    _isTrapModeDetected = _incorrectStreak >= 2 && _predictabilityScore > 0.6;

    // Ghost Bet Recommendation: 2 rounds after 2-loss streak
    if (_incorrectStreak == 2) {
      _ghostBetCounter = 2;
    } else if (_ghostBetCounter > 0) {
      _ghostBetCounter--;
    }

    // 1. Calculate Bomb Migration Bias (V3.0)
    Map<String, double> migrationBias = {'A': 0.0, 'B': 0.0, 'C': 0.0};
    if (_bombMigrationTrack.length >= 2) {
      String lastPos = _bombMigrationTrack.last;
      String prevPos = _bombMigrationTrack[_bombMigrationTrack.length - 2];

      if (lastPos == prevPos) {
        // Cluster detection: Bomb is staying put
        migrationBias[lastPos] = 0.8;
      } else {
        // Zig-Zag / Movement detection: Predict next move based on vector
        int vPrev = prevPos == 'A' ? 0 : (prevPos == 'B' ? 1 : 2);
        int vLast = lastPos == 'A' ? 0 : (lastPos == 'B' ? 1 : 2);
        int vector = vLast - vPrev;
        int nextV = (vLast + vector) % 3;
        String nextPos = nextV == 0 ? 'A' : (nextV == 1 ? 'B' : 'C');
        migrationBias[nextPos] = 0.6;
      }
    }

    for (String char in ['A', 'B', 'C']) {
      String id = char;

      // 1. Recency Bias (RB): V3.0 uses Migration + Recency
      double rb = _lastBombChars.contains(char) ? 0.4 : 0.0;
      double mb = migrationBias[char] ?? 0.0;

      // 2. Saturation Point (SP): Danger if Gem has been here 3+ times
      int consecGems = _consecutiveGemsPerPos[char] ?? 0;
      double spInverse = (1.0 - (consecGems / 3.0)).clamp(0.0, 1.0);

      // 3. Stability (Entropy Weight)
      double stability = _predictabilityScore;

      // 4. Trap Bias (Inversion Logic)
      // When in Trap Mode, high RB/SP scores are actually more dangerous.
      double baseScore =
          (rb * 0.3) + (mb * 0.2) + (spInverse * 0.3) + (stability * 0.2);

      if (_isTrapModeDetected) {
        // Invert: 1 - score (Simplified Trap Bias)
        baseScore = (1.0 - baseScore).clamp(0.1, 0.9);
        debugPrint(
          '[PREDATOR] ⚠️ Trap Mode Active: Inverting probabilities for $id',
        );
      }

      // 5. The Third Man Theory (V29.2: REMOVED - Preventing position bias)
      /*
      if (_inputs.length >= 3) {
        ...
      }
      */

      _deepScanSafetyScores[id] = baseScore;
    }
  }

  /// Formats last 10 rounds for Deep Scan V3.0 verification
  /// Format: กด (ตำแหน่ง) - ผล: (Gem/Bomb) - ระเบิดจริงอยู่ที่ (ตำแหน่ง)
  String getDeepScanHistory() {
    if (_inputs.isEmpty) return "No history recorded.";

    List<String> entries = [];
    var list = _inputs.toList();
    int start = (list.length - 10).clamp(0, list.length);

    for (int i = start; i < list.length; i++) {
      var entry = list[i];
      String resultIcon = entry.isRed ? "💣" : "💎";
      String actualBomb = entry.actualBombPos ?? "?";
      String selected = entry.selectedPos ?? "?";
      entries.add("กด $selected - ผล $resultIcon - ระเบิดจริง $actualBomb");
    }

    return entries.reversed.join("\n");
  }

  // Legacy V7/V11 predictions removed

  /// Sets the webview controller from the view
  void setWebViewController(InAppWebViewController controller) {
    _webViewController = controller;
    startLiveBalanceUpdates();
  }

  /// Start live balance auto-polling every 0.01 second (10ms)

  void startLiveBalanceUpdates() {
    if (_isDisposed) return;
    _balanceTimer?.cancel();
    _balanceTimer = Timer.periodic(const Duration(milliseconds: 2000), (_) {
      if (_isDisposed) return;
      updateBalance();
    });
    // Also fetch immediately
    updateBalance();
  }

  /// Stop live balance auto-polling
  void stopLiveBalanceUpdates() {
    _balanceTimer?.cancel();
    _balanceTimer = null;
  }

  /// Smart Balance Tracking: Executes JS to find and extract balance.
  /// Enhanced with multiple patterns and robust error handling.
  Future<void> updateBalance() async {
    if (_isDisposed || _webViewController == null) return;
    if (_isUpdatingBalance) return; // Prevent concurrent calls from 10ms timer
    _isUpdatingBalance = true;

    try {
      await _doUpdateBalance();
    } finally {
      _isUpdatingBalance = false;
    }
  }

  /// Fast balance update — single attempt, no retries.
  /// Used by Stop Profit monitor for instant readings.
  /// Has its OWN guard so it won't be blocked by the slow updateBalance retry loop.
  Future<void> updateBalanceFast({bool force = false}) async {
    if (_isDisposed || _webViewController == null) return;
    if (_isUpdatingBalanceFast && !force) return; // Separate guard — won't be blocked by updateBalance
    _isUpdatingBalanceFast = true;
    try {
      await _doUpdateBalanceSingleAttempt();
    } finally {
      _isUpdatingBalanceFast = false;
    }
  }

  Future<void> _doUpdateBalance() async {
    if (_isDisposed || _webViewController == null) return;

    // Enhanced JS function with focus on multiple cryptocurrency patterns
    const String jsCode = r"""
      (function() {
        try {
          const text = document.body.innerText || "";
          
          // All FaucetPay supported coins
          const coins = [
            {regex: /Bitcoin\s*\(BTC\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'BTC'},
            {regex: /Ethereum\s*\(ETH\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'ETH'},
            {regex: /Dogecoin\s*\(DOGE\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'DOGE'},
            {regex: /Litecoin\s*\(LTC\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'LTC'},
            {regex: /Bitcoin Cash\s*\(BCH\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'BCH'},
            {regex: /Dash\s*\(DASH\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'DASH'},
            {regex: /Digibyte\s*\(DGB\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'DGB'},
            {regex: /Tron\s*\(TRX\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'TRX'},
            {regex: /Tether\s*\(USDT\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'USDT'},
            {regex: /USDT\s*\(USDT\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'USDT'},
            {regex: /Feyorra\s*\(FEY\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'FEY'},
            {regex: /Zcash\s*\(ZEC\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'ZEC'},
            {regex: /Binance Coin\s*\(BNB\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'BNB'},
            {regex: /BNB\s*\(BNB\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'BNB'},
            {regex: /Solana\s*\(SOL\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'SOL'},
            {regex: /Ripple\s*\(XRP\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'XRP'},
            {regex: /XRP\s*\(XRP\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'XRP'},
            {regex: /Polygon\s*\(POL\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'POL'},
            {regex: /Cardano\s*\(ADA\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'ADA'},
            {regex: /Ton\s*\(TON\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'TON'},
            {regex: /TON\s*\(TON\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'TON'},
            {regex: /Stellar\s*\(XLM\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'XLM'},
            {regex: /USDC\s*\(USDC\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'USDC'},
            {regex: /Monero\s*\(XMR\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'XMR'},
            {regex: /Taraxa\s*\(TARA\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'TARA'}
          ];
          
          // Try text-based matching first
          for (const pattern of coins) {
            const match = text.match(pattern.regex);
            if (match && match[1]) {
              const balance = parseFloat(match[1].replace(/,/g, ''));
              if (!isNaN(balance) && balance > 0 && balance < 100000000) {
                return JSON.stringify({coin: pattern.coin, balance: match[1]});
              }
            }
          }
          
          // Fallback: Search in HTML with flexible spacing
          const html = document.body.innerHTML || "";
          for (const pattern of coins) {
            const flexRegex = new RegExp(pattern.regex.source.replace('\\s*', '[^0-9]*'), 'i');
            const match = html.match(flexRegex);
            if (match && match[1]) {
              const balance = parseFloat(match[1].replace(/,/g, ''));
              if (!isNaN(balance) && balance > 0 && balance < 100000000) {
                return JSON.stringify({coin: pattern.coin, balance: match[1]});
              }
            }
          }
          
          return null;
        } catch (e) {
          console.error('Balance extraction error:', e);
          return null;
        }
      })();
    """;

    // Enhanced retry logic with progressive delays
    const int maxRetries = 5;
    const List<Duration> retryDelays = [
      Duration(milliseconds: 200),
      Duration(milliseconds: 400),
      Duration(milliseconds: 800),
      Duration(milliseconds: 1200),
      Duration(milliseconds: 2000),
    ];

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _webViewController!.evaluateJavascript(
          source: jsCode,
        );

        if (result != null && result.toString().isNotEmpty) {
          // Parse JSON response to get coin type and balance
          Map<String, dynamic>? parsedResult;
          try {
            parsedResult = jsonDecode(result.toString());
          } catch (e) {
            // Fallback for non-JSON response (legacy compatibility)
            final balance = double.tryParse(
              result.toString().replaceAll(',', '').trim(),
            );
            if (balance != null && balance >= 0) {
              _currentBalance = balance.toString().replaceAll(',', '').trim();
              _initialBalance ??= _currentBalance;

              final initial = double.tryParse(_initialBalance!);
              final current = balance;
              if (initial != null && initial > 0) {
                _profitPercentage = ((current - initial) / initial) * 100;
                _checkBalanceWarning();
              }

              debugPrint(
                "[BalanceTracker] Success: $_currentBalance (Attempt $attempt) - Legacy mode",
              );
              notifyListeners();
              return;
            }
          }

          if (parsedResult != null) {
            final String coinType = parsedResult['coin'] ?? 'UNKNOWN';
            final String balanceValue =
                parsedResult['balance']?.toString() ?? '';
            final balance = double.tryParse(
              balanceValue.replaceAll(',', '').trim(),
            );

            if (balance != null && balance >= 0) {
              _detectedCoinType = coinType;
              _currentBalance = balanceValue;

              // Set initial balance for this coin type if not already set
              if (!_initialBalances.containsKey(coinType)) {
                _initialBalances[coinType] = balanceValue;
              }

              // Track highest balance for this coin type
              if (!_highestBalances.containsKey(coinType)) {
                _highestBalances[coinType] = balanceValue;
              } else {
                final currentHighest =
                    double.tryParse(
                      _highestBalances[coinType]!.replaceAll(',', ''),
                    ) ??
                    0;
                if (balance > currentHighest) {
                  _highestBalances[coinType] = balanceValue;
                  debugPrint(
                    "[BalanceTracker] New highest for $coinType: $balanceValue",
                  );
                }
              }

              // Track overall highest balance across all coins
              if (_overallHighestBalance == null) {
                _overallHighestBalance = balanceValue;
                _overallHighestCoin = coinType;
              } else {
                final overallHighest =
                    double.tryParse(
                      _overallHighestBalance!.replaceAll(',', ''),
                    ) ??
                    0;
                if (balance > overallHighest) {
                  _overallHighestBalance = balanceValue;
                  _overallHighestCoin = coinType;
                  debugPrint(
                    "[BalanceTracker] New overall highest: $coinType $balanceValue",
                  );
                }
              }

              final initial = double.tryParse(
                _initialBalances[coinType] ?? '0',
              );
              final current = balance;
              if (initial != null && initial > 0) {
                _profitPercentage = ((current - initial) / initial) * 100;
                _checkBalanceWarning();
              }

              debugPrint(
                "[BalanceTracker] Success: $coinType $_currentBalance (Attempt $attempt) | Highest: $_overallHighestBalance",
              );
              notifyListeners();
              return;
            }
          }
        }
      } catch (e) {
        debugPrint("[BalanceTracker] Attempt $attempt error: $e");
      }

      // Wait before retrying (progressive delay)
      if (attempt < maxRetries) {
        final delay = retryDelays[attempt - 1];
        debugPrint(
          "[BalanceTracker] Retry $attempt/$maxRetries in ${delay.inMilliseconds}ms",
        );
        await Future.delayed(delay);
        if (_isDisposed) return;
      }
    }

    // Enhanced fallback: Try to preserve last known balance
    if (_currentBalance != null &&
        _currentBalance != "Not Found" &&
        _currentBalance != "Error") {
      debugPrint("[BalanceTracker] Using last known balance: $_currentBalance");
      notifyListeners();
      return;
    }

    // Final fallback
    debugPrint("[BalanceTracker] All attempts failed");
    _currentBalance = "Checking...";
    notifyListeners();

    // Schedule another check after a delay
    Future.delayed(const Duration(seconds: 3), () {
      if (_isDisposed) return;
      if (_currentBalance == "Checking...") {
        updateBalance();
      }
    });
  }

  /// Single-attempt balance update — no retries, no fallback scheduling.
  /// For use by high-frequency PnL monitor to avoid blocking.
  Future<void> _doUpdateBalanceSingleAttempt() async {
    if (_isDisposed || _webViewController == null) return;

    const String jsCode = r"""
      (function() {
        try {
          const text = document.body.innerText || "";
          const coins = [
            {regex: /Bitcoin\s*\(BTC\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'BTC'},
            {regex: /Ethereum\s*\(ETH\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'ETH'},
            {regex: /Dogecoin\s*\(DOGE\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'DOGE'},
            {regex: /Litecoin\s*\(LTC\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'LTC'},
            {regex: /Bitcoin Cash\s*\(BCH\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'BCH'},
            {regex: /Dash\s*\(DASH\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'DASH'},
            {regex: /Digibyte\s*\(DGB\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'DGB'},
            {regex: /Tron\s*\(TRX\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'TRX'},
            {regex: /Tether\s*\(USDT\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'USDT'},
            {regex: /USDT\s*\(USDT\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'USDT'},
            {regex: /Feyorra\s*\(FEY\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'FEY'},
            {regex: /Zcash\s*\(ZEC\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'ZEC'},
            {regex: /Binance Coin\s*\(BNB\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'BNB'},
            {regex: /BNB\s*\(BNB\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'BNB'},
            {regex: /Solana\s*\(SOL\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'SOL'},
            {regex: /Ripple\s*\(XRP\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'XRP'},
            {regex: /XRP\s*\(XRP\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'XRP'},
            {regex: /Polygon\s*\(POL\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'POL'},
            {regex: /Cardano\s*\(ADA\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'ADA'},
            {regex: /Ton\s*\(TON\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'TON'},
            {regex: /TON\s*\(TON\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'TON'},
            {regex: /Stellar\s*\(XLM\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'XLM'},
            {regex: /USDC\s*\(USDC\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'USDC'},
            {regex: /Monero\s*\(XMR\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'XMR'},
            {regex: /Taraxa\s*\(TARA\)\s*([0-9,]+\.?[0-9]*)/i, coin: 'TARA'}
          ];
          for (const pattern of coins) {
            const match = text.match(pattern.regex);
            if (match && match[1]) {
              const balance = parseFloat(match[1].replace(/,/g, ''));
              if (!isNaN(balance) && balance > 0 && balance < 100000000) {
                return JSON.stringify({coin: pattern.coin, balance: match[1]});
              }
            }
          }
          return null;
        } catch (e) { return null; }
      })();
    """;

    try {
      final result = await _webViewController!.evaluateJavascript(source: jsCode);
      if (result != null && result.toString().isNotEmpty) {
        Map<String, dynamic>? parsedResult;
        try { parsedResult = jsonDecode(result.toString()); } catch (_) {}

        if (parsedResult != null) {
          final String coinType = parsedResult['coin'] ?? 'UNKNOWN';
          final String balanceValue = parsedResult['balance']?.toString() ?? '';
          final balance = double.tryParse(balanceValue.replaceAll(',', '').trim());

          if (balance != null && balance >= 0) {
            _detectedCoinType = coinType;
            _currentBalance = balanceValue;
            _initialBalances.putIfAbsent(coinType, () => balanceValue);

            final initial = double.tryParse(_initialBalances[coinType] ?? '0');
            if (initial != null && initial > 0) {
              _profitPercentage = ((balance - initial) / initial) * 100;
            }
            // No notifyListeners() here — this is called from timer, UI updates via monitor
          }
        }
      }
    } catch (_) {}
  }

  /// Checks balance against warning threshold and triggers lock if needed
  void _checkBalanceWarning() {
    // Note: _profitPercentage <= _warningThreshold logic is handled by UI/Alerts
  }

  /// Locks WebView and starts timer for app restart
  void lockWebView() {
    if (_isDisposed) return;
    _isWebViewLocked = true;
    _lockStartTime = DateTime.now();

    debugPrint(
      "[WARNING] Balance dropped to ${_profitPercentage.toStringAsFixed(2)}%. WebView locked for ${_lockDuration.inMinutes} minutes.",
    );

    // Cancel any existing timer
    _lockTimer?.cancel();

    // Save lock state to persistent storage
    _saveLockState();

    // Set timer for app restart
    _lockTimer = Timer(_lockDuration, () {
      if (_isDisposed) return;
      debugPrint("[RESTART] Lock period expired. Restarting app...");
      _restartApp();
    });

    notifyListeners();
  }

  /// Restarts WebView by reloading current URL
  void _restartApp() {
    if (_isDisposed) return;
    debugPrint("[RESTART] Lock period expired. Restarting WebView...");
    _isWebViewLocked = false;
    _lockStartTime = null;
    _lockTimer?.cancel();
    _lockTimer = null;

    // Clear persistent lock state
    _clearLockState();

    // Reload WebView to refresh the page
    if (_webViewController != null) {
      _webViewController!.reload();
    }

    debugPrint("[RESTART] WebView restarted and unlocked.");
    notifyListeners();
  }

  /// Clear lock state from persistent storage
  Future<void> _clearLockState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lockStateKey);
      await prefs.remove(_lockStartTimeKey);
      debugPrint("[LOCK] Cleared persistent lock state");
    } catch (e) {
      debugPrint("[LOCK] Error clearing lock state: $e");
    }
  }

  /// Manually unlock WebView (for testing/admin)
  void unlockWebView() {
    if (_isDisposed) return;
    _isWebViewLocked = false;
    _lockStartTime = null;
    _lockTimer?.cancel();
    _lockTimer = null;

    debugPrint("[MANUAL] WebView manually unlocked.");
    notifyListeners();
  }

  SequenceAnalyzerViewModel() {
    _rulesEngine = AdvancedRulesEngine(buttonValues);
    _timeSeriesEngine = TimeSeriesEngine(buttonValues);
    _nGramEngine = NGramEngine();
    _metaLearningEngine = MetaLearningEngine();
    _algolithoneEngine = AlgolithoneEngine();
    _shadowHunter = ShadowHunterEngine();

    _loadModel();
    _loadLearningMemory();
    _updateInternalState('');
    _restoreLockState();
  }

  /// Restore lock state from persistent storage
  Future<void> _restoreLockState() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _serverUrl = _prefs?.getString('ai_server_url') ?? 'https://ventricle-overdrawn-ocelot.ngrok-free.dev';
      _currentStrategy = _prefs?.getString('ai_strategy') ?? 'anti_loop';
      
      final isLocked = _prefs!.getBool(_lockStateKey) ?? false;

      if (isLocked) {
        final lockStartTimeStr = _prefs!.getString(_lockStartTimeKey);
        if (lockStartTimeStr != null) {
          final lockStartTime = DateTime.parse(lockStartTimeStr);
          final elapsed = DateTime.now().difference(lockStartTime);

          if (elapsed < _lockDuration) {
            // Lock is still active
            // _isWebViewLocked = true; // Disabled: "Lock Webview" only
            _lockStartTime = lockStartTime;

            // Calculate remaining time and set timer
            final remainingTime = _lockDuration - elapsed;
            _lockTimer = Timer(remainingTime, () {
              if (_isDisposed) return;
              _restartApp();
            });

            debugPrint(
              "[LOCK] Restored active lock. Remaining: ${remainingTime.inSeconds}s",
            );
          } else {
            // Lock period expired, clear it
            await _prefs!.remove(_lockStateKey);
            await _prefs!.remove(_lockStartTimeKey);
            debugPrint("[LOCK] Previous lock expired, cleared state");
          }
        }
      }
    } catch (e) {
      debugPrint("[LOCK] Error restoring lock state: $e");
    }
    notifyListeners();
  }

  /// Save lock state to persistent storage
  Future<void> _saveLockState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_lockStateKey, _isWebViewLocked);
      if (_lockStartTime != null) {
        await prefs.setString(
          _lockStartTimeKey,
          _lockStartTime!.toIso8601String(),
        );
      }
      debugPrint("[LOCK] Saved lock state: $_isWebViewLocked");
    } catch (e) {
      debugPrint("[LOCK] Error saving lock state: $e");
    }
  }

  Future<void> _loadModel() async {
    try {
      await _initModel();
      _advice = 'Hybrid AI Ready: TFLite + Active Learning';
    } catch (e) {
      debugPrint(
        '[WARNING] TFLite error: $e. Running on Active Learning only.',
      );
      _advice = 'Active Learning Engine Ready';
    }
    notifyListeners();
  }

  /// V18.2: Records a skipped round (Ghost Mode) and decrements the counter.
  void recordSkip() {
    if (_ghostCyclesRemaining > 0) _ghostCyclesRemaining--;
    _generateHybridResponse();
    notifyListeners();
  }

  Future<void> recordInput(
    String value, {
    String? triggerId,
    String? actualBombPos,
    double multiplier = 1.0,
    String? selectedAction,
  }) async {
    if (_isCalculating) return; // Prevent concurrent execution

    // V13.2: Mark interaction time for Ma/Mb/Mc predictor buttons or Markers
    _lastInteractionTime = DateTime.now();
    debugPrint('[V13.2] Interaction registered at $_lastInteractionTime');

    if (triggerId != null) {
      _lastUsedTriggerId = triggerId;
    }

    _isCalculating = true;
    _advice = '🤖 AI is thinking...';
    _predictionCount++; // Increment prediction count
    notifyListeners(); // Update UI immediately to show "thinking" state

    // Allow the UI to repaint before starting heavy computation
    await Future.delayed(const Duration(milliseconds: 20));

    // --- Original synchronous logic with error protection ---
    try {
      _performPredictionLogic(
        value,
        actualBombPos: actualBombPos,
        multiplier: multiplier,
        selectedAction: selectedAction,
      );
      // Hybrid trigger: also update balance after prediction
      await updateBalance();
    } catch (e, stackTrace) {
      debugPrint('[ERROR] Exception in prediction logic: $e');
      debugPrint('Stack trace: $stackTrace');
      _advice = '❌ Error occurred. Please try again.';
    } finally {
      // CRITICAL: Always reset calculating flag
      _isCalculating = false;
      notifyListeners(); // Update UI with final result or error
    }
  }

  void _performPredictionLogic(
    String value, {
    String? actualBombPos,
    double multiplier = 1.0,
    String? selectedAction,
  }) {
    // 🚨 V15.2 SANITIZER: Prevent 'Unknown' virus from entering the AI state machine.
    final String actualPlayedForSanitizer = selectedAction ?? _lastPredictedChar ?? 'A';
    if (value != 'A' && value != 'B' && value != 'C') {
        String oldVal = value;
        value = ['A', 'B', 'C'].firstWhere((e) => e != actualPlayedForSanitizer, orElse: () => 'A');
        debugPrint('[V15.2 SANITIZER] Sanitized invalid input value $oldVal to $value');
    }

    _roundCounter++;
    if (_lastPredictedChar != null) {
      _totalPredictions++;
      final String evaluatedAction = selectedAction ?? _lastPredictedChar!;
      bool wasCorrect = (evaluatedAction == value);

      if (wasCorrect) {
        _correctPredictions++;
        _correctStreak++;
        _incorrectStreak = 0;
      } else {
        _correctStreak = 0;
        _incorrectStreak++;

        // V37.4 TITANIUM: Seed Rotation on Consecutive Loss
        if (_incorrectStreak >= 2) {
          _rotateSeed();
        }

        // 🔄 NEW: More Resilient Mode Switching
        if (_predictionMode == 'copy_user') {
          // If Copy User is wrong, the user's pattern isn't simple. Switch to AI.
          _predictionMode = 'ai_model';
          debugPrint(
            '[SWITCH] Mode switched to: ai_model (Copy User was wrong)',
          );
        } else if (_predictionMode == 'ai_model' && _incorrectStreak >= 2) {
          // V29.2: Faster panic switch (2 losses)
          _predictionMode = 'copy_user';
          debugPrint(
            '[SWITCH] Mode switched to: copy_user (AI wrong 2x, panic reset)',
          );
        }
        // otherwise, if AI is wrong but streak < 3, STAY in AI mode to learn.
      }

      // Update Engines with round outcome
      _v13Engine.updateState(
        _inputs.toList(),
        wasCorrect,
        lastAction: selectedAction ?? _lastPredictedChar,
      );


      // --- FLOW 5.0 + V3.0 (Predator Protocol) ---
      // Update Deep Scan Trackers (RB and SP)
      _lastBombChars = ['A', 'B', 'C']
        ..remove(value); // Gems are 'value', others are bombs

      // Update V3.0 Migration Track
      if (actualBombPos != null) {
        _bombMigrationTrack.add(actualBombPos);
        if (_bombMigrationTrack.length > 20) _bombMigrationTrack.removeAt(0);
      } else {
        // Fallback: assume the first bomb char if not provided (not ideal but better than nothing)
        if (_lastBombChars.isNotEmpty) {
          _bombMigrationTrack.add(_lastBombChars.first);
        }
      }

      for (String char in ['A', 'B', 'C']) {
        if (char == value) {
          _consecutiveGemsPerPos[char] =
              (_consecutiveGemsPerPos[char] ?? 0) + 1;
        } else {
          _consecutiveGemsPerPos[char] = 0; // Reset on bomb
        }
      }

      // Update Anti-Resistance Accuracy (Window of 10)
      _recentResults.add(wasCorrect);
      if (_recentResults.length > 10) _recentResults.removeAt(0);
      _antiResistanceAccuracy =
          _recentResults.where((r) => r).length / _recentResults.length;

      // Deductive Logic Update
      _analyzeGameLogic(value, wasCorrect);

      // Update Loss Streak Marker Frequency
      if (!wasCorrect) {
        _lossStreakWinningChars.add(value);
        if (_lossStreakWinningChars.length > 10) {
          _lossStreakWinningChars.removeAt(0);
        }
      } else {
        _lossStreakWinningChars.clear();
      }

      final String actualPlayedForLearning = selectedAction ?? _lastPredictedChar ?? 'Unknown';

      // 🔥 Send Feedback to Server for Retraining
      _sendFeedbackToServer(wasCorrect, value);

      // 🧠 Enhanced Learning: Inline learning from results
      if (actualPlayedForLearning != 'Unknown') {
        List<String> historyForLearn = _inputs.map((e) => e.value).toList();
        if (historyForLearn.length >= 3) {
          String ctx = historyForLearn.sublist(historyForLearn.length - 3).join();
          _learningMemory.putIfAbsent(ctx, () => {});
          if (wasCorrect) {
            _learningMemory[ctx]![value] = (_learningMemory[ctx]![value] ?? 0) + 10;
            debugPrint('[SUCCESS] Correct! \'$value\' for \'$ctx\' (+10)');
          } else {
            _learningMemory[ctx]![value] = (_learningMemory[ctx]![value] ?? 0) + 15;
            int oldScore = _learningMemory[ctx]![actualPlayedForLearning] ?? 0;
            _learningMemory[ctx]![actualPlayedForLearning] = (oldScore - 15).clamp(-100, 999);
            debugPrint('[PENALTY] Wrong in \'$ctx\'. Penalizing $actualPlayedForLearning. Rewarding $value.');
          }
          _saveLearningMemory();
        }
      }

      // --- Cognitive 3.0: Record Cognitive Experience ---
      if (_lastUsedTriggerId != null) {
        // Record Momentum (Session)
        _triggerSessionHistory.add(MapEntry(_lastUsedTriggerId!, wasCorrect));
        if (_triggerSessionHistory.length > 50) {
          _triggerSessionHistory.removeAt(0);
        }

        // Record Context (Flow Intelligence 4.0: 4-Round Pattern Context)
        if (_inputs.length >= 4) {
          List<String> history = _inputs.map((e) => e.value).toList();
          String pattern4 = history.sublist(history.length - 4).join();

          _triggerContextMemory.putIfAbsent(pattern4, () => {});
          int currentScore4 =
              _triggerContextMemory[pattern4]![_lastUsedTriggerId!] ?? 0;
          _triggerContextMemory[pattern4]![_lastUsedTriggerId!] = wasCorrect
              ? currentScore4 + 1
              : currentScore4 - 1;

          debugPrint(
            '[FLOW 4.0] Memory Logged (4-Char): "$pattern4" -> $_lastUsedTriggerId results in ${wasCorrect ? "WIN" : "LOSS"}',
          );
        }

        // Secondary memory (3-Round) for wider coverage
        if (_inputs.length >= 3) {
          List<String> history = _inputs.map((e) => e.value).toList();
          String pattern3 = history.sublist(history.length - 3).join();
          _triggerContextMemory.putIfAbsent(pattern3, () => {});
          _triggerContextMemory[pattern3]![_lastUsedTriggerId!] =
              (_triggerContextMemory[pattern3]![_lastUsedTriggerId!] ?? 0) +
              (wasCorrect ? 1 : -1);
        }
      }



      // 🧬 Evolutionary Meta-Learning: Update rule weights
      if (_lastRuleName != null) {
        _rulesEngine.updateRuleWeights(_lastRuleName!, wasCorrect);
      }

      //  ADIS: Module 1 & 3 Updates
      _updateAdisState(wasCorrect);
    }

    // 2. Add new input with correct isRed status
    // If actualPlayed is Unknown, we MUST assume we played the predicted char to track the loss.
    final String actualPlayed = selectedAction ?? _lastPredictedChar ?? 'Unknown';
    bool isRed = (actualPlayed != 'Unknown') ? (actualPlayed != value) : (_lastPredictedChar != null ? _lastPredictedChar != value : false);
    
    // Safety: If it's literally NOT a win, and it's not Unknown, it's RED.
    if (actualPlayed != 'Unknown' && actualPlayed != value) isRed = true;

    // V18.1: Instant Feedback
    _shadowHunter.recordRound(
      clickedPos: actualPlayed == 'Unknown' ? null : actualPlayed,
      bombPos: actualBombPos,
      won: !isRed,
    );

    // --- V9.0 Reactive Learning Check ---
    // Decisive Fix: If it's a loss, we MUST track what failed.
    // If actualPlayed is Unknown, fallback to the last predicted char.
    final String trackingAction = (actualPlayed == 'Unknown') ? (_lastPredictedChar ?? 'Unknown') : actualPlayed;
    
    if (isRed || (value != trackingAction && trackingAction != 'Unknown')) {
        _lastFailedPrediction = trackingAction;
        // Inline failure diagnosis (V9.0)
        _lastFailureCause = 'General Miss';
        _correctionStrategyApplied = null;
        if (_lastFailedPrediction == _penultimatePredictedChar && _lastFailedPrediction != value) {
          _lastFailureCause = 'Repetition Bias';
          _consecutiveFailuresPerAction[_lastFailedPrediction!] = (_consecutiveFailuresPerAction[_lastFailedPrediction!] ?? 0) + 1;
          _correctionStrategyApplied = 'Force Change';
        } else if (_confidence > 85.0 && _normalizedEntropy > 0.6) {
          _lastFailureCause = 'Overconfidence Error';
          _correctionStrategyApplied = 'Reduce Risk';
        }
        // Counter Move Memory
        if (_lastFailedPrediction != null && _inputs.length >= 4) {
          String patCtx = _inputs.map((e) => e.value).toList().sublist(_inputs.length - 4, _inputs.length - 1).join();
          _counterMoveMemory.putIfAbsent(patCtx, () => {});
          _counterMoveMemory[patCtx]![_lastFailedPrediction!] = value;
        }
        debugPrint("[V16.9] 🛡️ RECORDED ACTUAL LOSS on $trackingAction. Cause: $_lastFailureCause");
    } else {
        // Reset failure tracking state on win
        _lastFailureCause = null;
        _lastFailedPrediction = null;
        _correctionStrategyApplied = null;
        _consecutiveFailuresPerAction.clear(); // Reset failure counts on win
        _lossSequence.clear(); // 🛡️ V15.0: Reset loss sequence on win
    }

    // --- White-to-White Activation Logic (TimeSeries v1.1) ---
    if (!isRed) {
      // Winner (White) detected
      if (!_isV1EngineDominant) {
        _isV1EngineDominant = true;
        debugPrint(
          "[TS ENGINE] ⚡ Winner detected. V1 Dominance ACTIVE.",
        );
      }
    } else {
      // If it's a Red (Loss), we reset the dominance so it relies on hybrid logic
      _isV1EngineDominant = false;
    }

    _inputs.add(
      HistoryEntry(
        value: value,
        isRed: isRed,
        selectedPos: actualPlayed,
        actualBombPos: actualBombPos,
        roundIndex: _roundCounter,
        multiplier: multiplier,
        timestamp: DateTime.now(),
      ),
    );

    // Emit outcome to WebSocket
    WebSocketService.instance?.submitSignal({
      'type': 'outcome',
      'actualValue': value,
      'isWin': !isRed,
      'roundIndex': _roundCounter,
    });

    // V14.2 Memory Guards
    if (_inputs.length > 200) {
      _inputs.removeFirst();
    }
    if (_triggerContextMemory.length > 500) {
      final keysToRemove = _triggerContextMemory.keys.take(_triggerContextMemory.length - 500).toList();
      for (final key in keysToRemove) {
        _triggerContextMemory.remove(key);
      }
    }

    // 🧠 V7.0 Engine Updates
    List<String> hist = _inputs.map((e) => e.value).toList();
    _markovEngine.update(hist);
    // _entropyScanner is updated in getV7Prediction() on demand

    // 🧠 SMART N-GRAM: Learn from every move (Real-time Pattern Update)
    _nGramEngine.learn(_inputs.map((e) => e.value).toList());

    // 🧬 META-LEARNING: Update strategies (Only if we had a prediction)
    if (_lastPredictedChar != null) {
      // Re-calculate wasCorrect just to be safe, or use the local var if in scope?
      // The checking logic above had 'wasCorrect'.
      // But to be clean, let's rely on the fact that isRed = !wasCorrect
      bool wasCorrectForMeta = !isRed;

      List<String> fullHistory = _inputs.map((e) => e.value).toList();
      _metaLearningEngine.update(value, wasCorrectForMeta, fullHistory);
    }

    // 🎯 Inline Active Learning (replaces _learnFromUserPattern + _trainOnInput)
    if (_inputs.length >= 4) {
      List<String> histForTrain = _inputs.map((e) => e.value).toList();
      String trainCtx = histForTrain.sublist(histForTrain.length - 4, histForTrain.length - 1).join();
      _learningMemory.putIfAbsent(trainCtx, () => {});
      _learningMemory[trainCtx]![value] = (_learningMemory[trainCtx]![value] ?? 0) + 1;
      _saveLearningMemory();
      debugPrint('[AI] Active Learning: Context \'$trainCtx\' -> Predict \'$value\' (Reinforced)');
    }

    // 🎯 Check and switch strategy if needed (Phase 11)
    _checkAndSwitchStrategy();

    // 4. Calculate User Stats (Legacy but useful)
    _updateInternalState(value);

    // --- V8.0: Inline Phase Detection ---
    {
      List<String> phaseHist = _inputs.map((e) => e.value).toList();
      final entropyScanner = EntropyScanner();
      _normalizedEntropy = entropyScanner.calculateNormalizedEntropy(phaseHist);
      _streakRisk = entropyScanner.calculateStreakRisk(
        history: phaseHist,
        incorrectStreak: _incorrectStreak,
        totalPredictions: _totalPredictions,
        correctPredictions: _correctPredictions,
        normalizedEntropy: _normalizedEntropy,
      );
      _currentPhase = entropyScanner.detectPhase(
        history: phaseHist,
        normalizedEntropy: _normalizedEntropy,
        incorrectStreak: _incorrectStreak,
        correctStreak: _correctStreak,
        streakRisk: _streakRisk,
      );
      debugPrint('[V8.0 PHASE] Phase: $_currentPhase | Entropy: ${_normalizedEntropy.toStringAsFixed(2)} | StreakRisk: ${(_streakRisk * 100).toStringAsFixed(0)}%');
    }
    
    // 🛡️ V15.0: Update loss sequence if it was a loss
    if (isRed) {
      final String actionToAdd = (actualPlayed == 'Unknown') ? (_lastPredictedChar ?? 'Unknown') : actualPlayed;
      if (actionToAdd != 'Unknown') {
        _lossSequence.add(actionToAdd);
        if (_lossSequence.length > 5) _lossSequence.removeAt(0);
      }
    }

    // --- V8.0: Inline Streak Risk Evaluation ---
    {
      if (_ghostCyclesRemaining > 0) _ghostCyclesRemaining--;
      if (_cooldownCyclesRemaining > 0) _cooldownCyclesRemaining--;
      if (_streakRisk > 0.65 && _ghostCyclesRemaining == 0 && _cooldownCyclesRemaining == 0) {
        _ghostCyclesRemaining = 2 + (_streakRisk > 0.75 ? 1 : 0);
        _decisionType = 'Ghost';
      } else if (_streakRisk > 0.80 && _cooldownCyclesRemaining == 0) {
        _cooldownCyclesRemaining = 3;
        _decisionType = 'Skip';
      } else if (_ghostCyclesRemaining > 0) {
        _decisionType = 'Ghost';
      } else if (_cooldownCyclesRemaining > 0) {
        _decisionType = 'Skip';
      } else {
        _decisionType = 'Execute';
      }
    }

    // 5. Generate Response
    _generateHybridResponse();

    // --- V8.0: Post-Decision Processing ---
    _recordState();

    // Note: _isCalculating reset and notifyListeners() are handled in finally block
  }

  void _recordState() {
    Map<String, dynamic> state = {
      'round': _roundCounter,
      'phase': _currentPhase.toString().split('.').last,
      'entropy': _normalizedEntropy,
      'streakRisk': _streakRisk,
      'confidence': _confidence,
      'decision': _decisionType,
      'prediction': _primaryPrediction,
      'correctStreak': _correctStreak,
      'incorrectStreak': _incorrectStreak,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    // Track decision sequence for anti-repetition
    _decisionSequence.add(_primaryPrediction);
    if (_decisionSequence.length > _maxDecisionSequence) {
      _decisionSequence.removeAt(0);
    }

    // Store state
    _stateMemory.add(state);
    if (_stateMemory.length > _maxStateMemory) {
      _stateMemory.removeAt(0);
    }

    // Detect pattern breaks via transition tracking
    if (_inputs.length >= 2) {
      String prev = _inputs.toList()[_inputs.length - 2].value;
      String curr = _inputs.last.value;
      // Track pattern flips (sudden direction changes)
      if (_inputs.length >= 3) {
        String prevPrev = _inputs.toList()[_inputs.length - 3].value;
        if (prevPrev == curr && prevPrev != prev) {
          _patternFlipCount++;
        } else {
          _patternFlipCount = (_patternFlipCount - 1).clamp(0, 20);
        }
      }
    }
  }

  // --- 🧠 Think System v2.3.2: Core Methods ---




  /// Log a decision with full context for auditing
  void _logDecision(
    String action,
    String reason,
    Set<String> constraints,
    Map<String, bool> constraintResults,
  ) {
    var entry = DecisionEntry(
      timestamp: DateTime.now(),
      selectedAction: action,
      confidence: _confidence,
      decisionReason: reason,
    );

    _decisionHistory.add(entry);

    // Keep only recent decisions
    if (_decisionHistory.length > _maxDecisionHistory) {
      _decisionHistory.removeAt(0);
    }

    debugPrint("[THINK] Decision logged: ${entry.toString()}");
  }

  /// Update efficiency metrics for Think System dashboard
  void _updateEfficiencyMetrics() {
    _efficiencyMetrics['totalDecisions'] = _totalPredictions;
    _efficiencyMetrics['avgSuccessRate'] = _totalPredictions > 0
        ? _correctPredictions / _totalPredictions
        : 0.0;

    // Track consecutive whites for MinConsecutiveWhiteConstraint
    if (_inputs.isNotEmpty && !_inputs.last.isRed) {
      _efficiencyMetrics['consecutiveWhiteCount'] =
          (_efficiencyMetrics['consecutiveWhiteCount'] ?? 0) + 1;
    } else {
      _efficiencyMetrics['consecutiveWhiteCount'] = 0;
    }

    // Calculate average confidence from recent decisions
    if (_decisionHistory.length > 5) {
      double sumConf = 0.0;
      for (var entry in _decisionHistory.reversed.take(5)) {
        sumConf += entry.confidence;
      }
      _efficiencyMetrics['avgConfidence'] = sumConf / 5;
    }
  }

  // --- Persistent Storage ---
  void _saveLearningMemory() {
    if (_isDisposed) return;
    _learningSaveDebounceTimer?.cancel();
    _learningSaveDebounceTimer = Timer(const Duration(seconds: 2), () {
      _flushLearningMemoryToStorage();
    });
  }

  Future<void> _flushLearningMemoryToStorage() async {
    if (_isDisposed) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonData = jsonEncode(_learningMemory);
      await prefs.setString('learning_memory', jsonData);
      await prefs.setInt('total_predictions', _totalPredictions);
      await prefs.setInt('correct_predictions', _correctPredictions);

      // Save Rule Weights
      final weightsData = jsonEncode(_rulesEngine.ruleWeights);
      await prefs.setString('rule_weights', weightsData);

      debugPrint("💾 Learning data + Rule weights saved to device");
    } catch (e) {
      debugPrint("⚠️ Failed to save learning data: $e");
    }
  }

  Future<void> _loadLearningMemory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonData = prefs.getString('learning_memory');
      if (jsonData != null) {
        final Map<String, dynamic> decoded = jsonDecode(jsonData);
        _learningMemory.clear();
        decoded.forEach((key, value) {
          _learningMemory[key] = Map<String, int>.from(value);
        });
        debugPrint(
          "📂 Loaded ${_learningMemory.length} learning patterns from device",
        );
      }
      _totalPredictions = prefs.getInt('total_predictions') ?? 0;
      _correctPredictions = prefs.getInt('correct_predictions') ?? 0;

      // Load Rule Weights
      final weightsJson = prefs.getString('rule_weights');
      if (weightsJson != null) {
        final Map<String, dynamic> decodedWeights = jsonDecode(weightsJson);
        decodedWeights.forEach((key, value) {
          _rulesEngine.ruleWeights[key] = (value as num).toDouble();
        });
        debugPrint("🧬 Loaded ${_rulesEngine.ruleWeights.length} rule weights");
      }

      notifyListeners();
    } catch (e) {
      debugPrint("⚠️ Failed to load learning data: $e");
    }
  }

  Map<String, double> _getLearningScores() {
    if (_inputs.length < 3) return {};

    List<String> history = _inputs.map((e) => e.value).toList();
    String context = history.sublist(history.length - 3).join();

    Map<String, double> scores = {};
    if (_learningMemory.containsKey(context)) {
      int total = _learningMemory[context]!.values.fold(0, (sum, c) => sum + c);
      _learningMemory[context]!.forEach((key, count) {
        scores[key] = count / total;
      });
      debugPrint("📚 Learning Memory recalled for '$context': $scores");
    }
    return scores;
  }

  // --- Adaptive Logic ---
  void _updateInternalState(String input) {
    if (_inputs.isEmpty) return;

    // Volatility
    if (_incorrectStreak > 2) {
      _flexInternalState['volatility'] = 'High';
    } else {
      _flexInternalState['volatility'] = 'Low';
    }

    // Trend
    List<String> history = _inputs.map((e) => e.value).toList();
    if (history.length >= 3) {
      String last3 = history.sublist(history.length - 3).join();
      if (last3[0] != last3[1] &&
          last3[1] != last3[2] &&
          last3[0] != last3[2]) {
        _flexInternalState['trend'] = 'Chaos';
      } else if (last3[1] == last3[2]) {
        _flexInternalState['trend'] = 'Repeating';
      } else {
        _flexInternalState['trend'] = 'Alternating';
      }
    }

    // Bias
    Map<String, double> bias = {'A': 0.0, 'B': 0.0, 'C': 0.0};
    int total = _inputs.length;
    if (total > 0) {
      for (var entry in _inputs) {
        bias[entry.value] = (bias[entry.value] ?? 0.0) + 1.0;
      }
      bias.updateAll((key, val) => val / total);
    }
    _adisProbabilities.updateAll((key, val) => 0.0);
    _baseRateScores.updateAll((key, val) => 0.33);
    _recentSuccessScores.updateAll((key, val) => 0.0);
    _patternAvoidanceScores.updateAll((key, val) => 1.0);
  }

  void _updateAdisState(bool wasCorrect) {
    // Update Ban List (Module 1 - Reverse Psychology)
    _banList.updateAll((key, val) => val > 0 ? val - 1 : 0);

    // Update Streak Levels (Module 1 - ERP v2.3 Balanced Escalation)
    if (!wasCorrect) {
      if (_incorrectStreak == 1) {
        _adisLevel = 1; // Yellow Alert on 1st miss
        debugPrint("[ADIS] 🟡 YELLOW ALERT: First miss detected. Monitoring...");
      } else if (_incorrectStreak == 2) {
        _adisLevel = 2; // Red Alert on 2nd miss
        debugPrint("[ADIS] 🔴 RED ALERT: Second miss detected. Defensive posture.");
      } else if (_incorrectStreak >= 3) {
        _adisLevel = 3; // Black Alert on 3rd+ miss
        debugPrint("[ADIS] ⚫ BLACK ALERT: Multiple misses. Activating Scorched Earth.");
      }

      // Ban the last wrong choice for a shorter duration (V16.8: 2 rounds)
      if (_lastPredictedChar != null) {
        _banList[_lastPredictedChar!] = 2;
      }
      _adisEmergencyReset();
    } else {
      _adisLevel = 0;

      // Pre-emptive Safety (Yellow Alert) if confidence is too low
      if (_confidence < 40.0) {
        _adisLevel = 1;
        debugPrint(
          "[YELLOW ALERT] ADIS v2.3: PRE-EMPTIVE SAFETY - Low Confidence Detected",
        );
      }
    }

    // Determine Mode (Module 3 - Strategic Selector v2.3)
    if (_incorrectStreak >= 1 || _adisLevel >= 3) {
      _adisMode = 'Panic Mode'; // Total lockdown on any error
    } else if (_confidence < 80 || _adisLevel == 1) {
      _adisMode =
          'Defensive Mode'; // Default to defensive if not high confidence
    } else if (_confidence > 90) {
      _adisMode = 'Aggressive Mode';
    } else {
      _adisMode = 'Balanced Mode';
    }
  }

  void _adisEmergencyReset() {
    // 🧠 User Optimization: Preserve all history and memory as requested.
    // We no longer remove items from _provenPatterns.
    // Instead, the system relies on the weight shift (Module 2) and Defensive Mode (Module 3).
    debugPrint(
      "🧠 ADIS: Emergency Reset triggered. Strategy shifted but memory preserved.",
    );
  }

  void _rotateSeed() {
    // Generate a fresh random string for the client seed to break tracking
    var rand = math.Random.secure();
    var values = List<int>.generate(16, (i) => rand.nextInt(256));
    _clientSeed = base64UrlEncode(values);
    debugPrint("🔄 [TITANIUM] Cryptographic Seed Rotated! New Seed: $_clientSeed");
  }

  void _calculateAdisScores() {
    _baseRateScores = {'A': 0.0, 'B': 0.0, 'C': 0.0};
    
    // 1. Machine Learning AI Score (Pattern Recognition)
    Map<String, double> learningScores = _getLearningScores();
    for (var char in buttonValues) {
      double learn = learningScores[char] ?? 0.0;
      _baseRateScores[char] = (learn * 40.0); // Weight 40 for ML
    }

    // 2. Titanium Engine 1: Cryptographic RNG (HMAC-SHA256)
    // We hash the _clientSeed with the current nonce (_totalPredictions)
    String message = '$_clientSeed-$_totalPredictions';
    var key = utf8.encode('GOLDEN_P_TITANIUM_KEY');
    var bytes = utf8.encode(message);

    var hmacSha256 = Hmac(sha256, key); // HMAC-SHA256
    var digest = hmacSha256.convert(bytes);
    
    // Take the first byte of the hash and modulo 3 to get 0, 1, or 2 (A, B, C)
    int hashByte = digest.bytes[0];
    int selection = hashByte % 3;
    
    String cryptoPick = buttonValues[selection];
    _baseRateScores[cryptoPick] = (_baseRateScores[cryptoPick] ?? 0.0) + 60.0; // Weight 60 for Crypto
    
    debugPrint("🤖 [SYSTEMATIC AI] ML Scores: A=${learningScores['A']}, B=${learningScores['B']}, C=${learningScores['C']} | Crypto Pick: $cryptoPick");

    // Clear old unused scores
    _recentSuccessScores = {'A': 0.0, 'B': 0.0, 'C': 0.0};
    _patternAvoidanceScores = {'A': 0.0, 'B': 0.0, 'C': 0.0};
  }



  /// V28.0: Force the AI to recalculate its prediction with an optional High-Risk guard.
  void regeneratePrediction({bool isHighRisk = false}) {
    _generateHybridResponse(isHighRiskOverride: isHighRisk);
    notifyListeners();
  }

  void _generateHybridResponse({bool isHighRiskOverride = false}) {
    _decisionSource = 'None';
    
    // 1. Future Forecast (Multi-step)
    _futureForecast = _nGramEngine.forecast(
      _inputs.map((e) => e.value).toList(),
      5,
    );

    _calculateAdisScores();

    // Delegate core AI logic to PredictionPipelineService
    final predictionContext = PredictionContext(
      inputs: _inputs.toList(),
      lastFailedPrediction: _lastFailedPrediction,
      incorrectStreak: _incorrectStreak,
      isV1EngineDominant: _isV1EngineDominant,
      learningMemory: _learningMemory,
      isHighRisk: isHighRiskOverride, // V28.0 Superpower Guard
      nonce: _totalPredictions, // V36.1 True Nonce
      timeSeriesEngine: _timeSeriesEngine,
      v13Engine: _v13Engine,
      shadowHunter: _shadowHunter,
    );

    late final PredictionResult result;
    if (_predictionMode == 'copy_user' && _inputs.isNotEmpty) {
      _primaryPrediction = _inputs.last.selectedPos ?? _inputs.last.value;
      _decisionSource = 'Copy User (Mode)';
      result = PredictionResult(
        primaryPrediction: _primaryPrediction,
        decisionSource: _decisionSource,
        scores: {},
      );
    } else {
      result = _predictionPipeline.generateHybridResponse(
        predictionContext,
        _baseRateScores,
        _recentSuccessScores,
        _patternAvoidanceScores,
        _counterMoveMemory,
        _decisionSequence,
      );
      _primaryPrediction = result.primaryPrediction;
      _decisionSource = result.decisionSource;
    }

    // V20.6: AGGRESSIVE MODE - No more Skip lockdowns.
    // The bot will keep fighting regardless of the streak.
    if (_incorrectStreak >= 3) {
      _advice = "🚨 STREAK: $_incorrectStreak. Fighting through the hunt!";
    }

    // Calculate confidence from the pipeline scores
    if (result.scores.isNotEmpty) {
      double maxScore = result.scores.values.reduce((a, b) => a > b ? a : b);
      double totalScore = result.scores.values.fold(0.0, (sum, v) => sum + v.abs());
      _confidence = totalScore > 0 ? (maxScore / totalScore * 100).clamp(0.0, 100.0) : 50.0;
    } else {
      _confidence = 50.0;
    }

    // Use forbiddenSet logic internally in service, but we can reconstruct it for finalize
    Set<String> forbiddenSet = {};
    if (_lastFailedPrediction != null) {
      forbiddenSet.add(_lastFailedPrediction!);
    }

    _finalizePrediction(forbiddenSet, result.scores);
  }



  void _finalizePrediction(
    Set<String> forbiddenSet,
    Map<String, double> combined,
  ) {
    // V19 CLEAN BRAIN: All complex overrides (Deadlock Breaker, Oscillation, Think System, Supreme Guard, Bomb Authority, etc.)
    // have been REMOVED. V19 uses a strict Score -> Filter -> Pick pipeline handled prior to calling this method.
    // This method now ONLY handles generating the UI advice, diagnostics, and metrics.

    _updateEfficiencyMetrics();
    
    _logDecision(
      _primaryPrediction,
      'V19 Clean Brain',
      {},
      {},
    );

    _backupOptions = buttonValues
        .where((e) => e != _primaryPrediction)
        .toList();

    _penultimatePredictedChar = _lastPredictedChar;
    _lastPredictedChar = _primaryPrediction;

    // Emit prediction to WebSocket
    WebSocketService.instance?.submitSignal({
      'type': 'prediction',
      'prediction': _primaryPrediction,
      'confidence': _confidence,
    });

    // V14.2 FIX: V13 Engine as advisory (No longer overrides, just provides diagnostics for UI)
    V13Decision v13Decision = _v13Engine.processRound(
      _inputs.toList(),
      lastAction: (_inputs.isNotEmpty && _inputs.last.selectedPos != null)
          ? _inputs.last.selectedPos
          : _lastPredictedChar,
    );
    
    // Update advice for UI
    _advice = 'V13 [${v13Decision.mode.toString().split('.').last.toUpperCase()}] | Strategy: ${v13Decision.strategyUsed} | Conf: ${(v13Decision.confidence * 100).toStringAsFixed(0)}%';



    // --- Generate V8.0 Decision Cycle + Think System Response ---
    String phaseIcon = _currentPhase == GamePhase.trend
        ? '📈'
        : (_currentPhase == GamePhase.chaos
              ? '🌀'
              : (_currentPhase == GamePhase.trap ? '🪤' : '🔄'));
    String decisionIcon = _decisionType == 'Execute'
        ? '✅'
        : (_decisionType == 'Ghost' ? '👻' : '⏸️');
    String alertIcon = _adisLevel == 1 ? "🟡" : (_adisLevel >= 2 ? "⚫" : "✅");
    String accuracy = _totalPredictions == 0
        ? '0'
        : (_correctPredictions * 100 / _totalPredictions).toStringAsFixed(1);

    // Think System metrics
    int whiteStreak = _efficiencyMetrics['consecutiveWhiteCount'] ?? 0;

    String stopAdvice = "";
    if (_ghostCyclesRemaining > 0) {
      stopAdvice =
          "\n\n👻 **GHOST BET ACTIVE ($_ghostCyclesRemaining cycles)**\n"
          "StreakRisk ${(_streakRisk * 100).toStringAsFixed(0)}% detected. Use MIN BET to reveal system seed.";
    } else if (_ghostBetCounter > 0) {
      stopAdvice =
          "\n\n👻 **GHOST BET RECOMMENDED**\n"
          "Pattern Drift detected. Use MIN BET for the next $_ghostBetCounter rounds to reveal system seed.";
    } else if (_cooldownCyclesRemaining > 0) {
      stopAdvice =
          "\n\n❄️ **COOLDOWN MODE ($_cooldownCyclesRemaining cycles)**\n"
          "System is resetting internal bias. Avoid aggressive moves.";
    } else if (_incorrectStreak >= 1) {
      stopAdvice =
          "\n\n🚨 **CRITICAL: PATTERN DISRUPTION**\n"
          "System has detected a miss under Extreme Zero-Tolerance mode.\n"
          "**IMMEDIATE ACTION:** Pattern recognition is compromised. Highly recommend 30m break.";
    }

    String strategyDisplay = "Strategy: V19 Strict Flow";
    if (_isV1EngineDominant) {
      strategyDisplay += " [🧠 V1 DOMINANT]";
    }
    if (_isSupremeShieldActive) {
      strategyDisplay += " [🛡️ ABSOLUTE SHIELD]";
    }

    // Enhanced Trap Detection Display
    if (whiteStreak >= 2) {
      strategyDisplay += " [🚨 TRAP: FORCE BREAK]";
    } else if (whiteStreak >= 1) {
      strategyDisplay += " [⚠️ TRAP: PREVENTIVE]";
    }

    String correctionNotice = _lastFailureCause != null
        ? "\n[⚠️ CAUSE: $_lastFailureCause | 🛠️ CORRECTION: ${_correctionStrategyApplied ?? 'None'}]"
        : "";

    // AI Engine Diagnostics (V15.3: Resolves unused field lints)
    String v18Diag = "[V18.1: FLASH | Hunt: ${(_shadowHunter.huntCertainty * 100).toStringAsFixed(0)}%]";

    _advice =
        "$phaseIcon **V19 CLEAN BRAIN ENGINE**\n"
        "Phase: ${_currentPhase.toString().split('.').last.toUpperCase()} | Entropy: ${_normalizedEntropy.toStringAsFixed(2)} | StreakRisk: ${(_streakRisk * 100).toStringAsFixed(0)}%\n"
        "Confidence: ${_confidence.toStringAsFixed(1)}% | Decision: $decisionIcon $_decisionType$correctionNotice\n\n"
        "$alertIcon **V19 CLEAN DECISION**\n"
        "Source: $_decisionSource\n"
        "🧠 Strategy: $strategyDisplay\n"
        "🕵️ HUNT: $v18Diag\n\n"
        "🎯 **PREDICTION**\n"
        "Primary: $_primaryPrediction (${_confidence.toStringAsFixed(1)}%)\n"
        "Banned: ${forbiddenSet.isNotEmpty ? forbiddenSet.join(', ') : 'None'}\n"
        "Backup: ${_backupOptions.join(',')}\n\n"
        "💡 ${_lastTsReasoning ?? 'Analyzing patterns...'}"
        "$stopAdvice\n\n"
        "📊 **METRICS:** Success: $accuracy% | Decisions: ${_decisionHistory.length} | States: ${_stateMemory.length}";

    // --- ⚙️ Algolithone Integration (Advanced Analysis) ---
    final List<String> history = _inputs.map((e) => e.value).toList();
    final algoResult = _algolithoneEngine.analyze(history);

    _advice +=
        "\n\n⚙️ **ALGOLITHONE ENGINE**\n"
        "Risk Level: ${algoResult.riskLevel}/10 | Mode: ${algoResult.mode.toString().split('.').last.toUpperCase()}\n"
        "Insight: ${algoResult.insight}";
  }



  // --- Server Feedback System ---
  Future<void> _sendFeedbackToServer(bool wasCorrect, String actualValue) async {
    if (_inputs.length < 3) return; // Need 3-char context before actualValue

    // Get context (3 inputs before the latest one)
    List<String> history = _inputs.map((e) => e.value).toList();
    String context = history
        .sublist(history.length - 3)
        .join();

    try {
      final targetUrl = '$_serverUrl/feedback';
      debugPrint("📡 Sending feedback to: $targetUrl");
      
      final response = await http.post(
        Uri.parse(targetUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'context': context,
          'predicted': _lastPredictedChar ?? '',
          'actual': actualValue,
          'correct': wasCorrect,
          'bomb_pos': _inputs.isNotEmpty ? _inputs.last.actualBombPos : null,
          'round_index': _roundCounter,
          'currency': _detectedCoinType ?? 'UNKNOWN',
        }),
      ).timeout(const Duration(milliseconds: 5000));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint(
          "📤 Feedback sent! Samples: ${data['samples_collected']}, Model Updated: ${data['model_updated']}",
        );

        // If model was updated, reload it
        if (data['model_updated'] == true) {
          debugPrint("🔄 Model was retrained! Reloading...");
          await _reloadModelFromServer();
        }
      } else {
        if (response.statusCode == 404) {
          debugPrint("❌ Server Error 404: Endpoint not found. Please check if your Server URL (ngrok) is still active.");
        } else {
          debugPrint("❌ Server Error: ${response.statusCode}");
        }
      }
    } catch (e) {
      debugPrint("❌ Network Error sending feedback: $e");
    }
  }

  Future<void> _reloadModelFromServer() async {
    try {
      debugPrint("📥 Downloading latest model from $_serverUrl/model...");
      final response = await http.get(Uri.parse('$_serverUrl/model')).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final dir = await getApplicationDocumentsDirectory();
        final file = File(p.join(dir.path, 'model.tflite'));
        await file.writeAsBytes(response.bodyBytes);
        debugPrint("✅ Model downloaded and saved to ${file.path}");
        
        await _initModel(); // Reload the interpreter
      } else {
        debugPrint("⚠️ Failed to download model: HTTP ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("⚠️ Model reload failed: $e");
    }
  }

  Future<void> _initModel() async {
    try {
      _interpreter?.close();
      
      final dir = await getApplicationDocumentsDirectory();
      final localModelFile = File(p.join(dir.path, 'model.tflite'));
      
      if (await localModelFile.exists()) {
        debugPrint("📂 Loading model from Local Storage: ${localModelFile.path}");
        _interpreter = Interpreter.fromFile(localModelFile);
      } else {
        debugPrint("📦 Loading model from Assets (First run)");
        _interpreter = await Interpreter.fromAsset('model.tflite');
      }
      
      debugPrint("🚀 AI Interpreter initialized successfully!");
    } catch (e) {
      debugPrint("❌ Failed to initialize AI Interpreter: $e");
    }
  }


  // 🎯 Adaptive Strategy Switcher - Strategy Switch Logic
  void _checkAndSwitchStrategy() {
    // Switch strategy when correct streak >= 3
    // FIX: Use == 3 to switch ONCE, preventing constant oscillation on long streaks
    if (_correctStreak == 3) {
      if (_currentStrategy == 'anti_loop') {
        _currentStrategy = 'anti_sequence';

        debugPrint(
          "🔄 Strategy Switch: anti_loop -> anti_sequence (Streak: $_correctStreak)",
        );
      } else {
        _currentStrategy = 'anti_loop';

        debugPrint(
          "🔄 Strategy Switch: anti_sequence -> anti_loop (Streak: $_correctStreak)",
        );
      }
    }
  }

  void resetAIState() {
    if (_isCalculating) return; // Prevent reset while calculating

    _inputs.clear();
    _predictionPipeline.clearHistory(); // V52.0 QA Fix: Clear engine bans and score memory
    _lastPredictedChar = null;
    _advice = 'Session Reset. V8.0 AI memory preserved! 🧠';
    _confidence = 0.0;
    // Keep total stats for overall tracking
    // _totalPredictions and _correctPredictions preserved
    _correctStreak = 0;
    _incorrectStreak = 0;
    _predictionMode = 'copy_user'; // 🔄 Reset to Copy User mode

    // 🔥 Keep learning memory! Don't clear it.
    // _learningMemory.clear();  <- Commented out to preserve memory

    // --- V8.0 State Reset ---
    _currentPhase = GamePhase.chaos;
    _streakRisk = 0.0;
    _normalizedEntropy = 0.0;
    _decisionType = 'Execute';
    _ghostCyclesRemaining = 0;
    _cooldownCyclesRemaining = 0;
    _decisionSequence.clear();
    _patternFlipCount = 0;
    // Keep _stateMemory for cross-session learning

    debugPrint(
      "🔄 V8.0 Session reset. Learning memory preserved (${_learningMemory.length} patterns, ${_stateMemory.length} states)",
    );

    _flexInternalState['trend'] = 'Neutral';
    _flexInternalState['volatility'] = 'Low';
    _flexInternalState['bias'] = <String, double>{'A': 0.0, 'B': 0.0, 'C': 0.0};
    _backupOptions.clear();

    notifyListeners();
  }

  @override
  void dispose() {
    _learningSaveDebounceTimer?.cancel();
    _flushLearningMemoryToStorage();
    _isDisposed = true;
    _balanceTimer?.cancel();
    _lockTimer?.cancel();
    _interpreter?.close();
    super.dispose();
  }
}


