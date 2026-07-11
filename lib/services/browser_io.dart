import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// A file picked or dropped by the user.
class PickedFile {
  final String name;
  final Uint8List bytes;
  const PickedFile(this.name, this.bytes);
}

/// Raw RGBA pixels decoded from an image file.
class DecodedRaw {
  final Uint8List rgba;
  final int width;
  final int height;
  const DecodedRaw(this.rgba, this.width, this.height);
}

const acceptedExtensions = ['.jpg', '.jpeg', '.png', '.heic', '.heif'];
const maxFileBytes = 50 * 1024 * 1024;

bool isAcceptedName(String name) {
  final lower = name.toLowerCase();
  return acceptedExtensions.any(lower.endsWith);
}

/// Opens the browser file picker and returns the selected images.
Future<List<PickedFile>> pickImages() {
  final completer = Completer<List<PickedFile>>();
  final input =
      web.document.createElement('input') as web.HTMLInputElement
        ..type = 'file'
        ..multiple = true
        ..accept = '.jpg,.jpeg,.png,.heic,.heif,image/jpeg,image/png,image/heic';
  input.style.display = 'none';
  web.document.body!.appendChild(input);

  void finish(List<PickedFile> files) {
    input.remove();
    if (!completer.isCompleted) completer.complete(files);
  }

  input.addEventListener(
    'change',
    ((web.Event e) {
      _readFileList(input.files).then(finish);
    }).toJS,
  );
  input.addEventListener('cancel', ((web.Event e) => finish(const [])).toJS);
  input.click();
  return completer.future;
}

Future<List<PickedFile>> _readFileList(web.FileList? list) async {
  final result = <PickedFile>[];
  if (list == null) return result;
  for (var i = 0; i < list.length; i++) {
    final file = list.item(i);
    if (file == null) continue;
    final buffer = await file.arrayBuffer().toDart;
    result.add(PickedFile(file.name, buffer.toDart.asUint8List()));
  }
  return result;
}

/// Wires window-level drag & drop. [onDragState] toggles the drop overlay,
/// [onFiles] receives the dropped images.
void setupDropHandlers({
  required void Function(bool dragging) onDragState,
  required void Function(List<PickedFile> files) onFiles,
}) {
  web.window.addEventListener(
    'dragover',
    ((web.DragEvent e) {
      e.preventDefault();
      onDragState(true);
    }).toJS,
  );
  web.window.addEventListener(
    'dragleave',
    ((web.DragEvent e) {
      e.preventDefault();
      onDragState(false);
    }).toJS,
  );
  web.window.addEventListener(
    'drop',
    ((web.DragEvent e) {
      e.preventDefault();
      onDragState(false);
      final transfer = e.dataTransfer;
      if (transfer == null) return;
      _readFileList(transfer.files).then(onFiles);
    }).toJS,
  );
}

/// Decodes an image with the browser's native decoder (fast, hardware backed,
/// EXIF-orientation aware). Optionally downscales so the longest edge is at
/// most [maxEdge]. HEIC decodes wherever the browser supports it (Safari).
Future<DecodedRaw> decodeImage(Uint8List bytes, {int? maxEdge}) async {
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/octet-stream'),
  );
  final web.ImageBitmap bitmap;
  try {
    bitmap = await web.window
        .createImageBitmap(
          blob,
          web.ImageBitmapOptions(imageOrientation: 'from-image'),
        )
        .toDart;
  } catch (_) {
    throw Exception(
      'This browser could not decode the image. HEIC files are only '
      'supported in Safari — convert to JPEG or PNG for other browsers.',
    );
  }

  var w = bitmap.width;
  var h = bitmap.height;
  if (maxEdge != null && (w > maxEdge || h > maxEdge)) {
    final scale = maxEdge / (w > h ? w : h);
    w = (w * scale).round().clamp(1, w);
    h = (h * scale).round().clamp(1, h);
  }

  final canvas = web.OffscreenCanvas(w, h);
  final ctx = canvas.getContext('2d') as web.OffscreenCanvasRenderingContext2D;
  ctx.drawImage(bitmap, 0, 0, w, h);
  bitmap.close();
  final data = ctx.getImageData(0, 0, w, h);
  final clamped = data.data.toDart;
  final rgba = Uint8List.view(
    clamped.buffer,
    clamped.offsetInBytes,
    clamped.lengthInBytes,
  );
  return DecodedRaw(Uint8List.fromList(rgba), w, h);
}

/// Encodes RGBA pixels with the browser's native encoder.
/// [mime] is 'image/jpeg' or 'image/png'.
Future<Uint8List> encodeImage(
  Uint8List rgba,
  int width,
  int height, {
  required String mime,
  double quality = 0.95,
}) async {
  final clamped = rgba.buffer
      .asUint8ClampedList(rgba.offsetInBytes, rgba.lengthInBytes);
  final imageData = web.ImageData(clamped.toJS as JSAny, width, height.toJS);
  final canvas = web.OffscreenCanvas(width, height);
  final ctx = canvas.getContext('2d') as web.OffscreenCanvasRenderingContext2D;
  ctx.putImageData(imageData, 0, 0);
  final blob = await canvas
      .convertToBlob(web.ImageEncodeOptions(type: mime, quality: quality))
      .toDart;
  final buffer = await blob.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}

/// Triggers a browser download of [bytes] as [filename].
void downloadBytes(Uint8List bytes, String filename, String mime) {
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mime),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  Timer(const Duration(seconds: 10), () => web.URL.revokeObjectURL(url));
}
