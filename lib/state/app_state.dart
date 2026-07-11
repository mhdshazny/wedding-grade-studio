import 'dart:async';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../models/settings.dart';
import '../processing/pipeline.dart';
import '../processing/scene.dart';
import '../services/browser_io.dart';

enum PhotoStatus { queued, decoding, analyzing, grading, ready, error }

const int _previewMaxEdge = 1400;
const int _thumbMaxEdge = 240;
// Full preview working sets are heavy; keep only a few photos "hot".
const int _maxPrepared = 3;

Future<ui.Image> _rgbaToImage(Uint8List rgba, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      rgba, width, height, ui.PixelFormat.rgba8888, completer.complete);
  return completer.future;
}

/// Disposes an image after the current frame so widgets still holding it
/// never paint a disposed image.
void _disposeImageLater(ui.Image? image) {
  if (image == null) return;
  Timer(const Duration(milliseconds: 300), image.dispose);
}

class PhotoItem {
  final String id;
  final String name;
  final Uint8List bytes;

  ui.Image? thumb;
  PhotoStatus status = PhotoStatus.queued;
  double progress = 0;
  String? error;

  // Preview-resolution working set; present only while the photo is "hot".
  Uint8List? previewRgba;
  int previewW = 0, previewH = 0;
  SceneCache? cache;
  ui.Image? beforeImage;
  ui.Image? afterImage;
  int renderedRevision = -1;

  PhotoItem(this.id, this.name, this.bytes);

  SceneType? get scene => cache?.scene;

  void disposeWorkingSet() {
    _disposeImageLater(beforeImage);
    _disposeImageLater(afterImage);
    beforeImage = null;
    afterImage = null;
    previewRgba = null;
    cache = null;
    renderedRevision = -1;
  }
}

class AppState extends ChangeNotifier {
  final photos = <PhotoItem>[];
  PhotoItem? selected;
  GradeSettings settings = GradeSettings.defaults;
  int _settingsRevision = 0;

  bool dragging = false;
  bool exporting = false;
  double exportProgress = 0;
  String exportLabel = '';

  String? notice; // transient user-facing message (bad file, decode error…)

  Timer? _debounce;
  int _nextId = 0;
  bool _intakeRunning = false;
  final _intakeQueue = <PhotoItem>[];
  final _preparedOrder = <PhotoItem>[];

  AppState() {
    setupDropHandlers(
      onDragState: (d) {
        if (dragging != d) {
          dragging = d;
          notifyListeners();
        }
      },
      onFiles: addFiles,
    );
  }

  // ------------------------------------------------------------------
  // Intake
  // ------------------------------------------------------------------
  Future<void> pickAndAdd() async {
    final files = await pickImages();
    await addFiles(files);
  }

  Future<void> addFiles(List<PickedFile> files) async {
    final rejected = <String>[];
    for (final f in files) {
      if (!isAcceptedName(f.name)) {
        rejected.add(f.name);
        continue;
      }
      if (f.bytes.length > maxFileBytes) {
        rejected.add('${f.name} (over 50 MB)');
        continue;
      }
      final item = PhotoItem('p${_nextId++}', f.name, f.bytes);
      photos.add(item);
      _intakeQueue.add(item);
    }
    if (rejected.isNotEmpty) {
      notice = 'Skipped: ${rejected.join(', ')} — '
          'use JPG, PNG or HEIC up to 50 MB.';
    }
    notifyListeners();
    if (!_intakeRunning) {
      _intakeRunning = true;
      try {
        while (_intakeQueue.isNotEmpty) {
          final item = _intakeQueue.removeAt(0);
          await _intake(item);
        }
      } finally {
        _intakeRunning = false;
      }
    }
  }

