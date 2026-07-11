import 'dart:math' as math;
import 'dart:typed_data';

import '../models/preset.dart';
import '../models/settings.dart';
import 'blur.dart';
import 'scene.dart';

typedef ProgressFn = void Function(double progress);

/// Everything that only depends on the source image (not on slider values).
/// Cached per photo so slider changes only re-run the grading passes.
class SceneCache {
  final ImageStats stats;
  final SceneType scene;
  final Uint8List flat; // flattened (LOG-like) RGBA base
  final Uint8List skinMask; // 0..255 soft skin membership
  final Uint8List lumaFlat; // luma plane of [flat]
  final Uint8List blurMed; // medium-radius blur of luma (clarity base)
  final Uint8List blurFine; // small-radius blur of luma (detail base)

  const SceneCache({
    required this.stats,
    required this.scene,
    required this.flat,
    required this.skinMask,
    required this.lumaFlat,
    required this.blurMed,
    required this.blurFine,
  });
}

/// Fully resolved grading parameters: preset + user sliders + scene bias.
class _Params {
  double exposure = 0;
  double temp = 0;
  double tint = 0;
  double contrast = 0;
  double highlights = 0;
  double shadows = 0;
  double whites = 0;
  double blackLift = 0;
  double satGlobal = 1;
  double vibrance = 0;
  double clarity = 0;
  double skinProtect = 0;
  double bloomBase = 0;
  double ghR = 0, ghG = 0, ghB = 0; // highlight tint
  double gmR = 0, gmG = 0, gmB = 0; // midtone tint
  double gsR = 0, gsG = 0, gsB = 0; // shadow tint
  // Per-hue-degree HSL mixer LUTs (index 0..359).
  Float32List hueShiftLut = Float32List(360);
  Float32List satMulLut = Float32List(360);
  Float32List lumMulLut = Float32List(360);
  bool hasHsl = false;
}

