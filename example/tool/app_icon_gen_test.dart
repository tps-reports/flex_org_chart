// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regenerates the example app's macOS icon set from vector drawing code.
///
/// This lives under `tool/`, not `test/`, so a plain `flutter test` run
/// (the CI/publish gate) never executes it — icon generation is a
/// deliberate, on-demand step:
///
///   cd example && flutter test tool/app_icon_gen_test.dart
///
/// The icon is an org-chart glyph in the demo app's own palette (indigo
/// seed theme, deep-purple `Connection` accent): a Big Sur-style rounded
/// square with an indigo gradient, a white three-node tree joined by the
/// same elbow links the chart draws, and a dashed purple connection arc
/// with an arrowhead between the outer leaf nodes.
///
/// Every size in `AppIcon.appiconset` is re-rendered natively rather than
/// downscaled from the 1024px master: stroke widths and dash lengths are
/// clamped to a device-pixel minimum per size, which keeps the glyph
/// legible at 16px where a naive downscale turns the lines to mush.
void main() {
  test('generates macOS AppIcon.appiconset PNGs', () async {
    const sizes = [16, 32, 64, 128, 256, 512, 1024];
    final dir = Directory(
      '${Directory.current.path}/macos/Runner/Assets.xcassets/AppIcon.appiconset',
    );
    expect(
      dir.existsSync(),
      isTrue,
      reason:
          'run from example/: cd example && '
          'flutter test tool/app_icon_gen_test.dart',
    );

    for (final px in sizes) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      _paintIcon(canvas, px.toDouble());
      final image = recorder.endRecording().toImageSync(px, px);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${dir.path}/app_icon_$px.png');
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      print('Wrote ${file.path} (${bytes.lengthInBytes} bytes)');
    }
  });
}

/// Paints the icon at [px] × [px] device pixels.
///
/// Geometry is authored in a 1024-unit design space and scaled by
/// `px / 1024`; stroke widths and dash lengths are clamped in device
/// pixels so the smallest sizes keep visible, crisp lines.
void _paintIcon(Canvas canvas, double px) {
  final u = px / 1024;
  Offset p(double x, double y) => Offset(x * u, y * u);

  // Big Sur-style rounded square: 824 units centered in 1024, with the
  // standard transparent margin the macOS Dock expects.
  final squircle = RRect.fromRectAndRadius(
    Rect.fromLTWH(100 * u, 100 * u, 824 * u, 824 * u),
    Radius.circular(185 * u),
  );

  if (px >= 64) {
    canvas.drawRRect(
      squircle.shift(Offset(0, 8 * u)),
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 16 * u),
    );
  }

  canvas.drawRRect(
    squircle,
    Paint()
      ..shader = ui.Gradient.linear(p(512, 100), p(512, 924), [
        const Color(0xFF5C6BC0),
        const Color(0xFF283593),
      ]),
  );
  canvas.save();
  canvas.clipRRect(squircle);

  // Elbow links: root bottom → shared horizontal rail → each child top,
  // the same link shape LinkStyle draws in the chart itself.
  final linkStroke = math.max(16 * u, 1.2);
  final links = Paint()
    ..color = Colors.white.withValues(alpha: 0.92)
    ..style = PaintingStyle.stroke
    ..strokeWidth = linkStroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  const railY = 520.0;
  final linkPath = Path()
    ..moveTo(512 * u, 430 * u)
    ..lineTo(512 * u, railY * u)
    ..moveTo(317 * u, railY * u)
    ..lineTo(707 * u, railY * u);
  for (final x in [317.0, 512.0, 707.0]) {
    linkPath
      ..moveTo(x * u, railY * u)
      ..lineTo(x * u, 585 * u);
  }
  canvas.drawPath(linkPath, links);

  // Nodes: white rounded rects, root above, three children below.
  final nodes = Paint()..color = Colors.white;
  RRect node(double cx, double cy, double w, double h) =>
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: p(cx, cy), width: w * u, height: h * u),
        Radius.circular(math.max(30 * u, 1.0)),
      );
  canvas.drawRRect(node(512, 370, 220, 130), nodes);
  for (final x in [317.0, 512.0, 707.0]) {
    canvas.drawRRect(node(x, 645, 160, 120), nodes);
  }

  // Dashed purple connection arc between the outer leaves, arrowhead at
  // the receiving end — the package's non-hierarchical Connection links.
  final arc = Path()
    ..moveTo(317 * u, 725 * u)
    ..quadraticBezierTo(512 * u, 880 * u, 700 * u, 733 * u);
  final arcStroke = math.max(14 * u, 1.1);
  final arcPaint = Paint()
    ..color = const Color(0xFFB388FF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = arcStroke
    ..strokeCap = StrokeCap.round;
  canvas.drawPath(
    _dash(arc, math.max(30 * u, 2.4), math.max(24 * u, 1.9)),
    arcPaint,
  );

  final metric = arc.computeMetrics().first;
  final end = metric.getTangentForOffset(metric.length)!;
  _arrowhead(
    canvas,
    end.position,
    end.vector.direction,
    math.max(44 * u, 3.5),
    arcPaint..style = PaintingStyle.fill,
  );

  canvas.restore();
}

/// Returns [source] rebuilt as dash segments of [on] units separated by
/// [off] units.
Path _dash(Path source, double on, double off) {
  final dashed = Path();
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      dashed.addPath(
        metric.extractPath(distance, math.min(distance + on, metric.length)),
        Offset.zero,
      );
      distance += on + off;
    }
  }
  return dashed;
}

/// Draws a filled triangular arrowhead of length [size] at [tip], pointing
/// along [direction] (radians).
void _arrowhead(
  Canvas canvas,
  Offset tip,
  double direction,
  double size,
  Paint paint,
) {
  const spread = 0.45;
  final path = Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(
      tip.dx - size * math.cos(direction - spread),
      tip.dy - size * math.sin(direction - spread),
    )
    ..lineTo(
      tip.dx - size * math.cos(direction + spread),
      tip.dy - size * math.sin(direction + spread),
    )
    ..close();
  canvas.drawPath(path, paint);
}
