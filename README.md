# Wedding Grade Studio

A wedding photo color grading web app with a **classic & timeless** cinematic
look — warm ivory whites, champagne highlights, coffee-brown shadows, olive
greens, muted teal-leaning blues and protected natural skin tones. Inspired by
fine-art wedding editorial work (Jose Villa, KT Merry).

Everything runs **entirely in the browser** — photos never leave the device.

Built with **Flutter Web · Dart · Material 3**.

## Features

- **Import** — JPG / JPEG / PNG / HEIC*, up to 50 MB, via drag & drop or file
  picker, multiple photos at once. (*HEIC decodes where the browser supports
  it — Safari.)
- **Processing pipeline** (per photo):
  1. *Flatten* — levels-normalized, desaturated, low-contrast LOG-like base so
     every camera starts from the same neutral profile.
  2. *Smart scene detection* — indoor, outdoor, golden hour, shade, direct
     sunlight, reception, night, flash — each biases the grade slightly.
  3. *Wedding grade* — warm white balance, film-like tone curve with lifted
     warm blacks and a creamy shoulder (no clipping), coffee/cream split
     toning, olive-shifted muted greens, teal-leaning muted blues, global
     saturation roll-off, gentle clarity.
  4. *Skin protection* — soft YCbCr skin mask; skin keeps its natural
     tone-mapped color with its own warmth control. No orange, no magenta.
  5. *Final polish* — cream-tinted highlight bloom, subtle lens softness,
     optional fine film grain.
- **UI** — dark Material 3 theme, before/after slider, pinch/scroll zoom and
  pan (double-tap resets), thumbnail strip with per-photo status, live
  preview with progress, responsive desktop and mobile layouts.
- **Controls** — Strength, Warmth, Contrast, Highlights, Shadows, Skin Warmth,
  Greens, Blues, Bloom, Sharpness, Film Grain (toggle + amount), Reset.
- **Export** — JPEG or PNG at 95% quality and original resolution; batch
  export of all photos as a ZIP.

## Architecture

```
lib/
  main.dart                  app entry + Material 3 dark theme
  models/settings.dart       GradeSettings (slider state)
  processing/
    scene.dart               image statistics + scene classification
    pipeline.dart            flatten → grade → polish (pure Dart, LUT-driven)
    blur.dart                O(n) box blur used for masks/clarity/bloom
  services/browser_io.dart   decode/encode via native canvas, picker,
                             drag & drop, downloads (package:web interop)
  state/app_state.dart       photo list, preview rendering, exports
  ui/                        home screen, before/after viewer, controls,
                             thumbnail strip
```

Performance notes:

- Decoding and encoding use the browser's **native** codecs
  (`createImageBitmap` / `OffscreenCanvas.convertToBlob`) — fast and
  EXIF-orientation aware.
- Grading is pure Dart compiled to JavaScript, driven by per-channel lookup
  tables with cooperative yielding so the UI never freezes.
- Live preview is graded at reduced resolution; the image-dependent work
  (flatten, scene, skin mask, blur planes) is cached per photo, so moving a
  slider only re-runs the color pass. Exports re-run the full pipeline at
  original resolution.
- CanvasKit and fonts are bundled — no CDN dependency at runtime.

## Development

Requires Flutter 3.44+.

```bash
flutter pub get
flutter test          # pipeline unit tests
flutter run -d chrome # dev
flutter build web --release
```

Serve the built app from `build/web` with any static file server, e.g.:

```bash
python3 -m http.server 8080 -d build/web
```
