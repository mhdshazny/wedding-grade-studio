import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wedding_grader/models/settings.dart';
import 'package:wedding_grader/processing/pipeline.dart';
import 'package:wedding_grader/processing/scene.dart';

/// Builds a synthetic RGBA test frame: sky on top, greens on the sides,
/// a warm midtone subject in the middle.
Uint8List _syntheticFrame(int w, int h) {
  final rgba = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      int r, g, b;
      if (y < h ~/ 3) {
        r = 110; g = 150; b = 220; // sky
      } else if (x < w ~/ 4 || x > 3 * w ~/ 4) {
        r = 60; g = 130; b = 55; // vegetation
      } else if (x < w ~/ 2) {
        r = 238; g = 234; b = 228; // white dress
      } else if (x > 5 * w ~/ 8) {
        r = 28; g = 26; b = 30; // dark suit
      } else {
        r = 210; g = 160; b = 130; // skin-ish subject
      }
      rgba[i] = r;
      rgba[i + 1] = g;
      rgba[i + 2] = b;
      rgba[i + 3] = 255;
    }
  }
  return rgba;
}

void main() {
  group('ImageStats', () {
    test('detects greens, sky and skin in a synthetic frame', () {
      const w = 120, h = 90;
      final stats = ImageStats.analyze(_syntheticFrame(w, h), w, h);
      expect(stats.greenFrac, greaterThan(0.1));
      expect(stats.skyFrac, greaterThan(0.05));
      expect(stats.skinFrac, greaterThan(0.05));
      expect(stats.meanLuma, inInclusiveRange(0.2, 0.9));
    });

    test('classifies dark cool frames as night', () {
      const w = 64, h = 64;
      final rgba = Uint8List(w * h * 4);
      final rng = math.Random(1);
      for (var p = 0; p < w * h; p++) {
        rgba[p * 4] = rng.nextInt(18);
        rgba[p * 4 + 1] = rng.nextInt(20);
        rgba[p * 4 + 2] = rng.nextInt(30);
        rgba[p * 4 + 3] = 255;
      }
      final stats = ImageStats.analyze(rgba, w, h);
      expect(detectScene(stats), SceneType.night);
    });
  });

  group('Pipeline', () {
    test('flatten reduces contrast and saturation, render restores a grade',
        () async {
      const w = 120, h = 90;
      final original = _syntheticFrame(w, h);
      final cache = await Pipeline.buildCache(original, w, h);

      final statsIn = ImageStats.analyze(original, w, h);
      final statsFlat = ImageStats.analyze(cache.flat, w, h);
      // Flat base: less saturation, less global contrast.
      expect(statsFlat.meanSat, lessThan(statsIn.meanSat));
      expect(statsFlat.stdLuma, lessThanOrEqualTo(statsIn.stdLuma + 0.01));
      // Nothing crushed or clipped in the flat base.
      expect(statsFlat.clipFrac, 0);
      expect(statsFlat.darkFrac, 0);

      final out = await Pipeline.render(
          original, cache, w, h, GradeSettings.defaults);
      expect(out.length, original.length);

      // Graded output keeps alpha opaque and stays in range.
      for (var p = 0; p < w * h; p++) {
        expect(out[p * 4 + 3], 255);
      }

      // Greens end up muted vs the original (olive, desaturated look).
      final statsOut = ImageStats.analyze(out, w, h);
      expect(statsOut.meanSat, lessThan(statsIn.meanSat));
    });

    test('strength 0 returns the original image', () async {
      const w = 60, h = 40;
      final original = _syntheticFrame(w, h);
      final cache = await Pipeline.buildCache(original, w, h);
      final out = await Pipeline.render(original, cache, w, h,
          const GradeSettings(strength: 0, bloom: 0, sharpness: 0));
      var maxDelta = 0;
      for (var i = 0; i < out.length; i++) {
        final d = (out[i] - original[i]).abs();
        if (d > maxDelta) maxDelta = d;
      }
      // Bloom is additive before the strength blend, so allow ±1 rounding.
      expect(maxDelta, lessThanOrEqualTo(1));
    });

    test('tone response is monotonic for a neutral ramp', () async {
      // A gray ramp: graded values must never invert order (no banding
      // artifacts, no curve folds).
      const w = 256, h = 4;
      final rgba = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = (y * w + x) * 4;
          rgba[i] = x;
          rgba[i + 1] = x;
          rgba[i + 2] = x;
          rgba[i + 3] = 255;
        }
      }
      final cache = await Pipeline.buildCache(rgba, w, h);
      final out = await Pipeline.render(
        rgba,
        cache,
        w,
        h,
        // Isolate the tone curve from spatial effects.
        const GradeSettings(strength: 1, bloom: 0, sharpness: 0.125),
      );
      for (var x = 1; x < w; x++) {
        final prev = out[(w + x - 1) * 4 + 1]; // row 1, green channel
        final cur = out[(w + x) * 4 + 1];
        expect(cur, greaterThanOrEqualTo(prev - 1),
            reason: 'tone inversion at x=$x');
      }
    });
  });
}
