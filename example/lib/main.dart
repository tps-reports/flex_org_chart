import 'package:flutter/material.dart';
import 'package:flex_org_chart/flex_org_chart.dart';

/// A single row of sample org data: one employee, their manager, and title.
///
/// This shape (flat list + id/parentId accessors) is exactly what
/// [OrgChartController] expects — swap this for API-fetched records in a
/// real app without changing anything else below.
class Employee {
  const Employee(this.id, this.managerId, this.name, this.title);
  final String id;
  final String? managerId;
  final String name;
  final String title;
}

/// A ~25-person, 4-level org: CEO -> three C-suite executives -> six VPs/
/// directors -> individual contributors. VP Engineering (id '5') has six
/// direct reports, which is enough for compact mode to visibly fold them
/// into two columns underneath her.
const employees = <Employee>[
  // Level 0: CEO.
  Employee('1', null, 'Ada Lovelace', 'CEO'),

  // Level 1: C-suite, reporting to the CEO.
  Employee('2', '1', 'Grace Hopper', 'CTO'),
  Employee('3', '1', 'Katherine Johnson', 'CFO'),
  Employee('4', '1', 'Radia Perlman', 'COO'),

  // Level 2: VPs and directors, reporting to the C-suite.
  Employee('5', '2', 'Margaret Hamilton', 'VP Engineering'),
  Employee('6', '2', 'Barbara Liskov', 'VP Infrastructure'),
  Employee('7', '3', 'Adele Goldberg', 'VP Finance'),
  Employee('8', '3', 'Frances Allen', 'Director of Accounting'),
  Employee('9', '4', 'Annie Easley', 'VP Operations'),
  Employee('10', '4', 'Shafi Goldwasser', 'VP People'),

  // Level 3: individual contributors, reporting to the VPs/directors.
  // VP Engineering's six-person team is the leaf-heavy group compact mode
  // folds into two columns.
  Employee('11', '5', 'Hedy Lamarr', 'Senior Software Engineer'),
  Employee('12', '5', 'Mary Allen Wilkes', 'Senior Software Engineer'),
  Employee('13', '5', 'Evelyn Boyd Granville', 'Software Engineer'),
  Employee('14', '5', 'Joan Clarke', 'Software Engineer'),
  Employee('15', '5', 'Kathleen Booth', 'Software Engineer'),
  Employee('16', '5', 'Karen Sparck Jones', 'Software Engineer'),

  Employee('17', '6', 'Elizabeth Feinler', 'Infrastructure Engineer'),
  Employee('18', '6', 'Lynn Conway', 'Infrastructure Engineer'),

  Employee('19', '7', 'Erna Schneider Hoover', 'Financial Analyst'),
  Employee('20', '7', 'Sister Mary Kenneth Keller', 'Financial Analyst'),

  Employee('21', '8', 'Jean Bartik', 'Accountant'),

  Employee('22', '9', 'Ruth Teitelbaum', 'Operations Specialist'),
  Employee('23', '9', 'Betty Holberton', 'Operations Specialist'),
  Employee('24', '9', 'Marlyn Wescoff', 'Operations Specialist'),

  Employee('25', '10', 'Fran Bilas', 'People Partner'),
];

void main() => runApp(const DemoApp());

/// The demo application: a single screen with an [OrgChart] wired to every
/// v1 feature — controller navigation, compact/layout toggles, connections,
/// highlighting, and a custom node card.
class DemoApp extends StatefulWidget {
  const DemoApp({super.key});

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  late final controller = OrgChartController<Employee>(
    data: employees,
    idOf: (e) => e.id,
    parentIdOf: (e) => e.managerId,
    // Expand down through the VPs so the compact folding under VP
    // Engineering is visible immediately, without requiring a tap.
    initialExpandLevel: 3,
    connections: const [
      // Non-hierarchical, dotted-line relationships independent of the
      // reporting tree. Chosen between nodes that sit close together in
      // the layout (adjacent siblings, or a manager and a nearby peer's
      // report) so the dashed arcs are actually visible rather than
      // running for hundreds of pixels underneath unrelated cards.
      Connection(from: '7', to: '8', label: 'shared ledger'),
      Connection(from: '5', to: '17', label: 'infra pairing'),
    ],
  );

