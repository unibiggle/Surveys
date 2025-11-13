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

class _SketchPageState extends State<SketchPage> {
  final GlobalKey _repaintKey = GlobalKey();
  final List<_Stroke> _strokes = [];
  _Stroke? _current;
  Color _color = Colors.red;
  double _width = 4.0;

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

  Future<void> _save() async {
    final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted) return;
    Navigator.pop(context, bytes?.buffer.asUint8List());
  }

  void _start(Offset p) {
    _current = _Stroke(color: _color, width: _width, points: [p]);
    setState(() => _strokes.add(_current!));
  }

  void _update(Offset p) {
    setState(() => _current?.points.add(p));
  }

  void _end() {
    _current = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sketch'),
        actions: [
          IconButton(icon: const Icon(Icons.undo), onPressed: _strokes.isNotEmpty ? () => setState(() => _strokes.removeLast()) : null),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => _strokes.clear())),
          IconButton(icon: const Icon(Icons.save), onPressed: _save),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              _colorSwatch(Colors.red),
              _colorSwatch(Colors.green),
              _colorSwatch(Colors.blue),
              _colorSwatch(Colors.yellow.shade700),
              const SizedBox(width: 12),
              const Text('Width'),
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Center(
            child: AspectRatio(
              aspectRatio: 3 / 5,
              child: RepaintBoundary(
                key: _repaintKey,
                child: GestureDetector(
                  onPanStart: (d) => _start(d.localPosition),
                  onPanUpdate: (d) => _update(d.localPosition),
                  onPanEnd: (_) => _end(),
                  child: CustomPaint(
                    painter: _SketchPainter(strokes: _strokes, bg: _bgImage),
                    child: Container(color: Colors.white),
                  ),
                ),
              ),
            ),
          );
        },
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
}

class _Stroke {
  _Stroke({required this.color, required this.width, required this.points});
  final Color color;
  final double width;
  final List<Offset> points;
}

class _SketchPainter extends CustomPainter {
  _SketchPainter({required this.strokes, this.bg});
  final List<_Stroke> strokes;
  final ui.Image? bg;

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

    for (final s in strokes) {
      paint
        ..color = s.color
        ..strokeWidth = s.width;
      if (s.points.length < 2) continue;
      final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
      for (int i = 1; i < s.points.length; i++) {
        path.lineTo(s.points[i].dx, s.points[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SketchPainter oldDelegate) => true;
}
