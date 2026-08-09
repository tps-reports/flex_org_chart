import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/flex_org_chart.dart';
import 'package:flex_org_chart/src/widgets/group_hulls.dart';
import 'package:flex_org_chart/src/widgets/group_box_painter.dart';
import 'package:flex_org_chart/src/widgets/path_builder.dart';

typedef R = ({String id, String? parentId});

void main() {
  group('GroupBoxStyle', () {
    test('value equality', () {
      const a = GroupBoxStyle(borderColor: Color(0xFF112233), dash: [4, 2]);
      const b = GroupBoxStyle(borderColor: Color(0xFF112233), dash: [4, 2]);
      const c = GroupBoxStyle(borderColor: Color(0xFF112233), dash: [4, 3]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('defaults are the documented ones', () {
      const s = GroupBoxStyle();
      expect(s.fill, const Color(0x14808080));
      expect(s.borderColor, const Color(0xFF9E9E9E));
      expect(s.borderWidth, 1.5);
      expect(s.borderRadius, 12);
      expect(s.padding, 16);
      expect(s.labelStyle, isNull);
      expect(s.dash, isNull);
    });
  });

  group('ChartGroup', () {
    test('holds rootId, label, and optional style override', () {
      const g = ChartGroup(
        rootId: '3',
        label: 'Engineering',
        style: GroupBoxStyle(padding: 24),
      );
      expect(g.rootId, '3');
      expect(g.label, 'Engineering');
      expect(g.style!.padding, 24);
      expect(const ChartGroup(rootId: 'x').label, isNull);
    });
  });

  group('computeGroupHulls', () {
    // a -> (b, c); c -> d
    OrgTree<R> tree() => stratify<R>(
      data: const [
        (id: 'a', parentId: null),
        (id: 'b', parentId: 'a'),
        (id: 'c', parentId: 'a'),
        (id: 'd', parentId: 'c'),
      ],
      idOf: (r) => r.id,
      parentIdOf: (r) => r.parentId,
    );

    LayoutRect r100(double left, double top) => LayoutRect(left, top, 100, 50);

    test('hull unions visible member rects and inflates by padding', () {
      final t = tree();
      final hulls = computeGroupHulls<R>(
        groups: const [ChartGroup(rootId: 'c', label: 'C-team')],
        memberRects: {
          'a': r100(0, 0),
          'b': r100(-150, 100),
          'c': r100(150, 100),
          'd': r100(150, 200),
        },
        nodeById: t.nodeById,
        paddingOf: (_) => 10,
      );
      expect(hulls, hasLength(1));
      final h = hulls.single.rect;
      // Union of c (150,100,100,50) and d (150,200,100,50) = (150,100,100,150),
      // inflated by 10 on all sides:
      expect(h.left, 140);
      expect(h.top, 90);
      expect(h.width, 120);
      expect(h.height, 170);
    });

    test(
      'collapsed root: only the root rect is in memberRects → root-only box',
      () {
        final t = tree();
        final hulls = computeGroupHulls<R>(
          groups: const [ChartGroup(rootId: 'c')],
          memberRects: {
            'a': r100(0, 0),
            'b': r100(-150, 100),
            'c': r100(150, 100),
          },
          nodeById: t.nodeById,
          paddingOf: (_) => 10,
        );
        expect(hulls.single.rect.left, 140);
        expect(hulls.single.rect.height, 70); // 50 + 2*10
      },
    );

    test('root not in memberRects → no hull', () {
      final t = tree();
      final hulls = computeGroupHulls<R>(
        groups: const [ChartGroup(rootId: 'c')],
        memberRects: {'a': r100(0, 0)},
        nodeById: t.nodeById,
        paddingOf: (_) => 10,
      );
      expect(hulls, isEmpty);
    });

    test('unknown rootId is silently skipped', () {
      final t = tree();
      final hulls = computeGroupHulls<R>(
        groups: const [
          ChartGroup(rootId: 'ghost'),
          ChartGroup(rootId: 'a'),
        ],
        memberRects: {'a': r100(0, 0)},
        nodeById: t.nodeById,
        paddingOf: (_) => 0,
      );
      expect(hulls, hasLength(1));
      expect(hulls.single.group.rootId, 'a');
    });

    test('nested groups sort outer (shallower root) first', () {
      final t = tree();
      final hulls = computeGroupHulls<R>(
        groups: const [
          ChartGroup(rootId: 'c'),
          ChartGroup(rootId: 'a'),
        ],
        memberRects: {
          'a': r100(0, 0),
          'b': r100(-150, 100),
          'c': r100(150, 100),
          'd': r100(150, 200),
        },
        nodeById: t.nodeById,
        paddingOf: (_) => 0,
      );
      expect(hulls.map((h) => h.group.rootId), ['a', 'c']);
      expect(hulls.first.rootDepth, 0);
      expect(hulls.last.rootDepth, 1);
    });

    test('per-group padding via paddingOf', () {
      final t = tree();
      final hulls = computeGroupHulls<R>(
        groups: const [
          ChartGroup(rootId: 'b', style: GroupBoxStyle(padding: 30)),
          ChartGroup(rootId: 'c'),
        ],
        memberRects: {
          'b': r100(-150, 100),
          'c': r100(150, 100),
          'd': r100(150, 200),
        },
        nodeById: t.nodeById,
        paddingOf: (g) => g.style?.padding ?? 5,
      );
      final byId = {for (final h in hulls) h.group.rootId: h.rect};
      expect(byId['b']!.left, -180); // -150 - 30
      expect(byId['c']!.left, 145); // 150 - 5
    });
  });

  group('dashedPath', () {
    Path line() => Path()
      ..moveTo(0, 0)
      ..lineTo(100, 0);

    test('valid pattern produces multiple contours', () {
      final dashed = dashedPath(line(), const [10, 10]);
      expect(dashed.computeMetrics().length, greaterThan(1));
    });

    test('empty or non-positive patterns fall back to the source path', () {
      // Regression guard shared with ConnectionPainter: a zero entry must
      // not hang the dash walk (see connections_test.dart 'invalid dash
      // patterns').
      for (final bad in [
        <double>[],
        <double>[0],
        <double>[5, -1],
      ]) {
        final result = dashedPath(line(), bad);
        expect(result.computeMetrics().single.length, 100);
      }
    });
  });

  group('GroupBoxPainter', () {
    GroupHull hull({GroupBoxStyle? style, String? label}) => GroupHull(
      group: ChartGroup(rootId: 'x', label: label, style: style),
      rect: const LayoutRect(10, 20, 200, 100),
      rootDepth: 0,
    );

    test('resolves per-group style over the default', () {
      const override = GroupBoxStyle(borderColor: Color(0xFF123456));
      final p = GroupBoxPainter(
        hulls: [hull(style: override)],
        defaultStyle: const GroupBoxStyle(),
        origin: Offset.zero,
      );
      expect(p.styleFor(p.hulls.single), override);
      final q = GroupBoxPainter(
        hulls: [hull()],
        defaultStyle: const GroupBoxStyle(),
        origin: Offset.zero,
      );
      expect(q.styleFor(q.hulls.single), const GroupBoxStyle());
    });

    test('shouldRepaint on hull rect, origin, or default style change', () {
      final a = GroupBoxPainter(
        hulls: [hull()],
        defaultStyle: const GroupBoxStyle(),
        origin: Offset.zero,
      );
      final same = GroupBoxPainter(
        hulls: [hull()],
        defaultStyle: const GroupBoxStyle(),
        origin: Offset.zero,
      );
      // Same group instances are NOT used here (hull() builds fresh
      // ChartGroups), so repaint is expected; identical lists are not.
      final moved = GroupBoxPainter(
        hulls: [
          GroupHull(
            group: a.hulls.single.group,
            rect: const LayoutRect(0, 0, 5, 5),
            rootDepth: 0,
          ),
        ],
        defaultStyle: const GroupBoxStyle(),
        origin: Offset.zero,
      );
      expect(moved.shouldRepaint(a), isTrue);
      final identicalHulls = GroupBoxPainter(
        hulls: a.hulls,
        defaultStyle: const GroupBoxStyle(),
        origin: Offset.zero,
      );
      expect(identicalHulls.shouldRepaint(a), isFalse);
      expect(
        GroupBoxPainter(
          hulls: a.hulls,
          defaultStyle: const GroupBoxStyle(),
          origin: const Offset(9, 9),
        ).shouldRepaint(a),
        isTrue,
      );
      // `same` shares no hull instances with `a`, but rects and groups
      // compare by value/identity respectively; group instances differ →
      // conservative repaint is acceptable and expected:
      expect(same.shouldRepaint(a), isTrue);
    });
  });

  group('OrgChart group boxes', () {
    OrgChartController<R> makeChart({List<ChartGroup> groups = const []}) =>
        OrgChartController<R>(
          data: const [
            (id: 'a', parentId: null),
            (id: 'b', parentId: 'a'),
            (id: 'c', parentId: 'a'),
            (id: 'd', parentId: 'c'),
          ],
          idOf: (r) => r.id,
          parentIdOf: (r) => r.parentId,
          initialExpandLevel: 2,
          groups: groups,
        );

    Widget app(OrgChartController<R> c, {GroupBoxStyle? style}) => MaterialApp(
      home: Scaffold(
        body: OrgChart<R>(
          controller: c,
          compact: false,
          nodeSize: (_) => (w: 100, h: 50),
          groupBoxStyle: style ?? const GroupBoxStyle(),
          nodeBuilder: (context, node) =>
              Text('node-${node.id}', key: ValueKey('node-${node.id}')),
        ),
      ),
    );

    GroupBoxPainter painterOf(WidgetTester tester) {
      final paints = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .where((p) => p.painter is GroupBoxPainter);
      return paints.single.painter! as GroupBoxPainter;
    }

    testWidgets('declared group renders one hull, painted beneath nodes', (
      tester,
    ) async {
      final c = makeChart(
        groups: const [ChartGroup(rootId: 'c', label: 'C-team')],
      );
      await tester.pumpWidget(app(c));
      await tester.pumpAndSettle();
      final p = painterOf(tester);
      expect(p.hulls, hasLength(1));
      expect(p.hulls.single.group.rootId, 'c');
      // Bottom-most: the group-box CustomPaint is the first child of the
      // animated layer's Stack.
      final stack = tester.widget<Stack>(
        find
            .ancestor(
              of: find.byWidget(
                tester
                    .widgetList<CustomPaint>(find.byType(CustomPaint))
                    .firstWhere((w) => w.painter is GroupBoxPainter),
              ),
              matching: find.byType(Stack),
            )
            .first,
      );
      expect(
        ((stack.children.first as Positioned).child as CustomPaint).painter,
        isA<GroupBoxPainter>(),
      );
    });

    testWidgets('collapsing the root ancestor removes the hull', (
      tester,
    ) async {
      final c = makeChart(groups: const [ChartGroup(rootId: 'c')]);
      await tester.pumpWidget(app(c));
      await tester.pumpAndSettle();
      expect(painterOf(tester).hulls, hasLength(1));
      c.collapse('a'); // c hidden behind collapsed a
      await tester.pumpAndSettle();
      expect(painterOf(tester).hulls, isEmpty);
    });

    testWidgets('hull shrinks when collapsing inside the group', (
      tester,
    ) async {
      final c = makeChart(groups: const [ChartGroup(rootId: 'c')]);
      await tester.pumpWidget(app(c));
      await tester.pumpAndSettle();
      final before = painterOf(tester).hulls.single.rect.height;
      c.collapse('c'); // d leaves; box should end at root-only height
      await tester.pumpAndSettle();
      final after = painterOf(tester).hulls.single.rect.height;
      expect(after, lessThan(before));
    });

    testWidgets('per-group style override wins over the widget default', (
      tester,
    ) async {
      const override = GroupBoxStyle(borderColor: Color(0xFFAA0000));
      final c = makeChart(
        groups: const [ChartGroup(rootId: 'c', style: override)],
      );
      await tester.pumpWidget(app(c));
      await tester.pumpAndSettle();
      final p = painterOf(tester);
      expect(p.styleFor(p.hulls.single), override);
    });
  });
}
