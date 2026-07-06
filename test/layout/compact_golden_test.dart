import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/src/layout/compact.dart';
import 'package:flex_org_chart/src/layout/flextree.dart';

void main() {
  // Select fixtures by decoding once and checking the `compact` content flag
  // rather than by filename: `leaf-heavy-for-compact.json` is a NON-compact
  // fixture whose name ends in "compact" but not "-compact.json" is not a
  // safe boundary in general, so the flag is the only reliable signal.
  // (Task 3 lesson: decode each file exactly once and reuse the result,
  // rather than decoding once to filter and again inside the test.)
  final decoded = Directory('test/fixtures')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .map((f) => MapEntry(f, jsonDecode(f.readAsStringSync()) as Map<String, dynamic>))
      .where((e) => e.value['compact'] == true)
      .toList()
    ..sort((a, b) => a.key.path.compareTo(b.key.path));

  test('exactly 8 compact fixtures are selected', () {
    expect(decoded.length, 8);
  });

  for (final entry in decoded) {
    final file = entry.key;
    final fx = entry.value;
    test('matches JS compact layout: ${file.path}', () {
      final p = fx['params'] as Map<String, dynamic>;
      final rows = (fx['nodes'] as List).cast<Map<String, dynamic>>();

      final byId = <String, FlexNode<String>>{};
      final sizes = <String, (double, double)>{};
      FlexNode<String>? root;
      for (final r in rows) {
        byId[r['id'] as String] = FlexNode<String>(r['id'] as String);
        sizes[r['id'] as String] =
            ((r['width'] as num).toDouble(), (r['height'] as num).toDouble());
      }
      for (final r in rows) {
        final n = byId[r['id']]!;
        final pid = r['parentId'] as String?;
        if (pid == null) {
          root = n;
        } else {
          n.parent = byId[pid];
          byId[pid]!.children.add(n);
        }
      }

      final compact = CompactLayout<String>(
        nodeWidth: (n) => sizes[n.item]!.$1,
        nodeHeight: (n) => sizes[n.item]!.$2,
        compactMarginBetween: (p['compactMarginBetween'] as num).toDouble(),
        compactMarginPair: (p['compactMarginPair'] as num).toDouble(),
      );
      compact.computeDimensions(root!);

      // Size nodes exactly like the fixture generator's nodeSize callback.
      void size(FlexNode<String> n) {
        final dim = n.flexCompactDim;
        if (dim != null) {
          n.xSize = dim[0];
          n.ySize = dim[1];
        } else {
          n.xSize = sizes[n.item]!.$1 + (p['siblingsMargin'] as num);
          n.ySize = sizes[n.item]!.$2 + (p['childrenMargin'] as num);
        }
        n.children.forEach(size);
      }

      size(root);
      final neighbour = (p['neighbourMargin'] as num).toDouble();
      FlexTreeLayout<String>(
        spacing: (a, b) => identical(a.parent, b.parent) ? 0 : neighbour,
      ).run(root);
      compact.computePositions(root);

      for (final r in rows) {
        final n = byId[r['id']]!;
        expect(n.x, closeTo((r['x'] as num).toDouble(), 1e-6),
            reason: 'x of ${r['id']}');
        expect(n.y, closeTo((r['y'] as num).toDouble(), 1e-6),
            reason: 'y of ${r['id']}');
      }
    });
  }
}