  var _layout = ChartLayout.top;
  var _compact = true;
  String _status = 'Tap a node to highlight its path to the CEO.';

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _setStatus(String message) => setState(() => _status = message);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flex_org_chart demo',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('flex_org_chart demo'),
          actions: [
            IconButton(
              tooltip: 'Fit to screen',
              icon: const Icon(Icons.fit_screen),
              onPressed: () {
                controller.fit();
                _setStatus('Fit the whole chart to the viewport.');
              },
            ),
            IconButton(
              tooltip: 'Expand all',
              icon: const Icon(Icons.unfold_more),
              onPressed: () {
                controller.expandAll();
                _setStatus('Expanded every node.');
              },
            ),
            IconButton(
              tooltip: 'Collapse all',
              icon: const Icon(Icons.unfold_less),
              onPressed: () {
                controller.collapseAll();
                _setStatus('Collapsed every node.');
              },
            ),
            IconButton(
              tooltip: "Center on Hedy Lamarr",
              icon: const Icon(Icons.center_focus_strong),
              onPressed: () {
                controller.centerNode('11');
                _setStatus(
                    'Centered on Hedy Lamarr (expanding collapsed ancestors '
                    'if needed).');
              },
            ),
            IconButton(
              tooltip: 'Highlight path to Hedy Lamarr',
              icon: const Icon(Icons.route),
              onPressed: () {
                controller.highlightPathToRoot('11');
                _setStatus('Highlighted the path from the CEO to Hedy '
                    'Lamarr.');
              },
            ),
            const SizedBox(width: 8),
            DropdownButton<ChartLayout>(
              value: _layout,
              dropdownColor: Theme.of(context).colorScheme.surface,
              underline: const SizedBox.shrink(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _layout = value);
                _setStatus('Switched layout direction to ${value.name}.');
              },
              items: [
                for (final layout in ChartLayout.values)
                  DropdownMenuItem(
                    value: layout,
                    child: Text(layout.name,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary)),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            const Text('Compact'),
            Switch(
              value: _compact,
              onChanged: (value) {
                setState(() => _compact = value);
                _setStatus(value
                    ? 'Compact mode on: leaf-heavy teams fold into columns.'
                    : 'Compact mode off: every node gets its own row.');
              },
            ),
          ],
        ),
        body: Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_status,
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: OrgChart<Employee>(
                controller: controller,
                layout: _layout,
                compact: _compact,
                nodeSize: (_) => (w: 220.0, h: 96.0),
                onNodeTap: (node) {
                  controller.highlightPathToRoot(node.id);
                  _setStatus(
                      'Highlighted the path from the CEO to ${node.data.name}.');
                },
                onExpandToggle: (node, expanded) => _setStatus(
                    '${expanded ? 'Expanded' : 'Collapsed'} '
                    "${node.data.name}'s team."),
                onZoom: (scale) =>
                    _setStatus('Zoom: ${scale.toStringAsFixed(2)}x'),
                connectionStyle: const ConnectionStyle(
                  color: Color(0xFF7C4DFF),
                  width: 2,
                  dash: [6, 6],
                ),
                nodeBuilder: (context, node) {
                  final highlighted = node.isHighlighted;
                  final onPath = node.isOnHighlightedPath;
                  return Card(
                    elevation: highlighted ? 6 : 1,
                    color: highlighted
                        ? Colors.pink.shade50
                        : onPath
                            ? Colors.pink.shade100
                            : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: highlighted
                          ? BorderSide(color: Colors.pink.shade400, width: 2)
                          : BorderSide.none,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            node.data.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            node.data.title,
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Spacer(),
                          Text(
                            node.totalSubordinates == 0
                                ? 'Individual contributor'
                                : '${node.totalSubordinates} report'
                                    '${node.totalSubordinates == 1 ? '' : 's'}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
