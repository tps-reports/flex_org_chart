import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/flex_org_chart.dart';

typedef Row = ({String id, String? parentId});

/// Wraps [OrgChart] in a plain ancestor [StatefulWidget] and exposes that
/// ancestor's own `setState` to the test via [onRebuild] — used to simulate
/// "some unrelated ancestor rebuilds" without touching the controller.
class _RebuildHarness extends StatefulWidget {
  const _RebuildHarness({required this.controller, required this.onRebuild});
  final OrgChartController<Row> controller;
  final void Function(VoidCallback triggerRebuild) onRebuild;

  @override
  State<_RebuildHarness> createState() => _RebuildHarnessState();
}

class _RebuildHarnessState extends State<_RebuildHarness> {
  @override
  void initState() {
    super.initState();
    widget.onRebuild(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    return OrgChart<Row>(
      controller: widget.controller,
      compact: false,
      nodeBuilder: (_, n) =>
          Text('node-${n.id}', key: ValueKey('node-${n.id}')),
    );
  }
}

/// Mirrors the example app's `onExpandToggle: (_, __) => setState(() {})`
/// pattern: the ancestor rebuilds itself (recreating the `OrgChart` widget,
/// which re-runs `configure()`/`_relayout` via `didUpdateWidget`) purely in
/// reaction to the toggle callback, not because any of `OrgChart`'s own
/// props changed.
class _ToggleHarness extends StatefulWidget {
  const _ToggleHarness({required this.controller});
  final OrgChartController<Row> controller;