double _smoothstep(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Hue window with soft raised edges; handles the 360° wrap.
double _hueWindow(double h, double lo, double hi, double feather) {
  double w = 0;
  for (final hh in [h - 360, h, h + 360]) {
    final rise = _smoothstep(lo - feather, lo + feather, hh);
    final fall = 1 - _smoothstep(hi - feather, hi + feather, hh);
    final v = rise * fall;
    if (v > w) w = v;
  }
  return w;
}

class _BandRange {
  final HslBand band;
  final double lo, hi;
  final double scale;
  const _BandRange(this.band, this.lo, this.hi, this.scale);
}

_Params _resolve(GradePreset preset, GradeSettings s, SceneType scene) {
  final p = _Params()
    ..exposure = preset.exposure
    ..temp = preset.temp + s.warmth
    ..tint = preset.tint
    ..contrast = preset.contrast + s.contrast
    ..highlights = preset.highlights + s.highlights
    ..shadows = preset.shadows + s.shadows
    ..whites = preset.whites
    ..blackLift = preset.blackLift
    ..satGlobal = preset.saturation
    ..vibrance = preset.vibrance
    ..clarity = preset.clarity
    ..skinProtect = preset.skinProtect
    ..bloomBase = preset.bloomBase
    ..ghR = preset.highlightTint.r
    ..ghG = preset.highlightTint.g
    ..ghB = preset.highlightTint.b
    ..gmR = preset.midtoneTint.r
    ..gmG = preset.midtoneTint.g
    ..gmB = preset.midtoneTint.b
    ..gsR = preset.shadowTint.r
    ..gsG = preset.shadowTint.g
    ..gsB = preset.shadowTint.b;

  // Scene bias keeps the same look consistent across lighting conditions.
  if (preset.sceneAdaptive) {
    switch (scene) {
      case SceneType.indoor:
        p.temp += 0.05;
        p.exposure += 0.05;
      case SceneType.outdoor:
        break;
      case SceneType.goldenHour:
        p.temp -= 0.06; // already warm light — don't stack warmth
        p.highlights -= 0.10;
        p.bloomBase += 0.06;
      case SceneType.shade:
        p.temp += 0.12;
      case SceneType.directSunlight:
        p.highlights -= 0.20;
        p.shadows += 0.12;
        p.contrast -= 0.15;
        p.clarity -= 0.04;
      case SceneType.reception:
        p.exposure += 0.12;
        p.shadows += 0.14;
        p.clarity -= 0.05;
      case SceneType.night:
        p.exposure += 0.10;
        p.shadows += 0.10;
        p.clarity -= 0.06;
        p.satGlobal -= 0.04;
      case SceneType.flash:
        p.highlights -= 0.24;
        p.contrast -= 0.18;
        p.temp += 0.04;
        p.skinProtect = math.min(1, p.skinProtect + 0.10);
    }
  }

  // Build the per-degree HSL mixer LUTs. The Greens/Blues sliders scale
  // their band's strength (0.5 = as designed, 0 = off, 1 = double).
  final bands = <_BandRange>[
    _BandRange(preset.reds, -20, 20, 1), // wraps around 0
    _BandRange(preset.oranges, 20, 45, 1),
    _BandRange(preset.yellows, 45, 75, 1),
    _BandRange(preset.greens, 75, 165, s.greens * 2),
    _BandRange(preset.aquas, 165, 200, 1),
    _BandRange(preset.blues, 200, 260, s.blues * 2),
    _BandRange(preset.magentas, 260, 340, 1),
  ];
  var any = false;
  for (var h = 0; h < 360; h++) {
    var hueShift = 0.0, satMul = 1.0, lumMul = 1.0;
    for (final br in bands) {
      if (br.band.isNeutral || br.scale == 0) continue;
      final w = _hueWindow(h.toDouble(), br.lo, br.hi, 12) * br.scale;
      if (w <= 0) continue;
      hueShift += br.band.hueShift * w;
      satMul *= 1 + (br.band.sat - 1) * w;
      lumMul *= 1 + (br.band.lum - 1) * w;
      any = true;
    }
    p.hueShiftLut[h] = hueShift;
    p.satMulLut[h] = satMul;
    p.lumMulLut[h] = lumMul;
  }
  p.hasHsl = any;
  return p;
}

/// Film-like tone curve: exposure, shadow/highlight shaping, whites control,
/// a soft S and a creamy shoulder that never clips.
double _tone(double v, _Params p) {
  v *= math.pow(2.0, p.exposure).toDouble();
  if (v < 0) v = 0;

  // Highlights: weighted toward the top, eased so it never bands.
  final hw = _smoothstep(0.45, 1.0, v);
  v += p.highlights * 0.22 * hw * (1.05 - v);

  // Whites: scales the very top end (protects dress detail when negative).
  v *= 1 + p.whites * 0.35 * _smoothstep(0.65, 1.0, v);

  // Shadows: weighted toward the bottom, zero at pure black.
  final sw = 1 - _smoothstep(0.0, 0.55, v);
  v += p.shadows * 0.55 * sw * v * (1 - v);

  // Soft S-curve around the midtones.
  final vc = v.clamp(0.0, 1.0);
  final sig = vc * vc * (3 - 2 * vc);
  final mixAmt = (0.45 * p.contrast).clamp(-0.20, 0.70);
  v = vc + (sig - vc) * mixAmt;

  // Creamy shoulder roll-off — highlights compress instead of clipping.
  if (v > 0.82) {
    v = 0.82 + 0.18 * (1 - math.exp(-(v - 0.82) / 0.18));
  }
  return v.clamp(0.0, 1.0);
}

class Pipeline {
  /// Default cooperative yield so the UI stays responsive during long loops.
  static Future<void> _breathe() => Future.delayed(Duration.zero);

  // ---------------------------------------------------------------------
  // Step 2 — flatten to a neutral LOG-like base + Step 3 scene detection +
  // skin mask. All image-dependent, settings-independent work.
  // ---------------------------------------------------------------------
  static Future<SceneCache> buildCache(
    Uint8List original,
    int width,
    int height, {
    ProgressFn? onProgress,
  }) async {
    final n = width * height;
    final stats = ImageStats.analyze(original, width, height);
    final scene = detectScene(stats);
    onProgress?.call(0.10);

    // Flatten LUT: normalize levels, lift the floor, soften the ceiling and
    // brighten midtones slightly — every camera lands on the same base.
    // The normalization is applied at 70% and the range is floored so a
    // low-contrast source is not over-stretched (which would amplify color).
    final lut = Float32List(256);
    final lo = 0.70 * stats.lumaLo;
    final hi = 255 - 0.70 * (255 - stats.lumaHi);
    final range = math.max(140.0, hi - lo);
    for (var v = 0; v < 256; v++) {
      var x = ((v - lo) / range).clamp(0.0, 1.0);
      x = math.pow(x, 0.92).toDouble(); // midtone detail up
      lut[v] = 0.06 + 0.86 * x; // reduced contrast, nothing crushed/clipped
    }

    final flat = Uint8List(n * 4);
    const desat = 0.78; // pull saturation toward neutral
    for (var y = 0; y < height; y++) {
      final row = y * width * 4;
      for (var x = 0; x < width; x++) {
        final i = row + x * 4;
        final r = lut[original[i]];
        final g = lut[original[i + 1]];
        final b = lut[original[i + 2]];
        final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        flat[i] = ((luma + (r - luma) * desat) * 255).round().clamp(0, 255);
        flat[i + 1] =
            ((luma + (g - luma) * desat) * 255).round().clamp(0, 255);
        flat[i + 2] =
            ((luma + (b - luma) * desat) * 255).round().clamp(0, 255);
        flat[i + 3] = 255;
      }
      if (y % 128 == 127) await _breathe();
    }
    onProgress?.call(0.40);

    // Luma plane of the flat base.
    final lumaFlat = Uint8List(n);
    for (var p = 0; p < n; p++) {
      final i = p * 4;
      lumaFlat[p] = (0.2126 * flat[i] +
              0.7152 * flat[i + 1] +
              0.0722 * flat[i + 2])
          .round()
          .clamp(0, 255);
    }
    await _breathe();
    onProgress?.call(0.55);

    // Skin mask from the *original* colors (flattening skews chroma).
    final mask = Uint8List(n);
    for (var p = 0; p < n; p++) {
      final i = p * 4;
      final r = original[i], g = original[i + 1], b = original[i + 2];
      final cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b;
      final cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b;
      // Soft windows instead of hard thresholds.
      final wCr = _smoothstep(130, 140, cr) * (1 - _smoothstep(168, 180, cr));
      final wCb = _smoothstep(75, 88, cb) * (1 - _smoothstep(120, 132, cb));
      final wRg = r > g ? 1.0 : 0.0;
      mask[p] = (wCr * wCb * wRg * 255).round();
    }
    await _breathe();
    final maskRadius = math.max(2, math.min(width, height) ~/ 160);
    final skinMask = boxBlurPlane(mask, width, height, maskRadius);
    onProgress?.call(0.75);

    // Blur planes for clarity (medium radius) and detail (fine radius).
    final medRadius = math.max(3, math.min(width, height) ~/ 100);
    final blurMed = boxBlurPlane(lumaFlat, width, height, medRadius);
    await _breathe();
    final blurFine = boxBlurPlane(lumaFlat, width, height, 1);
    onProgress?.call(1.0);

    return SceneCache(
      stats: stats,
      scene: scene,
      flat: flat,
      skinMask: skinMask,
      lumaFlat: lumaFlat,
      blurMed: blurMed,
      blurFine: blurFine,
    );
  }

  // ---------------------------------------------------------------------
  // Palette stage — executes the active preset (plus user sliders) on the
  // flat base, then applies skin protection and the final polish.
  // ---------------------------------------------------------------------
  static Future<Uint8List> render(
    Uint8List original,
    SceneCache cache,
    int width,
    int height,
    GradeSettings s, {
    GradePreset preset = GradePreset.defaultPreset,
    int grainSeed = 7,
    ProgressFn? onProgress,
  }) async {
    final n = width * height;
    final p = _resolve(preset, s, cache.scene);
    final out = Uint8List(n * 4);
    final flat = cache.flat;

    // White balance folded into per-channel tone LUTs. Positive tint pulls
    // green down slightly (magenta), the classic Lightroom axis.
    final wbR = 1 + 0.055 * p.temp + 0.006 * p.tint;
    final wbG = 1 + 0.010 * p.temp - 0.028 * p.tint;
    final wbB = 1 - 0.065 * p.temp + 0.008 * p.tint;

    // Lifted matte black point, faintly warm so blacks never go blue.
    final blR = p.blackLift * 1.15;
    final blG = p.blackLift;
    final blB = p.blackLift * 0.85;

    final lutR = Float32List(256);
    final lutG = Float32List(256);
    final lutB = Float32List(256);
    for (var v = 0; v < 256; v++) {
      final x = v / 255.0;
      lutR[v] = blR + _tone(x * wbR, p) * (1 - blR);
      lutG[v] = blG + _tone(x * wbG, p) * (1 - blG);
      lutB[v] = blB + _tone(x * wbB, p) * (1 - blB);
    }

    final clarity = math.max(0.0, p.clarity);
    // Detail gain: positive sharpens gently, slightly negative gives the
    // subtle lens-softness of the editorial look. Delta is clamped → no halos.
    final detailGain = 1.2 * s.sharpness - 0.15;
    final skinWarmR = 1 + 0.09 * s.skinWarmth;
    final skinWarmG = 1 + 0.015 * s.skinWarmth;
    final skinWarmB = 1 - 0.07 * s.skinWarmth;
    final satGlobal = p.satGlobal;
    final vibrance = p.vibrance;
    final skinProtect = p.skinProtect;
    final hasHsl = p.hasHsl;
    final hueShiftLut = p.hueShiftLut;
    final satMulLut = p.satMulLut;
    final lumMulLut = p.lumMulLut;
    final hasZoneTint = p.ghR != 0 || p.ghG != 0 || p.ghB != 0 ||
        p.gmR != 0 || p.gmG != 0 || p.gmB != 0 ||
        p.gsR != 0 || p.gsG != 0 || p.gsB != 0;

    for (var y = 0; y < height; y++) {
      final rowPx = y * width;
      for (var x = 0; x < width; x++) {
        final px = rowPx + x;
        final i = px * 4;

        // Tone curve + white balance via LUT.
        var r = lutR[flat[i]];
        var g = lutG[flat[i + 1]];
        var b = lutB[flat[i + 2]];

        // Skin reference: tone-mapped but before any creative color moves.
        final skinR = r, skinG = g, skinB = b;

        var t = 0.2126 * r + 0.7152 * g + 0.0722 * b;

        // 3-way color grading: golden highlights, neutral-warm midtones,
        // faintly cool shadows.
        if (hasZoneTint) {
          final hw = _smoothstep(0.55, 1.0, t);
          final sw = 1 - _smoothstep(0.0, 0.45, t);
          final mw = (1 - hw - sw).clamp(0.0, 1.0);
          r += hw * p.ghR + mw * p.gmR + sw * p.gsR;
          g += hw * p.ghG + mw * p.gmG + sw * p.gsG;
          b += hw * p.ghB + mw * p.gmB + sw * p.gsB;
        }

        // HSL mixer + presence (vibrance / saturation), in HSV space.
        var mx = r > g ? (r > b ? r : b) : (g > b ? g : b);
        var mn = r < g ? (r < b ? r : b) : (g < b ? g : b);
        if (mx > 0.0001) {
          final delta = mx - mn;
          var sat = delta / mx;
          if (sat > 0.0001) {
            double hue;
            if (mx == r) {
              hue = 60 * (((g - b) / delta) % 6);
            } else if (mx == g) {
              hue = 60 * ((b - r) / delta + 2);
            } else {
              hue = 60 * ((r - g) / delta + 4);
            }
            if (hue < 0) hue += 360;
            var val = mx;

            if (hasHsl) {
              final hi = hue.round() % 360;
              hue += hueShiftLut[hi];
              if (hue < 0) hue += 360;
              if (hue >= 360) hue -= 360;
              sat *= satMulLut[hi];
              val = (val * lumMulLut[hi]).clamp(0.0, 1.0);
            }

            // Vibrance lifts muted colors; global saturation eases off the
            // whole image; the roll-off tames anything still heavy.
            sat *= satGlobal;
            sat += vibrance * sat * (1 - sat);
            sat *= 1 - 0.18 * sat * sat;
            sat = sat.clamp(0.0, 1.0);

            // HSV → RGB.
            final c = val * sat;
            final hp = hue / 60.0;
            final xx = c * (1 - ((hp % 2) - 1).abs());
            final m = val - c;
            if (hp < 1) {
              r = c + m; g = xx + m; b = m;
            } else if (hp < 2) {
              r = xx + m; g = c + m; b = m;
            } else if (hp < 3) {
              r = m; g = c + m; b = xx + m;
            } else if (hp < 4) {
              r = m; g = xx + m; b = c + m;
            } else if (hp < 5) {
              r = xx + m; g = m; b = c + m;
            } else {
              r = c + m; g = m; b = xx + m;
            }
          }
        }

        // Gentle clarity (midtone local contrast) + detail/softness.
        final d = (cache.lumaFlat[px] - cache.blurMed[px]) / 255.0;
        t = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        final midW = 1 - (2 * t - 1).abs();
        var add = clarity * d * midW;
        var ds = (cache.lumaFlat[px] - cache.blurFine[px]) / 255.0;
        if (ds > 0.10) ds = 0.10;
        if (ds < -0.10) ds = -0.10;
        add += ds * detailGain;
        r += add;
        g += add;
        b += add;

        // Skin protection: pull skin back toward its natural tone-mapped
        // color, with its own warmth control.
        final m = cache.skinMask[px] / 255.0 * skinProtect;
        if (m > 0.003) {
          final sr = (skinR * skinWarmR).clamp(0.0, 1.0);
          final sg = (skinG * skinWarmG).clamp(0.0, 1.0);
          final sb = (skinB * skinWarmB).clamp(0.0, 1.0);
          r += (sr - r) * m;
          g += (sg - g) * m;
          b += (sb - b) * m;
        }

        out[i] = (r * 255).round().clamp(0, 255);
        out[i + 1] = (g * 255).round().clamp(0, 255);
        out[i + 2] = (b * 255).round().clamp(0, 255);
        out[i + 3] = 255;
      }
      if (y % 96 == 95) {
        await _breathe();
        onProgress?.call(0.7 * y / height);
      }
    }
    onProgress?.call(0.7);

    // ------------------------------------------------------------------
    // Final polish: highlight bloom (low-res bright pass, blurred, screened
    // back with a cream tint), optional film grain, strength blend.
    // ------------------------------------------------------------------
    final bloomAmt = (s.bloom + p.bloomBase).clamp(0.0, 1.2) * 0.5;
    Uint8List? bloomPlane;
    var lw = 0, lh = 0, factor = 1;
    if (bloomAmt > 0.005) {
      factor = math.max(1, (math.max(width, height) / 640).ceil());
      lw = (width + factor - 1) ~/ factor;
      lh = (height + factor - 1) ~/ factor;
      final bright = Uint8List(lw * lh);
      for (var ly = 0; ly < lh; ly++) {
        final sy = math.min(height - 1, ly * factor + factor ~/ 2);
        for (var lx = 0; lx < lw; lx++) {
          final sx = math.min(width - 1, lx * factor + factor ~/ 2);
          final i = (sy * width + sx) * 4;
          final t =
              (0.2126 * out[i] + 0.7152 * out[i + 1] + 0.0722 * out[i + 2]) /
                  255.0;
          bright[ly * lw + lx] =
              ((t - 0.72).clamp(0.0, 0.28) / 0.28 * 255).round();
        }
      }
      bloomPlane =
          boxBlurPlane(bright, lw, lh, math.max(2, math.min(lw, lh) ~/ 36));
      await _breathe();
    }
    onProgress?.call(0.78);

    final grainAmt = s.grainEnabled ? s.grain * 0.09 : 0.0;
    final rng = math.Random(grainSeed);
    final strength = s.strength;
    final invFactor = 1.0 / factor;

    for (var y = 0; y < height; y++) {
      final rowPx = y * width;
      final fy = bloomPlane != null ? y * invFactor : 0.0;
      final ly0 = bloomPlane != null ? math.min(lh - 1, fy.floor()) : 0;
      final ly1 = bloomPlane != null ? math.min(lh - 1, ly0 + 1) : 0;
      final wy = fy - fy.floorToDouble();
      for (var x = 0; x < width; x++) {
        final i = (rowPx + x) * 4;
        var r = out[i] / 255.0;
        var g = out[i + 1] / 255.0;
        var b = out[i + 2] / 255.0;

        if (bloomPlane != null) {
          final fx = x * invFactor;
          final lx0 = math.min(lw - 1, fx.floor());
          final lx1 = math.min(lw - 1, lx0 + 1);
          final wx = fx - fx.floorToDouble();
          final top = bloomPlane[ly0 * lw + lx0] * (1 - wx) +
              bloomPlane[ly0 * lw + lx1] * wx;
          final bot = bloomPlane[ly1 * lw + lx0] * (1 - wx) +
              bloomPlane[ly1 * lw + lx1] * wx;
          final bl = (top * (1 - wy) + bot * wy) / 255.0 * bloomAmt;
          // Screen blend with a cream tint — soft glow, no halos.
          r = 1 - (1 - r) * (1 - bl * 0.55);
          g = 1 - (1 - g) * (1 - bl * 0.50);
          b = 1 - (1 - b) * (1 - bl * 0.42);
        }

        if (grainAmt > 0) {
          final t = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          final noise = (rng.nextDouble() * 2 - 1) *
              grainAmt *
              (1 - (2 * t - 1).abs() * 0.6);
          r += noise;
          g += noise;
          b += noise;
        }

        if (strength < 0.999) {
          final or = original[i] / 255.0;
          final og = original[i + 1] / 255.0;
          final ob = original[i + 2] / 255.0;
          r = or + (r - or) * strength;
          g = og + (g - og) * strength;
          b = ob + (b - ob) * strength;
        }

        out[i] = (r * 255).round().clamp(0, 255);
        out[i + 1] = (g * 255).round().clamp(0, 255);
        out[i + 2] = (b * 255).round().clamp(0, 255);
      }
      if (y % 96 == 95) {
        await _breathe();
        onProgress?.call(0.78 + 0.22 * y / height);
      }
    }
    onProgress?.call(1.0);
    return out;
  }
}
