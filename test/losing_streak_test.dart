import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:golden_p/viewmodels/sequence_analyzer_viewmodel.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';
import 'package:golden_p/services/prediction_pipeline_service.dart';
import 'package:golden_p/models/prediction_context.dart';
import 'package:golden_p/models/history_entry.dart';
import 'package:golden_p/engines/time_series_engine.dart';
import 'package:golden_p/engines/v13_engine.dart';
import 'package:golden_p/engines/shadow_hunter_engine.dart';

class FakeInAppWebViewController extends Fake implements InAppWebViewController {
  final Future<dynamic> Function(String source, ContentWorld? contentWorld)? onEvaluateJavascript;
  final void Function()? onReload;

  FakeInAppWebViewController({this.onEvaluateJavascript, this.onReload});

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) {
    if (onEvaluateJavascript != null) {
      // Wrap in Future<dynamic>.value to force runtime generic type to be dynamic,
      // avoiding type-checking failures with .timeout's onTimeout in the viewmodel.
      return Future<dynamic>.value(onEvaluateJavascript!(source, contentWorld));
    }
    return Future<dynamic>.value(null);
  }

  @override
  Future<void> reload() async {
    if (onReload != null) {
      onReload!();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Losing Streak and Recovery Tests', skip: 'Outdated by 24/7 autonomous loop which does not halt on 3 losses', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({'overlay_smart_mode': true});
    });

    test('Inversion Logic: Triggers at streak == 2, does NOT trigger at streak == 3', () {
      final pipeline = PredictionPipelineService();
      
      final inputs = <HistoryEntry>[
        HistoryEntry(
          value: 'A',
          isRed: false,
          selectedPos: 'A',
          roundIndex: 1,
          multiplier: 1.0,
          timestamp: DateTime.now(),
        ),
        HistoryEntry(
          value: 'B',
          isRed: false,
          selectedPos: 'B',
          roundIndex: 2,
          multiplier: 1.0,
          timestamp: DateTime.now(),
        ),
      ];

      // Case 1: incorrectStreak == 2 -> Inversion triggers
      final contextStreak2 = PredictionContext(
        inputs: inputs,
        incorrectStreak: 2,
        isV1EngineDominant: false,
        learningMemory: {},
        nonce: 1,
        timeSeriesEngine: TimeSeriesEngine(['A', 'B', 'C']),
        v13Engine: V13Engine(),
        shadowHunter: ShadowHunterEngine(),
      );

      final result2 = pipeline.generateHybridResponse(
        contextStreak2,
        {'A': 0.33, 'B': 0.33, 'C': 0.33},
        {'A': 0.0, 'B': 0.0, 'C': 0.0},
        {'A': 1.0, 'B': 1.0, 'C': 1.0},
        {},
        [],
      );

      expect(result2.decisionSource.contains('Inversion'), isTrue,
          reason: 'Inversion logic should trigger when incorrectStreak == 2');

      // Case 2: incorrectStreak == 3 -> Inversion logic does NOT trigger again (allows consensus bestPick to run next)
      final contextStreak3 = PredictionContext(
        inputs: inputs,
        incorrectStreak: 3,
        isV1EngineDominant: false,
        learningMemory: {},
        nonce: 2,
        timeSeriesEngine: TimeSeriesEngine(['A', 'B', 'C']),
        v13Engine: V13Engine(),
        shadowHunter: ShadowHunterEngine(),
      );

      final result3 = pipeline.generateHybridResponse(
        contextStreak3,
        {'A': 0.33, 'B': 0.33, 'C': 0.33},
        {'A': 0.0, 'B': 0.0, 'C': 0.0},
        {'A': 1.0, 'B': 1.0, 'C': 1.0},
        {},
        [],
      );

      expect(result3.decisionSource.contains('Ensemble'), isTrue,
          reason: 'Inversion logic should NOT trigger when incorrectStreak == 3, allowing Ensemble/Consensus');

      // Case 3: incorrectStreak == 0 -> Inversion logic does NOT trigger
      final contextStreak0 = PredictionContext(
        inputs: inputs,
        incorrectStreak: 0,
        isV1EngineDominant: false,
        learningMemory: {},
        nonce: 3,
        timeSeriesEngine: TimeSeriesEngine(['A', 'B', 'C']),
        v13Engine: V13Engine(),
        shadowHunter: ShadowHunterEngine(),
      );

      final result0 = pipeline.generateHybridResponse(
        contextStreak0,
        {'A': 0.33, 'B': 0.33, 'C': 0.33},
        {'A': 0.0, 'B': 0.0, 'C': 0.0},
        {'A': 1.0, 'B': 1.0, 'C': 1.0},
        {},
        [],
      );

      expect(result0.decisionSource.contains('Ensemble'), isTrue,
          reason: 'Inversion logic should NOT trigger when incorrectStreak == 0');

      // Case 4: incorrectStreak == 1 -> Inversion logic does NOT trigger
      final contextStreak1 = PredictionContext(
        inputs: inputs,
        incorrectStreak: 1,
        isV1EngineDominant: false,
        learningMemory: {},
        nonce: 4,
        timeSeriesEngine: TimeSeriesEngine(['A', 'B', 'C']),
        v13Engine: V13Engine(),
        shadowHunter: ShadowHunterEngine(),
      );

      final result1 = pipeline.generateHybridResponse(
        contextStreak1,
        {'A': 0.33, 'B': 0.33, 'C': 0.33},
        {'A': 0.0, 'B': 0.0, 'C': 0.0},
        {'A': 1.0, 'B': 1.0, 'C': 1.0},
        {},
        [],
      );

      expect(result1.decisionSource.contains('Ensemble'), isTrue,
          reason: 'Inversion logic should NOT trigger when incorrectStreak == 1');

      // Case 5: incorrectStreak == 4 -> Inversion logic does NOT trigger
      final contextStreak4 = PredictionContext(
        inputs: inputs,
        incorrectStreak: 4,
        isV1EngineDominant: false,
        learningMemory: {},
        nonce: 5,
        timeSeriesEngine: TimeSeriesEngine(['A', 'B', 'C']),
        v13Engine: V13Engine(),
        shadowHunter: ShadowHunterEngine(),
      );

      final result4 = pipeline.generateHybridResponse(
        contextStreak4,
        {'A': 0.33, 'B': 0.33, 'C': 0.33},
        {'A': 0.0, 'B': 0.0, 'C': 0.0},
        {'A': 1.0, 'B': 1.0, 'C': 1.0},
        {},
        [],
      );

      expect(result4.decisionSource.contains('Ensemble'), isTrue,
          reason: 'Inversion logic should NOT trigger when incorrectStreak == 4');
    });

    test('predictionMode copy_user vs ai_model', () async {
      final vm = SequenceAnalyzerViewModel();
      
      final fakeController = FakeInAppWebViewController(
        onEvaluateJavascript: (source, contentWorld) async {
          return jsonEncode({'coin': 'POL', 'balance': '100.0'});
        }
      );
      vm.setWebViewController(fakeController);
      
      // Allow async initialization to run
      await Future.delayed(const Duration(milliseconds: 50));
      
      // Intended behavior: Starts in copy_user. Prediction matches last played position.
      await vm.recordInput('A', selectedAction: 'B');
      
      expect(vm.predictionMode, equals('copy_user'));
      expect(vm.getAbsolutePrediction(), equals('B'),
          reason: 'When predictionMode is copy_user, prediction should match the last played position');

      // AI Mode transition: If copy_user prediction (which was B) is wrong (outcome was A), it transitions to ai_model.
      // Now let's play round with outcome C, where user played B (which is incorrect since prediction should be B)
      await vm.recordInput('C', selectedAction: 'B');
      
      expect(vm.predictionMode, equals('ai_model'));
      expect(vm.getAbsolutePrediction(), isNotNull,
          reason: 'When predictionMode is ai_model, it should query the hybrid response pipeline');
    });

    test('Hard Stop-Loss: triggers under default conditions (recoveryMode == 1) after 5 consecutive recovery losses', () async {
      final vm = SequenceAnalyzerViewModel();
      final overlayVM = OverlayButtonsViewModel();
      
      // We'll track if base bet is set
      double lastSetBet = 1.0;
      final fakeController = FakeInAppWebViewController(
        onEvaluateJavascript: (source, contentWorld) async {
          if (source.contains('checkAtPoint')) {
            return 'bet'; // Simulate loss
          }
          if (source.contains('parseFloat(el.value)') || source.contains('document.querySelectorAll(\'input\')')) {
            return lastSetBet.toString();
          }
          if (source.trim().endsWith(')')) {
            final lastParen = source.lastIndexOf('(');
            if (lastParen != -1 && lastParen < source.length - 1) {
              final param = source.substring(lastParen + 1, source.length - 1).trim();
              final amt = double.tryParse(param);
              if (amt != null) {
                lastSetBet = amt;
              }
            }
          }
          return jsonEncode({'coin': 'POL', 'balance': '100.0'});
        }
      );
      
      vm.setWebViewController(fakeController);
      overlayVM.setWebViewController(fakeController);
      overlayVM.setSequenceAnalyzerViewModel(vm);
      
      await overlayVM.initialize();
      
      // Set button positions to non-zero so visual outcome is not skipped and round can start
      for (var button in overlayVM.buttons) {
        button.position = const Offset(10.0, 10.0);
      }
      
      // Default condition
      overlayVM.recoveryMode = 1;
      
      // Speed up wait times in loop
      overlayVM.setSpeedMultiplier(1000.0);
      
      // Start flow
      await overlayVM.startSequence();
      
      // Wait for 5 consecutive recovery losses to occur
      await Future.delayed(const Duration(milliseconds: 600));
      
      overlayVM.stopSequence();
      
      // Verify stop-loss triggered:
      // - recovery locked (isRecoveryUnlocked == false)
      // - bet size reset to base
      expect(overlayVM.isRecoveryUnlocked, isFalse,
          reason: 'Recovery should be locked after hard stop-loss triggers');
    });

    test('Trap Breaker Lockdown: loss during Trap Breaker does NOT unlock recovery or escalate bet size', () async {
      final vm = SequenceAnalyzerViewModel();
      final overlayVM = OverlayButtonsViewModel();
      
      double lastSetBet = 1.0;
      final fakeController = FakeInAppWebViewController(
        onEvaluateJavascript: (source, contentWorld) async {
          if (source.contains('checkAtPoint')) {
            return 'bet'; // Simulate loss
          }
          if (source.contains('parseFloat(el.value)') || source.contains('document.querySelectorAll(\'input\')')) {
            return lastSetBet.toString();
          }
          if (source.trim().endsWith(')')) {
            final lastParen = source.lastIndexOf('(');
            if (lastParen != -1 && lastParen < source.length - 1) {
              final param = source.substring(lastParen + 1, source.length - 1).trim();
              final amt = double.tryParse(param);
              if (amt != null) {
                lastSetBet = amt;
              }
            }
          }
          return jsonEncode({'coin': 'POL', 'balance': '100.0'});
        }
      );
      
      vm.setWebViewController(fakeController);
      overlayVM.setWebViewController(fakeController);
      overlayVM.setSequenceAnalyzerViewModel(vm);
      
      await overlayVM.initialize();
      
      // Set button positions to non-zero so visual outcome is not skipped and round can start
      for (var button in overlayVM.buttons) {
        button.position = const Offset(10.0, 10.0);
      }
      
      overlayVM.setSpeedMultiplier(1000.0);
      
      await overlayVM.startSequence();
      
      // Wait to trigger Trap Breaker (triggers at consecutiveRecoveryLosses == 3)
      await Future.delayed(const Duration(milliseconds: 500));
      
      overlayVM.stopSequence();
      
      // During Trap Breaker lockdown:
      // - recovery should not be unlocked
      expect(overlayVM.isRecoveryUnlocked, isFalse);
      // - bet size should stay at base bet size
      expect(lastSetBet, equals(1.0));
    });

    test('predictionMode transition state machine: win stays in copy_user, 2 consecutive AI losses reset to copy_user', () async {
      final vm = SequenceAnalyzerViewModel();
      
      final fakeController = FakeInAppWebViewController(
        onEvaluateJavascript: (source, contentWorld) async {
          return jsonEncode({'coin': 'POL', 'balance': '100.0'});
        }
      );
      vm.setWebViewController(fakeController);
      
      // Allow async initialization to run
      await Future.delayed(const Duration(milliseconds: 50));

      // 1. Starts in copy_user. Prediction mode should be copy_user.
      expect(vm.predictionMode, equals('copy_user'));
      
      String pred = vm.getAbsolutePrediction();
      
      // Record a correct prediction (Outcome matches predicted action)
      await vm.recordInput(pred, selectedAction: pred);
      // It should remain in copy_user
      expect(vm.predictionMode, equals('copy_user'));

      // 2. Record an incorrect prediction (outcome different from predicted action)
      // This switches copy_user to ai_model.
      String nextPred = vm.getAbsolutePrediction();
      String incorrectOutcome = nextPred == 'A' ? 'B' : 'A';
      await vm.recordInput(incorrectOutcome, selectedAction: nextPred);
      // It should transition to ai_model
      expect(vm.predictionMode, equals('ai_model'));

      // 3. Win in AI mode: prediction is correct.
      // It should remain in ai_model, and incorrect streak resets to 0.
      String aiPred = vm.getAbsolutePrediction();
      await vm.recordInput(aiPred, selectedAction: aiPred);
      expect(vm.predictionMode, equals('ai_model'));

      // 4. Lose 1 round in AI mode: incorrect streak becomes 1.
      // It should remain in ai_model.
      String aiPred2 = vm.getAbsolutePrediction();
      String incorrectOutcome2 = aiPred2 == 'A' ? 'B' : 'A';
      await vm.recordInput(incorrectOutcome2, selectedAction: aiPred2);
      expect(vm.predictionMode, equals('ai_model'));

      // 5. Lose 2nd consecutive round in AI mode: incorrect streak becomes 2.
      // It should trigger panic switch back to copy_user.
      String aiPred3 = vm.getAbsolutePrediction();
      String incorrectOutcome3 = aiPred3 == 'A' ? 'B' : 'A';
      await vm.recordInput(incorrectOutcome3, selectedAction: aiPred3);
      expect(vm.predictionMode, equals('copy_user'));
    });

    test('R1: Non-deterministic voting noise added to consensus scores', () {
      final pipeline = PredictionPipelineService();
      
      final context = PredictionContext(
        inputs: [],
        incorrectStreak: 0,
        isV1EngineDominant: false,
        learningMemory: {},
        nonce: 1,
        timeSeriesEngine: TimeSeriesEngine(['A', 'B', 'C']),
        v13Engine: V13Engine(),
        shadowHunter: ShadowHunterEngine(),
      );

      final result = pipeline.generateHybridResponse(
        context,
        {'A': 0.33, 'B': 0.33, 'C': 0.33},
        {'A': 0.0, 'B': 0.0, 'C': 0.0},
        {'A': 1.0, 'B': 1.0, 'C': 1.0},
        {},
        [],
      );

      expect(['A', 'B', 'C'].contains(result.primaryPrediction), isTrue);
      expect(result.scores.length, equals(3));
    });

    test('R2: Strict 3-Loss Hard Limit / Circuit Breaker reload and halt', () async {
      final vm = SequenceAnalyzerViewModel();
      final overlayVM = OverlayButtonsViewModel();
      
      bool didReload = false;
      final fakeController = FakeInAppWebViewController(
        onReload: () {
          didReload = true;
        },
        onEvaluateJavascript: (source, contentWorld) async {
          if (source.contains('checkAtPoint')) {
            return 'bet'; // Simulate consecutive losses
          }
          return jsonEncode({'coin': 'POL', 'balance': '100.0'});
        }
      );
      
      vm.setWebViewController(fakeController);
      overlayVM.setWebViewController(fakeController);
      overlayVM.setSequenceAnalyzerViewModel(vm);
      
      await overlayVM.initialize();
      overlayVM.setSpeedMultiplier(1000.0);
      
      // Set button positions to non-zero so visual outcome is not skipped
      for (var button in overlayVM.buttons) {
        button.position = const Offset(10.0, 10.0);
      }
      
      // Start flow
      await overlayVM.startSequence();
      
      // Wait for circuit breaker to execute (triggered at streak >= 3)
      await Future.delayed(const Duration(milliseconds: 2000));
      
      expect(didReload, isTrue, reason: 'Circuit Breaker should reload WebView');
      expect(overlayVM.isSequenceRunning, isFalse, reason: 'Circuit Breaker should halt autoplay');
      expect(overlayVM.stopReason.contains('CIRCUIT BREAKER'), isTrue);
      expect(vm.advice.contains('CIRCUIT BREAKER'), isTrue);
    });
  });
}