  @override
  State<_ToggleHarness> createState() => _ToggleHarnessState();
}

class _ToggleHarnessState extends State<_ToggleHarness> {
  @override
  Widget build(BuildContext context) {
    return OrgChart<Row>(
      controller: widget.controller,
      compact: false,
      nodeSize: (_) => (w: 100, h: 50),
      nodeBuilder: (_, n) =>
          Text('node-${n.id}', key: ValueKey('node-${n.id}')),
      onExpandToggle: (_, __) => setState(() {}),
    );
  }
}

void main() {
  testWidgets('expanding animates the new child in from its parent',
      (tester) async {
    final c = OrgChartController<Row>(data: const [
      (id: 'a', parentId: null),
      (id: 'b', parentId: 'a'),
    ], idOf: (r) => r.id, parentIdOf: (r) => r.parentId, initialExpandLevel: 0);
    await tester.pumpWidget(MaterialApp(
      home: OrgChart<Row>(
        controller: c,
        compact: false,
        nodeSize: (_) => (w: 100, h: 50),
        animationDuration: const Duration(milliseconds: 400),
        nodeBuilder: (_, n) =>
            Text('node-${n.id}', key: ValueKey('node-${n.id}')),
      ),
    ));
    await tester.pumpAndSettle();
    c.expand('a');
    await tester.pump(); // start animation
    final earlyY = tester.getTopLeft(find.byKey(const ValueKey('node-b'))).dy;
    await tester.pump(const Duration(milliseconds: 200));
    final midY = tester.getTopLeft(find.byKey(const ValueKey('node-b'))).dy;
    await tester.pumpAndSettle();
    final endY = tester.getTopLeft(find.byKey(const ValueKey('node-b'))).dy;
    // b enters at parent position and travels to its final spot
    expect(earlyY, lessThan(midY));
    expect(midY, lessThan(endY));
  });

  testWidgets('collapsing removes the child after the animation completes',
      (tester) async {
    final c = OrgChartController<Row>(data: const [
      (id: 'a', parentId: null),
      (id: 'b', parentId: 'a'),
    ], idOf: (r) => r.id, parentIdOf: (r) => r.parentId);
    await tester.pumpWidget(MaterialApp(
      home: OrgChart<Row>(
        controller: c,
        compact: false,
        nodeBuilder: (_, n) =>
            Text('node-${n.id}', key: ValueKey('node-${n.id}')),
      ),
    ));
    await tester.pumpAndSettle();
    c.collapse('a');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('node-b')), findsOneWidget); // mid-exit
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('node-b')), findsNothing);
  });

  // Regression tests for the "relayout mid-animation snaps/kills the layout
  // animation" bug: OrgChartController._relayout used to unconditionally
  // clobber `_previousState` on *every* call (highlight-only changes,
  // every configure() from didUpdateWidget), and the OrgChart widget's
  // `_mergedNodes`/EdgePainter read `previousState`/`state` live off the
  // controller — so any intervening notify mid-animation collapsed "from"
  // and "to" onto the same rects and the animation snapped to its end.

  testWidgets(
      'highlighting mid-expand-animation does not snap the animation to '
      'its final position', (tester) async {
    final c = OrgChartController<Row>(data: const [
      (id: 'a', parentId: null),
      (id: 'b', parentId: 'a'),
    ], idOf: (r) => r.id, parentIdOf: (r) => r.parentId, initialExpandLevel: 0);
    await tester.pumpWidget(MaterialApp(
      home: OrgChart<Row>(
        controller: c,
        compact: false,
        nodeSize: (_) => (w: 100, h: 50),
        animationDuration: const Duration(milliseconds: 400),
        nodeBuilder: (_, n) =>
            Text('node-${n.id}', key: ValueKey('node-${n.id}')),
      ),
    ));
    await tester.pumpAndSettle();

    c.expand('a');
    await tester.pump(); // start the enter animation
    await tester.pump(const Duration(milliseconds: 100)); // ~25% through

    // A highlight is a notify with no layout change — it must not disturb
    // the in-flight expand animation.
    c.highlight('a');
    await tester.pump(); // one frame after the highlight-triggered notify

    final midY = tester.getTopLeft(find.byKey(const ValueKey('node-b'))).dy;

    await tester.pumpAndSettle();
    final endY = tester.getTopLeft(find.byKey(const ValueKey('node-b'))).dy;

    // Bug symptom: the highlight-triggered notify made `_mergedNodes` (or,
    // pre-fix, the live controller reads it used) collapse "from" and "to"
    // onto the same rect, so `midY` came out equal to `endY` well before
    // the 400ms animation should have finished.
    expect(midY, isNot(closeTo(endY, 0.5)));
  });

  testWidgets(
      'an unrelated ancestor rebuild mid-collapse does not make the '
      'exiting node vanish before its exit animation finishes',
      (tester) async {
    final c = OrgChartController<Row>(data: const [
      (id: 'a', parentId: null),
      (id: 'b', parentId: 'a'),
    ], idOf: (r) => r.id, parentIdOf: (r) => r.parentId);
    VoidCallback? triggerRebuild;
    await tester.pumpWidget(MaterialApp(
      home: _RebuildHarness(
        controller: c,
        onRebuild: (fn) => triggerRebuild = fn,
      ),
    ));
    await tester.pumpAndSettle();

    c.collapse('a');
    await tester.pump(const Duration(milliseconds: 100)); // ~25% through exit
    expect(find.byKey(const ValueKey('node-b')), findsOneWidget); // mid-exit

    // Force a rebuild of an ancestor that has nothing to do with the chart
    // data — this recreates the OrgChart widget with identical props,
    // running didUpdateWidget -> configure() -> a redundant _relayout.
    triggerRebuild!();
    await tester.pump();

    // Bug symptom: the redundant relayout clobbered previousState to match
    // the (already-collapsed) current state, so the live-read merge lost
    // the exiting node entirely — it disappeared instead of continuing its
    // fade/slide out.
    expect(find.byKey(const ValueKey('node-b')), findsOneWidget); // mid-exit

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('node-b')), findsNothing);
  });

  testWidgets(
      'the example app\'s onExpandToggle: (_, __) => setState(() {}) '
      'pattern does not suppress the entrance animation', (tester) async {
    final c = OrgChartController<Row>(data: const [
      (id: 'a', parentId: null),
      (id: 'b', parentId: 'a'),
    ], idOf: (r) => r.id, parentIdOf: (r) => r.parentId, initialExpandLevel: 0);
    await tester.pumpWidget(MaterialApp(
      home: _ToggleHarness(controller: c),
    ));
    await tester.pumpAndSettle();

    // Tap the default expand button under the root, exactly like a user
    // would — this drives OrgChartController.setExpanded and then calls
    // onExpandToggle, which the harness wires to setState((){}) on the
    // *ancestor*, exactly like the example app.
    await tester.tap(find.byType(DefaultExpandButton));
    await tester.pump(); // apply the controller mutation + first frame
    await tester.pump(const Duration(milliseconds: 100)); // ~25% through

    final midY = tester.getTopLeft(find.byKey(const ValueKey('node-b'))).dy;

    await tester.pumpAndSettle();
    final endY = tester.getTopLeft(find.byKey(const ValueKey('node-b'))).dy;

    // Bug symptom: the ancestor's setState((){}) reaction to onExpandToggle
    // re-ran configure()/_relayout on the very next frame, which (pre-fix)
    // clobbered previousState and made the entering node's first
    // post-toggle frame already show it at its final position.
    expect(midY, isNot(closeTo(endY, 0.5)));
  });
}
