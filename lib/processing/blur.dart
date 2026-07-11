import 'dart:typed_data';

/// Fast O(n) box blur of a single-channel byte plane using running sums.
/// Returns a new plane; the source is untouched.
Uint8List boxBlurPlane(Uint8List src, int width, int height, int radius) {
  if (radius < 1) return Uint8List.fromList(src);
  final tmp = Uint8List(src.length);
  final out = Uint8List(src.length);

  // Horizontal pass.
  for (var y = 0; y < height; y++) {
    final row = y * width;
    var sum = 0;
    for (var x = -radius; x <= radius; x++) {
      sum += src[row + x.clamp(0, width - 1)];
    }
    final window = radius * 2 + 1;
    for (var x = 0; x < width; x++) {
      tmp[row + x] = sum ~/ window;
      final addX = (x + radius + 1).clamp(0, width - 1);
      final subX = (x - radius).clamp(0, width - 1);
      sum += src[row + addX] - src[row + subX];
    }
  }

  // Vertical pass.
  for (var x = 0; x < width; x++) {
    var sum = 0;
    for (var y = -radius; y <= radius; y++) {
      sum += tmp[y.clamp(0, height - 1) * width + x];
    }
    final window = radius * 2 + 1;
    for (var y = 0; y < height; y++) {
      out[y * width + x] = sum ~/ window;
      final addY = (y + radius + 1).clamp(0, height - 1);
      final subY = (y - radius).clamp(0, height - 1);
      sum += tmp[addY * width + x] - tmp[subY * width + x];
    }
  }
  return out;
}

/// Box blur of an interleaved RGB plane (RGBA stride 4, alpha untouched),
/// used for the low-resolution bloom layer.
void boxBlurRgbaInPlace(Uint8List rgba, int width, int height, int radius) {
  if (radius < 1) return;
  for (var c = 0; c < 3; c++) {
    final plane = Uint8List(width * height);
    for (var p = 0; p < width * height; p++) {
      plane[p] = rgba[p * 4 + c];
    }
    final blurred = boxBlurPlane(plane, width, height, radius);
    for (var p = 0; p < width * height; p++) {
      rgba[p * 4 + c] = blurred[p];
    }
  }
}
