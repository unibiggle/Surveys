import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

class SketchPage extends StatefulWidget {
  const SketchPage({super.key, this.background});
  final Uint8List? background;

  @override
  State<SketchPage> createState() => _SketchPageState();
}

enum _Tool { pen, shape, eraser }
enum _StrokeKind { pen, rect, circle, arrow, triangle, callout }
enum _ShapeKind { rect, circle, arrow, triangle, callout }

class _Stroke {
  _Stroke({required this.kind, required this.color, required this.width, required this.points});
  final _StrokeKind kind;
  final Color color;
  final double width;
  final List<Offset> points;
}

class _SketchPageState extends State<SketchPage> {
  final GlobalKey _repaintKey = GlobalKey();
  final TransformationController _transform = TransformationController();
  final List<_Stroke> _strokes = [];
  _Stroke? _current;
  bool _showWidthPicker = false;
  _ShapeKind _shapeKind = _ShapeKind.rect;
  Color _color = Colors.red;
  double _width = 4.0;
  bool _showGrid = false;
  bool _snapToGrid = false;
  final double _gridSize = 24.0;
  _Tool _tool = _Tool.pen;

  ui.Image? _bgImage;

  @override
  void initState() {
    super.initState();
    _loadBg();
  }

  Future<void> _loadBg() async {
    if (widget.background == null) return;
    final codec = await ui.instantiateImageCodec(widget.background!);
    final frame = await codec.getNextFrame();
    setState(() => _bgImage = frame.image);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted) return;
    Navigator.pop(context, bytes?.buffer.asUint8List());
  }

  Offset _snap(Offset p) {
    if (!_snapToGrid) return p;
    double snap(double v) => _gridSize * (v / _gridSize).roundToDouble();
    return Offset(snap(p.dx), snap(p.dy));
  }

  void _startAt(Offset scenePoint) {
    final p = _snap(scenePoint);
    _StrokeKind kind;
    if (_tool == _Tool.pen) {
      kind = _StrokeKind.pen;
    } else if (_tool == _Tool.shape) {
      switch (_shapeKind) {
        case _ShapeKind.rect:
          kind = _StrokeKind.rect;
          break;
        case _ShapeKind.circle:
          kind = _StrokeKind.circle;
          break;
        case _ShapeKind.arrow:
          kind = _StrokeKind.arrow;
          break;
        case _ShapeKind.triangle:
          kind = _StrokeKind.triangle;
          break;
        case _ShapeKind.callout:
          kind = _StrokeKind.callout;
          break;
      }
    } else {
      return;
    }
    _current = _Stroke(kind: kind, color: _color, width: _width, points: [p]);
    setState(() => _strokes.add(_current!));
  }

  void _updateAt(Offset scenePoint) {
    final p = _snap(scenePoint);
    setState(() => _current?.points.add(p));
  }

  void _endStroke() {
    _current = null;
  }

  void _eraseAt(Offset scenePoint) {
    final p = scenePoint;
    final threshold = _width + 4.0;
    setState(() {
      for (var i = _strokes.length - 1; i >= 0; i--) {
        final s = _strokes[i];
        final hit = _hitStroke(s, p, threshold);
        if (!hit) continue;
        if (_snapToGrid && s.kind == _StrokeKind.pen && s.points.length > 1) {
          final idx = _nearestPointIndex(s.points, p);
          if (idx <= 0) {
            _strokes.removeAt(i);
          } else if (idx < s.points.length) {
            s.points.removeRange(idx, s.points.length);
          }
        } else {
          _strokes.removeAt(i);
        }
        break;
      }
    });
  }

  bool _hitStroke(_Stroke s, Offset p, double threshold) {
    if (s.points.isEmpty) return false;
    switch (s.kind) {
      case _StrokeKind.pen:
        for (final pt in s.points) {
          if ((pt - p).distance <= threshold) return true;
        }
        return false;
      case _StrokeKind.rect:
      case _StrokeKind.circle:
      case _StrokeKind.arrow:
      case _StrokeKind.triangle:
      case _StrokeKind.callout:
        final rect = Rect.fromPoints(s.points.first, s.points.last);
        final outer = rect.inflate(threshold);
        if (!outer.contains(p)) return false;
        final inner = rect.deflate(threshold);
        if (inner.contains(p)) return false;
        return true;
    }
  }

  int _nearestPointIndex(List<Offset> points, Offset p) {
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final d = (points[i] - p).distanceSquared;
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  void _handlePointerDown(PointerDownEvent e) {
    final scene = _transform.toScene(e.localPosition);
    if (_tool == _Tool.eraser) {
      _eraseAt(scene);
    } else {
      _startAt(scene);
    }
  }

  void _handlePointerMove(PointerMoveEvent e) {
    final scene = _transform.toScene(e.localPosition);
    if (_tool == _Tool.eraser) {
      _eraseAt(scene);
    } else {
      _updateAt(scene);
    }
  }

  void _handlePointerUp(PointerUpEvent e) {
    if (_tool != _Tool.eraser) {
      _endStroke();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sketch'),
        actions: [
          IconButton(icon: const Icon(Icons.undo), onPressed: _strokes.isNotEmpty ? () => setState(() => _strokes.removeLast()) : null),
          IconButton(icon: const Icon(Icons.grid_on), onPressed: () => setState(() => _showGrid = !_showGrid), color: _showGrid ? Theme.of(context).colorScheme.primary : null),
          IconButton(icon: const Icon(Icons.save), onPressed: _save),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RepaintBoundary(
              key: _repaintKey,
              child: InteractiveViewer(
                transformationController: _transform,
                minScale: 1,
                maxScale: 4,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _handlePointerDown,
                  onPointerMove: _handlePointerMove,
                  onPointerUp: _handlePointerUp,
                  child: CustomPaint(
                    painter: _SketchPainter(
                      strokes: _strokes,
                      bg: _bgImage,
                      showGrid: _showGrid,
                      gridSize: _gridSize,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
          if (_showWidthPicker)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    const Text('Width'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Slider(
                        min: 1,
                        max: 16,
                        value: _width,
                        onChanged: (v) => setState(() => _width = v),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  _colorSwatch(Colors.black),
                  _colorSwatch(Colors.red),
                  _colorSwatch(Colors.green),
                  _colorSwatch(Colors.blue),
                  _colorSwatch(Colors.yellow.shade700),
                  const SizedBox(width: 8),
                  _toolButton(
                    context: context,
                    tool: _Tool.pen,
                    icon: Icons.brush,
                    tooltip: 'Pen',
                  ),
                  _shapeToolButton(context),
                  _toolButton(
                    context: context,
                    tool: _Tool.eraser,
                    icon: Icons.cleaning_services,
                    tooltip: 'Eraser',
                  ),
                  IconButton(
                    tooltip: 'Snap to grid',
                    icon: const Icon(Icons.grid_4x4),
                    color: _snapToGrid ? Theme.of(context).colorScheme.primary : null,
                    onPressed: () => setState(() => _snapToGrid = !_snapToGrid),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() => _showWidthPicker = !_showWidthPicker),
                    child: Text('Width ${_width.toStringAsFixed(0)}'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _colorSwatch(Color c) {
    final selected = _color.value == c.value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: GestureDetector(
        onTap: () => setState(() => _color = c),
        child: CircleAvatar(radius: selected ? 14 : 12, backgroundColor: c, child: selected ? const Icon(Icons.check, size: 14, color: Colors.white) : null),
      ),
    );
  }

  Widget _toolButton({
    required BuildContext context,
    required _Tool tool,
    required IconData icon,
    required String tooltip,
  }) {
    final isSelected = _tool == tool;
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkResponse(
        onTap: () => setState(() => _tool = tool),
        radius: 24,
        child: Container(
          decoration: isSelected
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                )
              : null,
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            color: isSelected ? color : null,
          ),
        ),
      ),
    );
  }

  Widget _shapeToolButton(BuildContext context) {
    final isSelected = _tool == _Tool.shape;
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkResponse(
        onTap: _showShapePicker,
        radius: 24,
        child: Container(
          decoration: isSelected
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                )
              : null,
          padding: const EdgeInsets.all(4),
          child: const Icon(Icons.crop_square),
        ),
      ),
    );
  }

  Future<void> _showShapePicker() async {
    setState(() => _tool = _Tool.shape);
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 24,
              runSpacing: 16,
              children: [
                _shapeOption(ctx, _ShapeKind.rect, Icons.crop_square, 'Square'),
                _shapeOption(ctx, _ShapeKind.circle, Icons.circle_outlined, 'Circle'),
                _shapeOption(ctx, _ShapeKind.arrow, Icons.arrow_right_alt, 'Arrow'),
                _shapeOption(ctx, _ShapeKind.triangle, Icons.change_history, 'Triangle'),
                _shapeOption(ctx, _ShapeKind.callout, Icons.chat_bubble_outline, 'Callout'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _shapeOption(BuildContext ctx, _ShapeKind kind, IconData icon, String label) {
    final isCurrent = _shapeKind == kind && _tool == _Tool.shape;
    final color = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: () {
        setState(() {
          _shapeKind = kind;
          _tool = _Tool.shape;
        });
        Navigator.of(ctx).pop();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: isCurrent
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  )
                : null,
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: isCurrent ? color : null),
          ),
          const SizedBox(height: 4),
          Text(label),
        ],
      ),
    );
  }
}

class _SketchPainter extends CustomPainter {
  _SketchPainter({required this.strokes, this.bg, required this.showGrid, required this.gridSize});
  final List<_Stroke> strokes;
  final ui.Image? bg;
  final bool showGrid;
  final double gridSize;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (bg != null) {
      final src = Rect.fromLTWH(0, 0, bg!.width.toDouble(), bg!.height.toDouble());
      final dst = Offset.zero & size;
      canvas.drawImageRect(bg!, src, dst, Paint());
    }

    if (showGrid) {
      final gridPaint = Paint()
        ..color = Colors.grey.withOpacity(0.2)
        ..strokeWidth = 0.5;
      for (double x = 0; x <= size.width; x += gridSize) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
      for (double y = 0; y <= size.height; y += gridSize) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    }

    for (final s in strokes) {
      paint
        ..color = s.color
        ..strokeWidth = s.width
        ..style = PaintingStyle.stroke;

      if (s.points.isEmpty) continue;

      switch (s.kind) {
        case _StrokeKind.pen:
          if (s.points.length == 1) {
            final p = s.points.first;
            canvas.drawCircle(p, s.width / 2, paint..style = PaintingStyle.fill);
            paint.style = PaintingStyle.stroke;
            continue;
          }
          final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
          for (int i = 1; i < s.points.length; i++) {
            path.lineTo(s.points[i].dx, s.points[i].dy);
          }
          canvas.drawPath(path, paint);
          break;
        case _StrokeKind.rect:
          final start = s.points.first;
          final end = s.points.last;
          final rect = Rect.fromPoints(start, end);
          canvas.drawRect(rect, paint);
          break;
        case _StrokeKind.circle:
          {
            final start = s.points.first;
            final end = s.points.last;
            final rect = Rect.fromPoints(start, end);
            canvas.drawOval(rect, paint);
          }
          break;
        case _StrokeKind.arrow:
          {
            final start = s.points.first;
            final end = s.points.last;
            final path = Path()
              ..moveTo(start.dx, start.dy)
              ..lineTo(end.dx, end.dy);
            canvas.drawPath(path, paint);

            final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
            const arrowSize = 12.0;
            final p1 = Offset(
              end.dx - arrowSize * math.cos(angle - math.pi / 6),
              end.dy - arrowSize * math.sin(angle - math.pi / 6),
            );
            final p2 = Offset(
              end.dx - arrowSize * math.cos(angle + math.pi / 6),
              end.dy - arrowSize * math.sin(angle + math.pi / 6),
            );
            final head = Path()
              ..moveTo(end.dx, end.dy)
              ..lineTo(p1.dx, p1.dy)
              ..moveTo(end.dx, end.dy)
              ..lineTo(p2.dx, p2.dy);
            canvas.drawPath(head, paint);
          }
          break;
        case _StrokeKind.triangle:
          {
            final start = s.points.first;
            final end = s.points.last;
            final rect = Rect.fromPoints(start, end);
            final top = Offset(rect.center.dx, rect.top);
            final left = Offset(rect.left, rect.bottom);
            final right = Offset(rect.right, rect.bottom);
            final path = Path()
              ..moveTo(top.dx, top.dy)
              ..lineTo(left.dx, left.dy)
              ..lineTo(right.dx, right.dy)
              ..close();
            canvas.drawPath(path, paint);
          }
          break;
        case _StrokeKind.callout:
          {
            final start = s.points.first;
            final end = s.points.last;
            final rect = Rect.fromPoints(start, end);
            canvas.drawRect(rect, paint);

            final tip = Offset(rect.left - 20, rect.center.dy);
            final top = Offset(rect.left, rect.center.dy - 10);
            final bottom = Offset(rect.left, rect.center.dy + 10);
            final path = Path()
              ..moveTo(tip.dx, tip.dy)
              ..lineTo(top.dx, top.dy)
              ..lineTo(bottom.dx, bottom.dy)
              ..close();
            canvas.drawPath(path, paint);
          }
          break;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SketchPainter oldDelegate) => true;
}
