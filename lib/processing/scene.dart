import 'dart:math' as math;
import 'dart:typed_data';

/// Scene categories used to bias the grade per photo.
enum SceneType {
  indoor('Indoor'),
  outdoor('Outdoor'),
  goldenHour('Golden Hour'),
  shade('Shade'),
  directSunlight('Direct Sunlight'),
  reception('Reception'),
  night('Night'),
  flash('Flash');

  final String label;
  const SceneType(this.label);
}

/// Global statistics sampled from an image, used for normalization
/// (flattening) and scene detection.
class ImageStats {
  final double meanLuma; // 0..1
  final double stdLuma; // 0..1
  final double meanSat; // 0..1
  final double warmth; // meanR - meanB, roughly -1..1
  final double darkFrac; // fraction of pixels with luma < 0.08
  final double brightFrac; // fraction of pixels with luma > 0.85
  final double clipFrac; // fraction of pixels with luma > 0.97
  final double greenFrac; // fraction of vegetation-like pixels
  final double skyFrac; // fraction of sky-like pixels in the top half
  final double skinFrac; // fraction of skin-tone pixels
  final int lumaLo; // ~0.5th percentile of luma, 0..255
  final int lumaHi; // ~99.5th percentile of luma, 0..255

  const ImageStats({
    required this.meanLuma,
    required this.stdLuma,
    required this.meanSat,
    required this.warmth,
    required this.darkFrac,
    required this.brightFrac,
    required this.clipFrac,
    required this.greenFrac,
    required this.skyFrac,
    required this.skinFrac,
    required this.lumaLo,
    required this.lumaHi,
  });

  /// Samples the RGBA buffer (striding for speed) and gathers stats.
  static ImageStats analyze(Uint8List rgba, int width, int height) {
    final totalPx = width * height;
    // Aim for ~120k samples regardless of image size.
    final stride = math.max(1, (totalPx / 120000).round());

    final hist = Uint32List(256);
    var n = 0;
    var sumL = 0.0, sumL2 = 0.0, sumSat = 0.0, sumR = 0.0, sumB = 0.0;
    var dark = 0, bright = 0, clip = 0, green = 0, sky = 0, skin = 0;

    for (var p = 0; p < totalPx; p += stride) {
      final i = p * 4;
      final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
      final lum = (0.2126 * r + 0.7152 * g + 0.0722 * b);
      final l = lum / 255.0;
      hist[lum.round().clamp(0, 255)]++;
      n++;
      sumL += l;
      sumL2 += l * l;
      sumR += r / 255.0;
      sumB += b / 255.0;

      final mx = math.max(r, math.max(g, b));
      final mn = math.min(r, math.min(g, b));
      final sat = mx == 0 ? 0.0 : (mx - mn) / mx;
      sumSat += sat;

      if (l < 0.08) dark++;
      if (l > 0.85) bright++;
      if (l > 0.97) clip++;

      // Vegetation: green channel dominant, moderately saturated.
      if (g > r && g > b && sat > 0.15 && l > 0.08 && l < 0.85) green++;

      // Sky: blue dominant, bright, in the top half of the frame.
      final y = p ~/ width;
      if (b > r && b >= g && sat > 0.10 && l > 0.45 && y < height ~/ 2) {
        sky++;
      }

      // Skin: classic YCbCr window.
      final cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b;
      final cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b;
      if (cr >= 135 && cr <= 175 && cb >= 80 && cb <= 125 && r > g) skin++;
    }

    if (n == 0) n = 1;
    final mean = sumL / n;
    final variance = math.max(0.0, sumL2 / n - mean * mean);

    // Percentiles from the histogram.
    final loTarget = (n * 0.005).round();
    final hiTarget = (n * 0.995).round();
    var acc = 0;
    var lo = 0, hi = 255;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= loTarget) {
        lo = v;
        break;
      }
    }
    acc = 0;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= hiTarget) {
        hi = v;
        break;
      }
    }
    if (hi - lo < 32) {
      // Degenerate (nearly flat) image; avoid extreme stretching.
      lo = math.max(0, lo - 16);
      hi = math.min(255, hi + 16);
    }

    return ImageStats(
      meanLuma: mean,
      stdLuma: math.sqrt(variance),
      meanSat: sumSat / n,
      warmth: sumR / n - sumB / n,
      darkFrac: dark / n,
      brightFrac: bright / n,
      clipFrac: clip / n,
      greenFrac: green / n,
      skyFrac: sky / n,
      skinFrac: skin / n,
      lumaLo: lo,
      lumaHi: hi,
    );
  }
}

/// Heuristic scene classification from global stats.
SceneType detectScene(ImageStats s) {
  final outdoor = (s.greenFrac + s.skyFrac) > 0.06;

  // Flash look: bright subject against a dark ground, hard clipping,
  // typical of on-camera flash at receptions.
  if (s.darkFrac > 0.30 &&
      s.brightFrac > 0.06 &&
      s.clipFrac > 0.008 &&
      s.skinFrac > 0.04 &&
      !outdoor) {
    return SceneType.flash;
  }

  if (s.meanLuma < 0.20 && s.darkFrac > 0.40) {
    // Dark overall: warm dark frames read as reception, cool ones as night.
    return s.warmth > 0.04 && !outdoor ? SceneType.reception : SceneType.night;
  }

  if (outdoor) {
    if (s.warmth > 0.10 && s.meanLuma > 0.25 && s.meanLuma < 0.75) {
      return SceneType.goldenHour;
    }
    if (s.clipFrac > 0.015 && s.stdLuma > 0.24 && s.brightFrac > 0.12) {
      return SceneType.directSunlight;
    }
    if (s.warmth < 0.03 && s.clipFrac < 0.006) {
      return SceneType.shade;
    }
    return SceneType.outdoor;
  }

  if (s.meanLuma < 0.34 && s.warmth > 0.02) {
    return SceneType.reception;
  }
  return SceneType.indoor;
}
