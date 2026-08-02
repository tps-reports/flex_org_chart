import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/flex_org_chart.dart';

typedef Row = ({String id, String? parentId});
Row r(String id, String? p) => (id: id, parentId: p);

OrgTree<Row> build(List<Row> rows) =>
    stratify<Row>(data: rows, idOf: (r) => r.id, parentIdOf: (r) => r.parentId);

void main() {
  test('builds single-root tree with correct parent/child wiring', () {
    final tree = build([r('a', null), r('b', 'a'), r('c', 'a'), r('d', 'b')]);
    expect(tree.roots, hasLength(1));
    final a = tree.nodeById('a')!;
    expect(a.children.map((n) => n.id), ['b', 'c']);
    expect(tree.nodeById('d')!.parent!.id, 'b');
    expect(tree.nodeById('d')!.depth, 2);
    expect(a.directSubordinates, 2);
    expect(a.totalSubordinates, 3);
  });

  test('supports multiple roots', () {
    final tree = build([r('a', null), r('x', null), r('b', 'a')]);
    expect(tree.roots.map((n) => n.id), ['a', 'x']);
  });

  test('throws on duplicate ids, listing them', () {
    expect(
      () => build([r('a', null), r('a', null)]),
      throwsA(
        isA<OrgChartDataException>().having((e) => e.offendingIds, 'ids', [
          'a',
        ]),
      ),
    );
  });

  test('throws on orphaned parentId', () {
    expect(
      () => build([r('a', null), r('b', 'ghost')]),
      throwsA(
        isA<OrgChartDataException>().having((e) => e.offendingIds, 'ids', [
          'b',
        ]),
      ),
    );
  });

  test('throws on cycle, listing unreachable ids', () {
    expect(
      () => build([r('a', null), r('b', 'c'), r('c', 'b')]),
      throwsA(
        isA<OrgChartDataException>().having(
          (e) => e.offendingIds,
          'ids',
          containsAll(['b', 'c']),
        ),
      ),
    );
  });

  test('throws on empty data', () {
    expect(() => build([]), throwsA(isA<OrgChartDataException>()));
  });
}
