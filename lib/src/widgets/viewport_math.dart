import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../model/geometry.dart';

/// Returns a [Matrix4] that scales [bounds] to fit within [viewport] (minus
/// [padding] on every side) and centers it, clamped to `[minScale, maxScale]`.
///
/// Pure function: no widget/controller state involved, which is what makes
/// it cheap to unit test without pumping a widget tree.
Matrix4 fitTransform({
  required LayoutRect bounds,
  required Size viewport,
  double padding = 40,
  double minScale = 0.001,
  double maxScale = 20,
}) {
  final availW = math.max(1.0, viewport.width - padding * 2);
  final availH = math.max(1.0, viewport.height - padding * 2);
  var scale = math.min(availW / bounds.width, availH / bounds.height);
  scale = scale.clamp(minScale, maxScale);
  return centerTransform(rect: bounds, viewport: viewport, scale: scale);
}

/// Returns a [Matrix4] that maps the center of [rect] to the center of
/// [viewport] at the given [scale] (no clamping — callers that want fit
/// behavior should go through [fitTransform]).
Matrix4 centerTransform({
  required LayoutRect rect,
  required Size viewport,
  required double scale,
}) {
  final tx = viewport.width / 2 - rect.centerX * scale;
  final ty = viewport.height / 2 - rect.centerY * scale;
  return Matrix4.identity()
    ..translateByDouble(tx, ty, 0.0, 1.0)
    ..scaleByDouble(scale, scale, scale, 1.0);
}
