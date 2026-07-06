import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/src/layout/flextree.dart';

void main() {
  final files = Directory('test/fixtures')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json') && !f.path.contains('compact'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    test('matches d3-flextree: ${file.path}', () {
      final fx = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final params = fx['params'] as Map<String, dynamic>;
      final rows = (fx['nodes'] as List).cast<Map<String, dynamic>>();

      final byId = <String, FlexNode<String>>{};
      FlexNode<String>? root;
      for (final r in rows) {
        final n = FlexNode<String>(r['id'] as String)
          ..xSize =
              ((r['width'] as num) + (params['siblingsMargin'] as num))
                  .toDouble()
          ..ySize =
              ((r['height'] as num) + (params['childrenMargin'] as num))
                  .toDouble();
        byId[r['id'] as String] = n;
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

      final neighbour = (params['neighbourMargin'] as num).toDouble();
      FlexTreeLayout<String>(
        spacing: (a, b) => identical(a.parent, b.parent) ? 0 : neighbour,
      ).run(root!);

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
