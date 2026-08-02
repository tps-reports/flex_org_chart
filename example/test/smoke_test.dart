import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/flex_org_chart.dart';
import 'package:flex_org_chart_example/main.dart';

void main() {
  testWidgets('demo app starts, renders the chart, and exposes its controls', (
    tester,
  ) async {
    await tester.pumpWidget(const DemoApp());
    // The initial fit animation and layout-change animation both run on
    // timers; let them settle before asserting on the tree.
    await tester.pumpAndSettle();

    // The chart rendered real node cards for the sample data, not an empty
    // or error state.
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('CEO'), findsOneWidget);
    expect(find.text('Margaret Hamilton'), findsOneWidget);

    // Every app-bar action from the brief is present and tappable.
    expect(find.byTooltip('Fit to screen'), findsOneWidget);
    expect(find.byTooltip('Expand all'), findsOneWidget);
    expect(find.byTooltip('Collapse all'), findsOneWidget);
    expect(find.byTooltip('Center on Hedy Lamarr'), findsOneWidget);
    expect(find.byTooltip('Highlight path to Hedy Lamarr'), findsOneWidget);

    // Layout-direction dropdown and compact switch are both present.
    expect(find.byType(DropdownButton<ChartLayout>), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets(
    'tapping the compact switch toggles compact mode without throwing',
    (tester) async {
      await tester.pumpWidget(const DemoApp());
      await tester.pumpAndSettle();

      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);

      final before = tester.widget<Switch>(switchFinder).value;
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      final after = tester.widget<Switch>(switchFinder).value;
      expect(after, !before);

      // Toggle back; still no exceptions, and the chart still renders.
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(find.text('Ada Lovelace'), findsOneWidget);
    },
  );

  testWidgets('expand all / collapse all buttons work without throwing', (
    tester,
  ) async {
    await tester.pumpWidget(const DemoApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Collapse all'));
    await tester.pumpAndSettle();
    // Collapsed to just the root.
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('Margaret Hamilton'), findsNothing);

    await tester.tap(find.byTooltip('Expand all'));
    await tester.pumpAndSettle();
    expect(find.text('Margaret Hamilton'), findsOneWidget);
  });

  testWidgets('tapping a node highlights its path without throwing', (
    tester,
  ) async {
    await tester.pumpWidget(const DemoApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ada Lovelace'));
    await tester.pumpAndSettle();
    // No exception; the status bar reflects the tap.
    expect(find.textContaining('Highlighted the path'), findsOneWidget);
  });
}
