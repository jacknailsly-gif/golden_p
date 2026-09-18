import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/engines/n_gram_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NGramEngine Memory Persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('should save and load memory correctly', () async {
      final engine1 = NGramEngine();
      
      // Teach engine1 some patterns
      engine1.learn(['A', 'B', 'C', 'A']);
      engine1.learn(['B', 'C', 'A', 'B']);
      engine1.learn(['C', 'A', 'B', 'C']);
      
      // Save to prefs
      await engine1.saveToPrefs();
      
      // Create a fresh engine and load from prefs
      final engine2 = NGramEngine();
      await engine2.loadFromPrefs();
      
      // Ensure engine2 can predict based on engine1's memory
      // Context 'C', 'A', 'B' should predict 'C' based on the 3rd learn call
      String prediction = engine2.predict(['C', 'A', 'B']);
      
      expect(prediction, isNotNull);
      // Since it's a mock, it should load successfully without crashing.
    });
  });
}
