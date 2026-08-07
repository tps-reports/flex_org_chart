import 'dart:ui';

import 'package:flutter/painting.dart' show TextStyle;

/// A user-declared department: the node with [rootId] plus all of its
/// currently visible descendants, drawn with a styled bounding box behind
/// the chart (see `GroupBoxPainter`). Declared via
/// `OrgChartController.groups`, mirroring how `Connection`s are declared.
class ChartGroup {
  /// Creates a group rooted at the node with id [rootId], optionally
  /// labeled and optionally styled (overriding the `OrgChart` widget's
  /// default `groupBoxStyle`).
  const ChartGroup({required this.rootId, this.label, this.style});

  /// Id of the group's root node, matching whatever `idOf` returns for
  /// it. A group whose root id matches no node is silently skipped.
  final String rootId;

  /// Optional text painted at the box's top-left. Never truncated: a
  /// label wider than its box overflows the box edge.
  final String? label;

  /// Optional style override for this group's box. `null` uses the
  /// `OrgChart` widget's `groupBoxStyle`.
  final GroupBoxStyle? style;
}

/// Visual style for a department bounding box: a rounded, optionally
/// dashed outline with a translucent fill and a top-left label.
class GroupBoxStyle {
  /// Creates a group-box style.
  const GroupBoxStyle({
    this.fill = const Color(0x14808080),
    this.borderColor = const Color(0xFF9E9E9E),
    this.borderWidth = 1.5,
    this.borderRadius = 12,
    this.padding = 16,
    this.labelStyle,
    this.dash,
  });

  /// Fill color painted inside the box, under the chart's nodes and
  /// links. Defaults to a translucent gray wash.
  final Color fill;

  /// Stroke color of the box outline.
  final Color borderColor;

  /// Stroke width of the box outline.
  final double borderWidth;

  /// Corner radius of the box outline and fill.
  final double borderRadius;

  /// Inflation applied to the hull of the group's member rects, on all
  /// four sides, in layout units.
  final double padding;

  /// Text style for the group's `ChartGroup.label`. Defaults to a 12px
  /// label in [borderColor] when `null`.
  final TextStyle? labelStyle;

  /// On/off segment lengths for a dashed outline, in logical pixels, or
  /// `null` for a solid outline. Entries must be positive; a pattern
  /// that is empty or contains a zero/negative entry cannot be validated
  /// here (const constructor) and falls back to a solid outline at paint
  /// time instead of dashing — the same contract as
  /// `ConnectionStyle.dash`.
  final List<double>? dash;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupBoxStyle &&
          runtimeType == other.runtimeType &&
          fill == other.fill &&
          borderColor == other.borderColor &&
          borderWidth == other.borderWidth &&
          borderRadius == other.borderRadius &&
          padding == other.padding &&
          labelStyle == other.labelStyle &&
          _dashEquals(dash, other.dash);

  @override
  int get hashCode => Object.hash(
    fill,
    borderColor,
    borderWidth,
    borderRadius,
    padding,
    labelStyle,
    dash == null ? null : Object.hashAll(dash!),
  );
}

bool _dashEquals(List<double>? a, List<double>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
