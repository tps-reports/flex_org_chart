import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Wraps [child] with pinch-zoom, drag-pan, and scroll-wheel/trackpad
/// zoom-at-cursor, all expressed as updates to [transformationController].
///
/// This widget owns no state that outlives a single gesture — the actual
/// transform lives in [transformationController] so callers (the
/// [OrgChartController]-driven `fit`/`centerNode`/`zoomIn`/`zoomOut` calls)
/// can drive the same matrix programmatically.
class ChartViewport extends StatefulWidget {
  const ChartViewport({
    super.key,
    required this.child,
    required this.transformationController,
    this.scaleExtent = const (0.001, 20.0),
    this.onZoom,
    this.onInteractionStart,
    this.enabled = true,
  });

  final Widget child;

  /// Holds the current view matrix. This widget both reads it (to render
  /// [child] transformed) and writes it (in response to gestures); the
  /// owning widget writes it too (for programmatic fit/center/zoom).
  final TransformationController transformationController;

  /// `(min, max)` scale factors gestures are clamped to. Matches
  /// [OrgChartController]'s own `zoomBy` clamp so programmatic and gesture
  /// zoom agree on the limits.
  final (double, double) scaleExtent;

  /// Called after every gesture- or scroll-driven zoom with the new scale.
  final void Function(double scale)? onZoom;

  /// Called when the user starts interacting with the viewport — at the
  /// start of a pinch/drag gesture and before each scroll-wheel/trackpad
  /// zoom step. The owning widget uses this to stop any in-flight
  /// programmatic viewport animation so its tween doesn't keep ticking and
  /// fight the user's gesture for control of [transformationController].
  final VoidCallback? onInteractionStart;

  /// When false, pan/pinch/scroll gestures are ignored entirely — the
  /// transform can only change programmatically. The owning `OrgChart`
  /// disables the viewport while a drag-to-reparent is in flight so a
  /// second pointer can't pan or zoom under the drag (which would
  /// invalidate the gesture's frozen coordinate transform).
  final bool enabled;

  @override
  State<ChartViewport> createState() => _ChartViewportState();
}

class _ChartViewportState extends State<ChartViewport> {
  // Snapshot of the transform and focal point taken at the start of the
  // current scale/pan gesture. Every onScaleUpdate recomputes the full
  // transform from these two fixed values plus the gesture's *cumulative*
  // scale/focal-point (both of which Flutter reports relative to gesture
  // start, not incrementally) — see _composeGesture below. Recomputing from
  // a fixed start avoids compounding rounding/clamping error across
  // onScaleUpdate calls, which an incremental "multiply this update's delta
  // into the running matrix" approach is prone to once clamping kicks in.
  Matrix4? _gestureStart;
  Offset? _focalStart;

  // Local position of the most recent single-pointer down, tracked via the
  // raw Listener below rather than the gesture-arena/recognizer machinery.
  // Needed because ScaleGestureRecognizer.onStart's own
  // `details.localFocalPoint` is only trustworthy as a gesture-start anchor
  // when Scale wins its arena at pointer-down. If this viewport's Scale
  // recognizer instead competes against a sibling recognizer that only
  // rejects once the pointer has moved past its own slop (e.g. a node's
  // long-press when drag-to-reparent is enabled — see OrgChart), the arena
  // doesn't resolve until that same move event, and Scale's onStart fires
  // using its *already-updated* (post-move) focal point — onStart and the
  // paired first onUpdate then report the identical position, silently
  // eating that whole first movement. Anchoring to the raw down position
  // instead sidesteps arena-resolution timing entirely. Only applied for
  // single-pointer gestures (see onScaleStart) — a multi-finger pinch's
  // focal point is an average of every contact, which one pointer's down
  // position can't stand in for.
  Offset? _rawPointerDownLocal;

  TransformationController get _tc => widget.transformationController;

  double get _minScale => widget.scaleExtent.$1;
  double get _maxScale => widget.scaleExtent.$2;

