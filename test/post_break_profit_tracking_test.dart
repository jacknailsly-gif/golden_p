import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/viewmodels/sequence_analyzer_viewmodel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Post-Break Profit Tracking Tests (REPRO & Verification)', () {
    test('Calling analyzer.resetSessionProfit sets new baseline and calculates both wins and losses accurately', () {
      final analyzer = SequenceAnalyzerViewModel(gameMode: GameMode.towers);

      // 1. Initial session: baseline 1.0 DOGE -> Profit 0.000%
      analyzer.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '1.00000000',
      });
      expect(analyzer.getProfitForMode(GameMode.towers), 0.0);

      // 2. Win round -> balance 1.05000000 (+5.0% profit)
      analyzer.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '1.05000000',
      });
      expect(analyzer.getProfitForMode(GameMode.towers), closeTo(5.0, 0.001));

      // 3. 2-3 hour break ends: resetSessionProfit called with 1.05000000
      analyzer.resetSessionProfit(mode: GameMode.towers, newBaseline: 1.05000000, coinType: 'DOGE');
      expect(analyzer.getProfitForMode(GameMode.towers), 0.0);
      expect(analyzer.getBalanceForMode(GameMode.towers), '1.05000000');

      // 4. Win round after break -> balance 1.10250000 (+5.0% profit from new baseline)
      analyzer.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '1.10250000',
      });
      expect(analyzer.getProfitForMode(GameMode.towers), closeTo(5.0, 0.001));

      // 5. Loss round after break -> balance 1.02900000 (-2.0% loss from new baseline 1.05)
      analyzer.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '1.02900000',
      });
      expect(analyzer.getProfitForMode(GameMode.towers), closeTo(-2.0, 0.001));
    });

    test('syncCurrentBalance ensures analyzer receives verified balance and notifies listeners', () {
      final analyzer = SequenceAnalyzerViewModel(gameMode: GameMode.towers);
      int notifyCount = 0;
      analyzer.addListener(() {
        notifyCount++;
      });

      analyzer.syncCurrentBalance(GameMode.towers, 1.25000000, coinType: 'DOGE');
      expect(analyzer.getBalanceForMode(GameMode.towers), '1.25000000');
      expect(notifyCount, greaterThan(0));

      // Further update via syncCurrentBalance moves profit
      analyzer.syncCurrentBalance(GameMode.towers, 1.37500000, coinType: 'DOGE');
      expect(analyzer.getProfitForMode(GameMode.towers), closeTo(10.0, 0.001));
    });

    test('Mines POL mode post-break profit tracking', () {
      final analyzer = SequenceAnalyzerViewModel(gameMode: GameMode.mines);

      analyzer.applyParsedBalanceResultForTesting(GameMode.mines, {
        'coin': 'POL',
        'balance': '5.00000000',
      });
      expect(analyzer.getProfitForMode(GameMode.mines), 0.0);

      // Win to 6.0 (+20%)
      analyzer.applyParsedBalanceResultForTesting(GameMode.mines, {
        'coin': 'POL',
        'balance': '6.00000000',
      });
      expect(analyzer.getProfitForMode(GameMode.mines), closeTo(20.0, 0.001));

      // Break finished, reset with new baseline 6.0
      analyzer.resetSessionProfit(mode: GameMode.mines, newBaseline: 6.00000000, coinType: 'POL');
      expect(analyzer.getProfitForMode(GameMode.mines), 0.0);

      // Loss to 5.88 (-2.0%)
      analyzer.applyParsedBalanceResultForTesting(GameMode.mines, {
        'coin': 'POL',
        'balance': '5.88000000',
      });
      expect(analyzer.getProfitForMode(GameMode.mines), closeTo(-2.0, 0.001));
    });
  });
}
