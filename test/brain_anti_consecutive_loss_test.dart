import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/engines/omni_matrix_engine.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/models/history_entry.dart';
import 'package:golden_p/models/prediction_context.dart';
import 'package:golden_p/services/prediction_pipeline_service.dart';
import 'package:golden_p/engines/time_series_engine.dart';
import 'package:golden_p/engines/v13_engine.dart';
import 'package:golden_p/engines/shadow_hunter_engine.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';

void main() {
  group('Brain Anti-Consecutive Loss Verification Tests', () {
    test('OmniMatrix Veto prevents choosing lastLoss during loss streak', () {
      final engine = OmniMatrixEngine.instance;
      engine.resetAllMemory(mode: GameMode.towers);

      // Record a loss on column C
      engine.recordOutcome(
        chosenColumn: 'C',
        won: false,
        revealedBombPos: 'C',
        mode: GameMode.towers,
      );

      expect(engine.getConsecutiveLosses(GameMode.towers), 1);

      // If AI Brain erroneously suggests 'C' (the box that just bombed),
      // OmniMatrix Risk Veto must intercept it and pick A or B!
      final result = engine.getNextPrediction(
        mode: GameMode.towers,
        aiBrainPrediction: 'C',
      );

      expect(result.column, isNot(equals('C')),
          reason: 'OmniMatrix must VETO picking column C because C just lost');
      expect(result.column, anyOf('A', 'B'));
    });

    test('V70 Inversion triggers on streak >= 2 and evades the bombed box', () {
      final pipeline = PredictionPipelineService();
      final context = PredictionContext(
        inputs: [
          HistoryEntry(value: 'B', isRed: true, selectedPos: 'A', actualBombPos: 'A', roundIndex: 1, timestamp: DateTime.now()),
          HistoryEntry(value: 'C', isRed: true, selectedPos: 'B', actualBombPos: 'B', roundIndex: 2, timestamp: DateTime.now()),
        ],
        incorrectStreak: 2,
        isV1EngineDominant: false,
        learningMemory: {},
        nonce: 2,
        timeSeriesEngine: TimeSeriesEngine(['A', 'B', 'C']),
        v13Engine: V13Engine(),
        shadowHunter: ShadowHunterEngine(),
      );

      final result = pipeline.generateHybridResponse(
        context,
        {'A': 1.0, 'B': 1.0, 'C': 1.0},
        {},
        {},
        {},
        [],
      );

      expect(result.primaryPrediction, isNot(equals('B')),
          reason: 'V70 Inversion must not pick the box that just bombed');
    });

    test('Debt is strictly preserved and only subtracted by actual profit, never trimmed or forgotten', () {
      final state = GameModeSessionState(GameMode.towers);
      state.activeNewLoss = 0.00050000;
      expect(state.totalAccumulatedLoss, equals(0.00050000));

      // Small profit win
      state.subtractProfitFromDebt(0.00010000);
      expect(state.totalAccumulatedLoss, equals(0.00040000));

      // Another win
      state.subtractProfitFromDebt(0.00020000);
      expect(state.totalAccumulatedLoss, equals(0.00020000));

      // Full recovery win
      state.subtractProfitFromDebt(0.00020000);
      expect(state.totalAccumulatedLoss, equals(0.0));
    });
  });
}