  /// Applies a one-shot zoom by [factor] around [focal] (a point in the
  /// viewport's local coordinate space), clamped to [scaleExtent]. Used by
  /// the discrete scroll-wheel/trackpad path, where each event is a single
  /// isolated step from the current matrix (no gesture-start bookkeeping
  /// needed).
  void _applyScaleAt(double factor, Offset focal) {
    final current = _tc.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(_minScale, _maxScale);
    final applied = target / current;
    _tc.value = Matrix4.identity()
      ..translateByDouble(focal.dx, focal.dy, 0.0, 1.0)
      ..scaleByDouble(applied, applied, applied, 1.0)
      ..translateByDouble(-focal.dx, -focal.dy, 0.0, 1.0)
      ..multiply(_tc.value);
    widget.onZoom?.call(_tc.value.getMaxScaleOnAxis());
  }

  /// Recomputes the full transform for an in-progress pinch/pan gesture from
  /// the fixed gesture-start snapshot, per the formula documented on
  /// [_gestureStart]:
  ///
  /// `target = T(focalCurrent) * S(appliedScale) * T(-focalStart) * start`
  ///
  /// where `appliedScale` is derived by clamping the *absolute* target scale
  /// (`start scale * details.scale`) to [scaleExtent] and dividing back out,
  /// so pinching past the limit clamps cleanly instead of overshooting and
  /// snapping back. For a one-finger drag, `details.scale == 1.0`, so this
  /// degenerates to a plain pan by `focalCurrent - focalStart`.
  void _composeGesture(ScaleUpdateDetails details) {
    final start = _gestureStart;
    final focalStart = _focalStart;
    if (start == null || focalStart == null) return;
    final startScale = start.getMaxScaleOnAxis();
    final targetScale = (startScale * details.scale).clamp(
      _minScale,
      _maxScale,
    );
    final appliedScale = targetScale / startScale;
    final focalCurrent = details.localFocalPoint;
    _tc.value = Matrix4.identity()
      ..translateByDouble(focalCurrent.dx, focalCurrent.dy, 0.0, 1.0)
      ..scaleByDouble(appliedScale, appliedScale, appliedScale, 1.0)
      ..translateByDouble(-focalStart.dx, -focalStart.dy, 0.0, 1.0)
      ..multiply(start);
    if (details.scale != 1.0) {
      widget.onZoom?.call(_tc.value.getMaxScaleOnAxis());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Tracked independently of the gesture arena purely to recover the
      // true down position for onScaleStart's anchor — see
      // _rawPointerDownLocal's doc comment. Does not itself participate in
      // hit-testing/arena resolution.
      onPointerDown: (event) => _rawPointerDownLocal = event.localPosition,
      onPointerUp: (_) => _rawPointerDownLocal = null,
      onPointerCancel: (_) => _rawPointerDownLocal = null,
      onPointerSignal: (event) {
        if (!widget.enabled) return;
        if (event is PointerScrollEvent) {
          widget.onInteractionStart?.call();
          final factor = event.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1;
          _applyScaleAt(factor, event.localPosition);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (details) {
          if (!widget.enabled) return;
          // Must run before the transform snapshot below: stopping an
          // in-flight programmatic animation may not change _tc.value, but
          // ordering it first guarantees the snapshot is taken from a
          // matrix that nothing else is about to overwrite.
          widget.onInteractionStart?.call();
          _gestureStart = _tc.value.clone();
          _focalStart = details.pointerCount == 1
              ? (_rawPointerDownLocal ?? details.localFocalPoint)
              : details.localFocalPoint;
        },
        onScaleUpdate: (details) {
          if (!widget.enabled) return;
          _composeGesture(details);
        },
        onScaleEnd: (_) {
          _gestureStart = null;
          _focalStart = null;
        },
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            minHeight: 0,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: AnimatedBuilder(
              animation: _tc,
              builder: (context, _) => Transform(
                transform: _tc.value,
                alignment: Alignment.topLeft,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
