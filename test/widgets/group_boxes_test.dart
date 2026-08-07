import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/flex_org_chart.dart';

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
}
