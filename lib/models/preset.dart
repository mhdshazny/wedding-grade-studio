/// Modular color-grading presets, modeled after Lightroom / Camera Raw
/// develop settings. A preset fully describes the "Apply palette" stage;
/// the processing pipeline just executes whatever preset is active, so new
/// looks can be added here without touching the pipeline.
library;

/// One HSL color band (like Lightroom's HSL mixer rows).
class HslBand {
  final double hueShift; // degrees, +/- rotates the band's hue
  final double sat; // saturation multiplier (1 = unchanged)
  final double lum; // luminance multiplier (1 = unchanged)

  const HslBand({this.hueShift = 0, this.sat = 1, this.lum = 1});

  static const neutral = HslBand();

  bool get isNeutral => hueShift == 0 && sat == 1 && lum == 1;
}

/// A small RGB offset applied to a tonal zone (3-way color grading).
class ZoneTint {
  final double r, g, b;
  const ZoneTint(this.r, this.g, this.b);
  static const none = ZoneTint(0, 0, 0);
}

class GradePreset {
  final String id;
  final String name;
  final String description;

  /// Whether scene detection may bias the parameters (kept off for "None").
  final bool sceneAdaptive;

  // Global adjustments (Lightroom "Basic" panel).
  final double exposure; // EV
  final double contrast; // S-curve amount, 0 = none
  final double highlights; // -1..1
  final double shadows; // -1..1
  final double whites; // -1..1 (negative pulls whites down)
  final double blackLift; // 0..~0.05 lifted matte black point

  // White balance bias.
  final double temp; // warm(+) / cool(-)
  final double tint; // magenta(+) / green(-)

  // Presence.
  final double saturation; // global multiplier
  final double vibrance; // boosts muted colors, spares saturated ones
  final double clarity; // midtone local contrast

  // HSL mixer.
  final HslBand reds, oranges, yellows, greens, aquas, blues, magentas;

  // 3-way color grading.
  final ZoneTint highlightTint, midtoneTint, shadowTint;

  // Protections / finish.
  final double skinProtect; // 0..1 strength of the skin mask blend
  final double bloomBase; // added to the user's bloom slider

  const GradePreset({
    required this.id,
    required this.name,
    required this.description,
    this.sceneAdaptive = true,
    this.exposure = 0,
    this.contrast = 0,
    this.highlights = 0,
    this.shadows = 0,
    this.whites = 0,
    this.blackLift = 0,
    this.temp = 0,
    this.tint = 0,
    this.saturation = 1,
    this.vibrance = 0,
    this.clarity = 0,
    this.reds = HslBand.neutral,
    this.oranges = HslBand.neutral,
    this.yellows = HslBand.neutral,
    this.greens = HslBand.neutral,
    this.aquas = HslBand.neutral,
    this.blues = HslBand.neutral,
    this.magentas = HslBand.neutral,
    this.highlightTint = ZoneTint.none,
    this.midtoneTint = ZoneTint.none,
    this.shadowTint = ZoneTint.none,
    this.skinProtect = 0,
    this.bloomBase = 0,
  });

  /// Pass-through: the flat profile plus whatever the user sets manually.
  static const none = GradePreset(
    id: 'none',
    name: 'None',
    description: 'No palette — flat profile with manual adjustments only.',
    sceneAdaptive: false,
  );

  /// The house look: classic, timeless, soft, warm, filmic, premium.
  static const classicTimelessWedding = GradePreset(
    id: 'classic_timeless_wedding',
    name: 'Classic & Timeless Wedding',
    description:
        'Soft film-inspired grade — creamy highlights, olive greens, deep '
        'quiet blues and natural warm skin.',
    sceneAdaptive: true,

    // Global: gentle lift after flattening, protected whites, matte blacks.
    exposure: 0.10,
    contrast: 0.50, // soft S-curve, moderate after the flat base
    highlights: -0.15, // preserve white dresses
    shadows: 0.15, // gently lifted
    whites: -0.10,
    blackLift: 0.022, // subtle matte, texture kept in black clothing

    // Warm and inviting, never yellow; a whisper of magenta.
    temp: 0.35,
    tint: 0.06,

    // Slightly reduced saturation, richer muted colors via vibrance.
    saturation: 0.93,
    vibrance: 0.16,
    clarity: 0.20,

    // HSL mixer — the heart of the palette.
    reds: HslBand(hueShift: 3, sat: 1.0, lum: 1.04),
    oranges: HslBand(hueShift: 0, sat: 0.94, lum: 1.05), // skin priority
    yellows: HslBand(hueShift: -10, sat: 0.85, lum: 1.06), // creamy sunlight
    greens: HslBand(hueShift: -22, sat: 0.68, lum: 1.04), // olive, never neon
    aquas: HslBand(sat: 0.86),
    blues: HslBand(hueShift: -4, sat: 0.85, lum: 0.95), // deep elegant skies
    magentas: HslBand(sat: 0.88),

    // 3-way grading: golden highlights, neutral-warm mids, faintly cool
    // shadows (balance, not blue).
    highlightTint: ZoneTint(0.020, 0.011, -0.012),
    midtoneTint: ZoneTint(0.007, 0.002, -0.003),
    shadowTint: ZoneTint(-0.002, 0.001, 0.006),

    skinProtect: 0.80,
    bloomBase: 0.0,
  );

  /// Registry shown in the UI, in display order.
  static const all = [none, classicTimelessWedding];

  static const defaultPreset = classicTimelessWedding;
}
