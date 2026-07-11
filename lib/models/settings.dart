/// User-adjustable grading controls.
///
/// All values are normalized: bipolar controls run -1..1 with 0 as the
/// designed default, unipolar controls run 0..1.
class GradeSettings {
  final double strength; // 0..1 blend between original and graded result
  final double warmth; // -1..1 white balance bias on top of the base grade
  final double contrast; // -1..1
  final double highlights; // -1..1
  final double shadows; // -1..1
  final double skinWarmth; // -1..1
  final double greens; // 0..1 amount of olive shift + desaturation
  final double blues; // 0..1 amount of teal shift + desaturation
  final double grain; // 0..1 film grain amount
  final bool grainEnabled;
  final double bloom; // 0..1 highlight bloom amount
  final double sharpness; // 0..1 gentle output sharpening

  const GradeSettings({
    this.strength = 0.85,
    this.warmth = 0.0,
    this.contrast = 0.0,
    this.highlights = 0.0,
    this.shadows = 0.0,
    this.skinWarmth = 0.0,
    this.greens = 0.5,
    this.blues = 0.5,
    this.grain = 0.3,
    this.grainEnabled = false,
    this.bloom = 0.35,
    this.sharpness = 0.3,
  });

  static const defaults = GradeSettings();

  GradeSettings copyWith({
    double? strength,
    double? warmth,
    double? contrast,
    double? highlights,
    double? shadows,
    double? skinWarmth,
    double? greens,
    double? blues,
    double? grain,
    bool? grainEnabled,
    double? bloom,
    double? sharpness,
  }) {
    return GradeSettings(
      strength: strength ?? this.strength,
      warmth: warmth ?? this.warmth,
      contrast: contrast ?? this.contrast,
      highlights: highlights ?? this.highlights,
      shadows: shadows ?? this.shadows,
      skinWarmth: skinWarmth ?? this.skinWarmth,
      greens: greens ?? this.greens,
      blues: blues ?? this.blues,
      grain: grain ?? this.grain,
      grainEnabled: grainEnabled ?? this.grainEnabled,
      bloom: bloom ?? this.bloom,
      sharpness: sharpness ?? this.sharpness,
    );
  }
}
