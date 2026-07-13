import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/views/splash_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('SplashView displays logo and loading indicator', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SplashView(),
        ),
      ),
    );

    // Verify that the logo icon exists
    expect(find.byType(Icon), findsWidgets);

    // Verify that the CircularProgressIndicator exists
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    // Verify that the specific text exists
    expect(find.text('Midnight Azure'), findsOneWidget);

    // Clear the pending timer
    await tester.pump(const Duration(seconds: 3));
  });
}