  Future<void> _intake(PhotoItem item) async {
    if (!photos.contains(item)) return;
    item.status = PhotoStatus.decoding;
    notifyListeners();
    try {
      final thumbRaw = await decodeImage(item.bytes, maxEdge: _thumbMaxEdge);
      item.thumb =
          await _rgbaToImage(thumbRaw.rgba, thumbRaw.width, thumbRaw.height);
      item.status = PhotoStatus.queued;
      notifyListeners();
      // Auto-select and fully process the first photo.
      if (selected == null) {
        await selectPhoto(item);
      } else if (photos.contains(item)) {
        await _preparePhoto(item);
      }
    } catch (e) {
      item.status = PhotoStatus.error;
      item.error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }

  // ------------------------------------------------------------------
  // Selection & preview rendering
  // ------------------------------------------------------------------
  Future<void> selectPhoto(PhotoItem item) async {
    selected = item;
    notifyListeners();
    await _preparePhoto(item);
  }

  Future<void> _preparePhoto(PhotoItem item) async {
    if (item.status == PhotoStatus.error) return;
    if (item.cache == null) {
      try {
        item.status = PhotoStatus.decoding;
        item.progress = 0;
        notifyListeners();
        final raw = await decodeImage(item.bytes, maxEdge: _previewMaxEdge);
        if (!photos.contains(item)) return;
        item.previewRgba = raw.rgba;
        item.previewW = raw.width;
        item.previewH = raw.height;
        item.beforeImage =
            await _rgbaToImage(raw.rgba, raw.width, raw.height);

        item.status = PhotoStatus.analyzing;
        notifyListeners();
        item.cache = await Pipeline.buildCache(
          raw.rgba,
          raw.width,
          raw.height,
          onProgress: (p) {
            item.progress = p * 0.5;
            notifyListeners();
          },
        );
        _markPrepared(item);
      } catch (e) {
        item.status = PhotoStatus.error;
        item.error = e.toString().replaceFirst('Exception: ', '');
        notifyListeners();
        return;
      }
    }
    await _renderPreview(item);
  }

  Future<void> _renderPreview(PhotoItem item) async {
    final cache = item.cache;
    final rgba = item.previewRgba;
    if (cache == null || rgba == null) return;
    final revision = _settingsRevision;
    if (item.renderedRevision == revision &&
        item.status == PhotoStatus.ready) {
      return;
    }
    item.status = PhotoStatus.grading;
    notifyListeners();
    try {
      final out = await Pipeline.render(
        rgba,
        cache,
        item.previewW,
        item.previewH,
        settings,
        onProgress: (p) {
          item.progress = 0.5 + p * 0.5;
          notifyListeners();
        },
      );
      if (!photos.contains(item)) return;
      final image = await _rgbaToImage(out, item.previewW, item.previewH);
      _disposeImageLater(item.afterImage);
      item.afterImage = image;
      item.renderedRevision = revision;
      item.status = PhotoStatus.ready;
      item.progress = 1;
      notifyListeners();
      // Settings changed while rendering — render once more.
      if (revision != _settingsRevision && item == selected) {
        await _renderPreview(item);
      }
    } catch (e) {
      item.status = PhotoStatus.error;
      item.error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }

  void _markPrepared(PhotoItem item) {
    _preparedOrder.remove(item);
    _preparedOrder.add(item);
    while (_preparedOrder.length > _maxPrepared) {
      final victim = _preparedOrder.firstWhere(
        (p) => p != selected,
        orElse: () => _preparedOrder.first,
      );
      if (victim == selected) break;
      _preparedOrder.remove(victim);
      victim.disposeWorkingSet();
      if (victim.status == PhotoStatus.ready) {
        victim.status = PhotoStatus.queued;
      }
    }
  }

  // ------------------------------------------------------------------
  // Settings
  // ------------------------------------------------------------------
  void updateSettings(GradeSettings next) {
    settings = next;
    _settingsRevision++;
    notifyListeners();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 140), () {
      final item = selected;
      if (item != null && item.status != PhotoStatus.grading) {
        _renderPreview(item);
      }
    });
  }

  void resetSettings() => updateSettings(GradeSettings.defaults);

  void clearNotice() {
    notice = null;
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Removal
  // ------------------------------------------------------------------
  void removePhoto(PhotoItem item) {
    photos.remove(item);
    _intakeQueue.remove(item);
    _preparedOrder.remove(item);
    item.disposeWorkingSet();
    _disposeImageLater(item.thumb);
    item.thumb = null;
    if (selected == item) {
      selected = photos.isEmpty ? null : photos.first;
      if (selected != null) {
        selectPhoto(selected!);
        return;
      }
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Export (always full resolution)
  // ------------------------------------------------------------------
  String _exportName(String name, String ext) {
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    return '${base}_graded.$ext';
  }

  Future<Uint8List> _processFullRes(
    PhotoItem item,
    String mime,
    void Function(double) onProgress,
  ) async {
    final raw = await decodeImage(item.bytes);
    onProgress(0.15);
    final cache = await Pipeline.buildCache(
      raw.rgba,
      raw.width,
      raw.height,
      onProgress: (p) => onProgress(0.15 + p * 0.35),
    );
    final out = await Pipeline.render(
      raw.rgba,
      cache,
      raw.width,
      raw.height,
      settings,
      onProgress: (p) => onProgress(0.5 + p * 0.4),
    );
    final encoded = await encodeImage(
      out,
      raw.width,
      raw.height,
      mime: mime,
      quality: 0.95,
    );
    onProgress(1.0);
    return encoded;
  }

  Future<void> exportSelected({required bool png}) async {
    final item = selected;
    if (item == null || exporting) return;
    exporting = true;
    exportProgress = 0;
    exportLabel = 'Processing ${item.name} at full resolution…';
    notifyListeners();
    try {
      final mime = png ? 'image/png' : 'image/jpeg';
      final bytes = await _processFullRes(item, mime, (p) {
        exportProgress = p;
        notifyListeners();
      });
      downloadBytes(bytes, _exportName(item.name, png ? 'png' : 'jpg'), mime);
    } catch (e) {
      notice = 'Export failed: ${e.toString().replaceFirst('Exception: ', '')}';
    } finally {
      exporting = false;
      notifyListeners();
    }
  }

  Future<void> exportAllZip() async {
    if (photos.isEmpty || exporting) return;
    exporting = true;
    exportProgress = 0;
    notifyListeners();
    final archive = Archive();
    var done = 0;
    final eligible =
        photos.where((p) => p.status != PhotoStatus.error).toList();
    try {
      for (final item in eligible) {
        exportLabel =
            'Processing ${done + 1} of ${eligible.length} — ${item.name}';
        notifyListeners();
        try {
          final bytes = await _processFullRes(item, 'image/jpeg', (p) {
            exportProgress = (done + p) / eligible.length;
            notifyListeners();
          });
          archive.addFile(
              ArchiveFile.bytes(_exportName(item.name, 'jpg'), bytes));
        } catch (_) {
          // Skip photos that fail (e.g. HEIC on non-Safari); keep going.
        }
        done++;
      }
      if (archive.isNotEmpty) {
        exportLabel = 'Building ZIP…';
        notifyListeners();
        final zip = ZipEncoder().encodeBytes(archive);
        downloadBytes(zip, 'wedding_graded_photos.zip', 'application/zip');
      } else {
        notice = 'Nothing could be exported.';
      }
    } finally {
      exporting = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
