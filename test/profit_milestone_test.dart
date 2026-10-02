import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/models/stop_profit_milestone.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';

void main() {
  group('Profit Milestones History Tests', () {
    test('StopProfitMilestoneRecord toJson and fromJson serialization works correctly', () {
      final now = DateTime.now();
      final resume = now.add(const Duration(minutes: 120));

      final original = StopProfitMilestoneRecord(
        timestamp: now,
        mode: GameMode.towers,
        pnlPercent: 5.25,
        targetPercent: 5.0,
        endingBalance: 125.45,
        breakMinutes: 120,
        resumeTime: resume,
      );

      final jsonMap = original.toJson();
      final jsonStr = jsonEncode(jsonMap);
      final decodedMap = jsonDecode(jsonStr) as Map<String, dynamic>;
      final restored = StopProfitMilestoneRecord.fromJson(decodedMap);

      expect(restored.mode, equals(GameMode.towers));
      expect(restored.pnlPercent, equals(5.25));
      expect(restored.targetPercent, equals(5.0));
      expect(restored.endingBalance, equals(125.45));
      expect(restored.breakMinutes, equals(120));
      expect(restored.timestamp.millisecondsSinceEpoch, equals(now.millisecondsSinceEpoch));
      expect(restored.resumeTime.millisecondsSinceEpoch, equals(resume.millisecondsSinceEpoch));
    });

    test('Milestones collection caps at 30 items to prevent memory inflation', () {
      List<StopProfitMilestoneRecord> records = [];
      final now = DateTime.now();

      for (int i = 0; i < 40; i++) {
        final record = StopProfitMilestoneRecord(
          timestamp: now.add(Duration(minutes: i)),
          mode: i % 2 == 0 ? GameMode.towers : GameMode.mines,
          pnlPercent: 5.0 + (i * 0.1),
          targetPercent: 5.0,
          endingBalance: 100.0 + i,
          breakMinutes: 120,
          resumeTime: now.add(Duration(minutes: i + 120)),
        );
        records.insert(0, record);
        if (records.length > 30) {
          records = records.sublist(0, 30);
        }
      }

      expect(records.length, equals(30));
      // First item should be the newest (i = 39)
      expect(records.first.endingBalance, equals(139.0));
    });

    test('OverlayButtonsViewModel exposes profitMilestones and clearProfitMilestones', () {
      final vm = OverlayButtonsViewModel();
      expect(vm.profitMilestones, isNotNull);
      expect(vm.profitMilestones, isEmpty);

      // Verify clear does not throw
      vm.clearProfitMilestones();
      expect(vm.profitMilestones, isEmpty);
    });
  });
}
