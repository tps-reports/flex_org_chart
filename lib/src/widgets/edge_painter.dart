import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../layout/link_geometry.dart';
import '../model/chart_state.dart';
import 'path_builder.dart';

/// Visual style for the parent-child connector lines drawn by [EdgePainter].
class LinkStyle {
  /// Creates a link style with the given [color] and [width].
  const LinkStyle({this.color = const Color(0xFFCCCCCC), this.width = 1.5});

  /// Stroke color of the connector line.
  final Color color;

  /// Stroke width of the connector line.
  final double width;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkStyle &&
          runtimeType == other.runtimeType &&
          color == other.color &&
          width == other.width;

  @override
  int get hashCode => Object.hash(color, width);
}

/// Paints every [LinkLayout] in [links] as a stroked path, translated by
/// [origin] so the chart's layout-space bounds line up with the widget's
/// (0,0)-origin canvas. Links whose child id is in [highlightedChildIds]
/// are painted with [highlightedStyle] in a second pass.
///
/// When [prevLinks] is supplied (Task 11: animated layout transitions), a
/// link present in both [prevLinks] and [links] (matched by [LinkLayout
/// .childId] — unique per link since every node has at most one parent) is
/// drawn by lerping each command's coordinates pairwise at progress [t].
/// This is safe without inspecting shapes at runtime because both path
/// generators ([verticalDiagonal]/[horizontalDiagonal] in link_geometry.dart)
/// always emit the same 8-command shape (M, L, L, L, C, L, C, L) for any
/// link. A link only in [links] (just appeared) fades in with opacity [t];
/// a link only in [prevLinks] (about to disappear) fades out with opacity
/// `1 - t` and is only considered while `t < 1`.
class EdgePainter extends CustomPainter {
  EdgePainter({
    required this.links,
    this.prevLinks,
    this.t = 1.0,
    required this.style,
    required this.origin,
    this.highlightedChildIds = const {},
    this.highlightedStyle = const LinkStyle(),
  });

  final List<LinkLayout> links;
  final List<LinkLayout>? prevLinks;
  final double t;
  final LinkStyle style;
  final Offset origin;
  final Set<String> highlightedChildIds;
  final LinkStyle highlightedStyle;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);

    final regular = <_AnimatedLink>[];
    final highlightedLinks = <_AnimatedLink>[];

    final prevById = <String, LinkLayout>{
      for (final l in prevLinks ?? const <LinkLayout>[]) l.childId: l,
    };
    for (final link in links) {
      final p = prevById[link.childId];
      final commands = p == null
          ? link.commands
          : _lerpCommands(p.commands, link.commands, t);
      final opacity = p == null ? t : 1.0;
      final bucket = highlightedChildIds.contains(link.childId)
          ? highlightedLinks
          : regular;
      bucket.add(_AnimatedLink(commands, opacity));
    }
    // Links only in the previous state (their child just left) keep fading
    // out until the animation completes; not worth building/painting once
    // `t` reaches 1 since their opacity would be exactly 0.
    if (prevLinks != null && t < 1.0) {
      final nextIds = {for (final l in links) l.childId};
      for (final p in prevLinks!) {
        if (nextIds.contains(p.childId)) continue;
        regular.add(_AnimatedLink(p.commands, 1.0 - t));
      }
    }

    _paintLinks(canvas, regular, style);
    _paintLinks(canvas, highlightedLinks, highlightedStyle);

    canvas.restore();
  }

  void _paintLinks(Canvas canvas, List<_AnimatedLink> items, LinkStyle s) {
    for (final item in items) {
      final paint = Paint()
        ..color = s.color
            .withValues(alpha: (s.color.a * item.opacity).clamp(0.0, 1.0))
        ..strokeWidth = s.width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(buildPath(item.commands), paint);
    }
  }

  @override
  bool shouldRepaint(EdgePainter oldDelegate) =>
      !identical(oldDelegate.links, links) ||
      !identical(oldDelegate.prevLinks, prevLinks) ||
      oldDelegate.t != t ||
      oldDelegate.style != style ||
      oldDelegate.origin != origin ||
      !setEquals(oldDelegate.highlightedChildIds, highlightedChildIds) ||
      oldDelegate.highlightedStyle != highlightedStyle;
}

/// One command list ready to paint, with its per-frame opacity multiplier
/// already resolved (see [EdgePainter.paint]).
class _AnimatedLink {
  _AnimatedLink(this.commands, this.opacity);
  final List<PathCommand> commands;
  final double opacity;
}

/// Lerps two command lists pairwise by index, assuming (per the generator
/// contract documented on [EdgePainter]) that both lists have identical
/// command shapes. Falls back to [b] outright if that contract is ever
/// violated (length mismatch) — better a visually wrong but valid path than
/// a crash mid-animation.
List<PathCommand> _lerpCommands(
    List<PathCommand> a, List<PathCommand> b, double t) {
  if (a.length != b.length) return b;
  return [for (var i = 0; i < a.length; i++) _lerpCommand(a[i], b[i], t)];
}

PathCommand _lerpCommand(PathCommand a, PathCommand b, double t) {
  double lerp(double x, double y) => x + (y - x) * t;
  if (a is MoveTo && b is MoveTo) {
    return MoveTo(lerp(a.x, b.x), lerp(a.y, b.y));
  }
  if (a is LineTo && b is LineTo) {
    return LineTo(lerp(a.x, b.x), lerp(a.y, b.y));
  }
  if (a is CubicTo && b is CubicTo) {
    return CubicTo(lerp(a.x1, b.x1), lerp(a.y1, b.y1), lerp(a.x2, b.x2),
        lerp(a.y2, b.y2), lerp(a.x, b.x), lerp(a.y, b.y));
  }
  return b; // shape mismatch: shouldn't happen per the generator contract
}
