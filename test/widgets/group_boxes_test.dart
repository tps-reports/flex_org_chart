import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/flex_org_chart.dart';
import 'package:flex_org_chart/src/widgets/group_hulls.dart';

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
}
