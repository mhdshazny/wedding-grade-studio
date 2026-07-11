import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Before/after comparison with a draggable split handle. Zoom and pan are
/// shared between both sides via a single [TransformationController]; the
/// split line stays in screen space so it works at any zoom level.
class BeforeAfterViewer extends StatefulWidget {
  final ui.Image before;
  final ui.Image after;

  const BeforeAfterViewer({
    super.key,
    required this.before,
    required this.after,
  });

  @override
  State<BeforeAfterViewer> createState() => _BeforeAfterViewerState();
}

class _BeforeAfterViewerState extends State<BeforeAfterViewer> {
  final _controller = TransformationController();
  double _split = 0.5;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _fitted(ui.Image image) {
    return Center(
      child: AspectRatio(
        aspectRatio: image.width / image.height,
        child: RawImage(image: image, fit: BoxFit.fill),
      ),
    );
  }

  Widget _viewer(ui.Image image) {
    return InteractiveViewer(
      transformationController: _controller,
      minScale: 1,
      maxScale: 10,
      clipBehavior: Clip.hardEdge,
      child: _fitted(image),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final splitX = (_split * width).clamp(12.0, width - 12.0);
        return GestureDetector(
          onDoubleTap: () =>
              setState(() => _controller.value = Matrix4.identity()),
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: [
              // Graded result underneath (receives zoom/pan gestures).
              _viewer(widget.after),
              // Original on top, clipped to the left of the split line.
              IgnorePointer(
                child: ClipRect(
                  clipper: _SplitClipper(splitX),
                  child: _viewer(widget.before),
                ),
              ),
              // Split line + drag grip.
              Positioned(
                left: splitX - 1,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(width: 2, color: Colors.white70),
                ),
              ),
              Positioned(
                left: splitX - 22,
                top: 0,
                bottom: 0,
                width: 44,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _split = ((splitX + details.delta.dx) / width)
                          .clamp(0.02, 0.98);
                    });
                  },
                  child: Center(
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white70),
                        boxShadow: const [
                          BoxShadow(color: Colors.black45, blurRadius: 8),
                        ],
                      ),
                      child: const Icon(Icons.unfold_more, size: 20),
                    ),
                  ),
                ),
              ),
              Positioned(left: 12, top: 12, child: _label(context, 'Before')),
              Positioned(right: 12, top: 12, child: _label(context, 'After')),
            ],
          ),
        );
      },
    );
  }

  Widget _label(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: const TextStyle(fontSize: 12, color: Colors.white)),
    );
  }
}

class _SplitClipper extends CustomClipper<Rect> {
  final double splitX;
  const _SplitClipper(this.splitX);

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, 0, splitX, size.height);

  @override
  bool shouldReclip(_SplitClipper oldClipper) => oldClipper.splitX != splitX;
}
