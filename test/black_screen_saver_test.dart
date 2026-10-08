import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';
import 'package:golden_p/widgets/overlay_buttons_panel.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('OLED Black Screen Saver State & Lifecycle Tests', () {
    test('Default state of isBlackScreenSaverActive is false', () async {
      final viewModel = OverlayButtonsViewModel();
      await viewModel.initialize();

      expect(viewModel.isBlackScreenSaverActive, isFalse);
    });

    test('toggleBlackScreenSaver turns black screen saver on and off', () async {
      final viewModel = OverlayButtonsViewModel();
      await viewModel.initialize();

      expect(viewModel.isBlackScreenSaverActive, isFalse);

      viewModel.toggleBlackScreenSaver();
      expect(viewModel.isBlackScreenSaverActive, isTrue);

      viewModel.toggleBlackScreenSaver();
      expect(viewModel.isBlackScreenSaverActive, isFalse);
    });

    test('disableBlackScreenSaver turns off black screen saver when active', () async {
      final viewModel = OverlayButtonsViewModel();
      await viewModel.initialize();

      viewModel.toggleBlackScreenSaver();
      expect(viewModel.isBlackScreenSaverActive, isTrue);

      viewModel.disableBlackScreenSaver();
      expect(viewModel.isBlackScreenSaverActive, isFalse);

      // Calling disable again when already false is a no-op and stays false
      viewModel.disableBlackScreenSaver();
      expect(viewModel.isBlackScreenSaverActive, isFalse);
    });

    test('toggle and disable notify listeners appropriately', () async {
      final viewModel = OverlayButtonsViewModel();
      await viewModel.initialize();

      int notifications = 0;
      viewModel.addListener(() {
        notifications++;
      });

      viewModel.toggleBlackScreenSaver();
      expect(viewModel.isBlackScreenSaverActive, isTrue);
      expect(notifications, 1);

      viewModel.disableBlackScreenSaver();
      expect(viewModel.isBlackScreenSaverActive, isFalse);
      expect(notifications, 2);

      // No notification if already disabled
      viewModel.disableBlackScreenSaver();
      expect(notifications, 2);
    });
  });

  group('OLED Black Screen Saver UI & Widget Interaction Tests', () {
    testWidgets('OverlayButtonsPanel displays dark mode button and toggles state on tap', (WidgetTester tester) async {
      final viewModel = OverlayButtonsViewModel();
      await viewModel.initialize();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<OverlayButtonsViewModel>.value(
            value: viewModel,
            child: const Scaffold(
              body: OverlayButtonsPanel(
                screenSize: Size(800, 600),
                gameMode: GameMode.towers,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkModeFinder = find.byIcon(Icons.dark_mode_rounded);
      expect(darkModeFinder, findsOneWidget);

      // Check initial color is white60 (inactive)
      Icon iconWidget = tester.widget<Icon>(darkModeFinder);
      expect(iconWidget.color, Colors.white60);

      // Tap to activate
      await tester.tap(darkModeFinder);
      await tester.pumpAndSettle();

      expect(viewModel.isBlackScreenSaverActive, isTrue);
      iconWidget = tester.widget<Icon>(darkModeFinder);
      expect(iconWidget.color, Colors.amberAccent);

      // Tap again to deactivate
      await tester.tap(darkModeFinder);
      await tester.pumpAndSettle();

      expect(viewModel.isBlackScreenSaverActive, isFalse);
      iconWidget = tester.widget<Icon>(darkModeFinder);
      expect(iconWidget.color, Colors.white60);
    });

    testWidgets('Double-tap on OLED Black Screen Saver dismisses the overlay', (WidgetTester tester) async {
      final viewModel = OverlayButtonsViewModel();
      await viewModel.initialize();
      viewModel.toggleBlackScreenSaver();
      expect(viewModel.isBlackScreenSaverActive, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<OverlayButtonsViewModel>.value(
            value: viewModel,
            child: Scaffold(
              body: SizedBox.expand(
                child: Stack(
                  children: [
                    const Center(child: Text('Underlying Game View')),
                    Consumer<OverlayButtonsViewModel>(
                      builder: (context, overlayViewModel, _) {
                        if (!overlayViewModel.isBlackScreenSaverActive) {
                          return const SizedBox.shrink();
                        }
                        return Positioned.fill(
                          child: GestureDetector(
                            key: const Key('oled_gesture_detector'),
                            behavior: HitTestBehavior.opaque,
                            onDoubleTap: () => overlayViewModel.disableBlackScreenSaver(),
                            child: Container(
                              color: Colors.black,
                              child: const Center(
                                child: Opacity(
                                  opacity: 0.30,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.bedtime_rounded,
                                        size: 44,
                                        color: Colors.white,
                                      ),
                                      SizedBox(height: 16),
                                      Text(
                                        'โหมดประหยัดพลังงาน OLED (บอทกำลังทำงาน)',
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'แตะหน้าจอ 2 ครั้งติดกัน (Double Tap) เพื่อเปิดหน้าจอ',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify the OLED elements are present
      expect(find.text('โหมดประหยัดพลังงาน OLED (บอทกำลังทำงาน)'), findsOneWidget);
      expect(find.text('แตะหน้าจอ 2 ครั้งติดกัน (Double Tap) เพื่อเปิดหน้าจอ'), findsOneWidget);
      expect(find.byIcon(Icons.bedtime_rounded), findsOneWidget);

      // Perform double tap gesture on the detector
      final gestureFinder = find.byKey(const Key('oled_gesture_detector'));
      await tester.tap(gestureFinder);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(gestureFinder);
      await tester.pumpAndSettle();

      // State is now disabled and overlay is gone
      expect(viewModel.isBlackScreenSaverActive, isFalse);
      expect(find.text('โหมดประหยัดพลังงาน OLED (บอทกำลังทำงาน)'), findsNothing);
      expect(find.text('Underlying Game View'), findsOneWidget);
    });
  });
}
