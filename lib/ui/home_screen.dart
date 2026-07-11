import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'before_after.dart';
import 'controls_panel.dart';
import 'photo_strip.dart';

class HomeScreen extends StatelessWidget {
  final AppState state;
  const HomeScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.favorite,
                    size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Text('Wedding Grade Studio'),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Add photos',
                onPressed: state.pickAndAdd,
                icon: const Icon(Icons.add_photo_alternate_outlined),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                children: [
                  if (state.notice != null)
                    MaterialBanner(
                      content: Text(state.notice!),
                      leading: const Icon(Icons.info_outline),
                      actions: [
                        TextButton(
                          onPressed: state.clearNotice,
                          child: const Text('Dismiss'),
                        ),
                      ],
                    ),
                  Expanded(
                    child: state.photos.isEmpty
                        ? _EmptyDropZone(onPick: state.pickAndAdd)
                        : _Workspace(state: state),
                  ),
                ],
              ),
              if (state.dragging) const _DropOverlay(),
              if (state.exporting) _ExportOverlay(state: state),
            ],
          ),
        );
      },
    );
  }
}

class _Workspace extends StatelessWidget {
  final AppState state;
  const _Workspace({required this.state});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 920;
        final preview = _PreviewArea(state: state);
        final strip = PhotoStrip(state: state);
        final controls = ControlsPanel(state: state);

        if (wide) {
          return Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: preview,
                      ),
                    ),
                    strip,
                  ],
                ),
              ),
              Container(
                width: 340,
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                ),
                child: controls,
              ),
            ],
          );
        }

        return Column(
          children: [
            SizedBox(
              height: constraints.maxHeight * 0.44,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: preview,
              ),
            ),
            strip,
            const Divider(height: 1),
            Expanded(child: controls),
          ],
        );
      },
    );
  }
}

class _PreviewArea extends StatelessWidget {
  final AppState state;
  const _PreviewArea({required this.state});

  ui.Image? _stageImage(PhotoItem item) => switch (state.stage) {
        ViewStage.original => item.beforeImage,
        ViewStage.flattened => item.flatImage,
        ViewStage.graded => item.afterImage,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = state.selected;

    Widget child;
    if (item == null) {
      child = Center(
        child: Text('Select a photo below',
            style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    } else if (item.status == PhotoStatus.error) {
      child = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, color: scheme.error, size: 40),
              const SizedBox(height: 12),
              Text(item.error ?? 'This photo could not be processed.',
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    } else if (item.beforeImage != null && _stageImage(item) != null) {
      child = BeforeAfterViewer(
        key: ValueKey(item.id),
        before: item.beforeImage!,
        after: _stageImage(item)!,
        afterLabel: switch (state.stage) {
          ViewStage.original => 'Original',
          ViewStage.flattened => 'Flat Profile',
          ViewStage.graded => 'After',
        },
      );
    } else {
      final label = switch (item.status) {
        PhotoStatus.decoding => 'Decoding image…',
        PhotoStatus.analyzing => 'Flattening profile & detecting scene…',
        PhotoStatus.grading => 'Applying wedding grade…',
        _ => 'Preparing…',
      };
      child = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 160,
              child: LinearProgressIndicator(
                value: item.progress > 0 ? item.progress : null,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF17130F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          // Subtle re-grading indicator while sliders settle.
          if (item != null &&
              item.status == PhotoStatus.grading &&
              item.afterImage != null)
            const Positioned(
              right: 12,
              bottom: 12,
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyDropZone extends StatelessWidget {
  final VoidCallback onPick;
  const _EmptyDropZone({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.outlineVariant, width: 1.5),
            color: scheme.surfaceContainerLow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_upload_outlined, size: 56, color: scheme.primary),
              const SizedBox(height: 20),
              Text(
                'Drag & drop wedding photos',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'JPG · PNG · HEIC — up to 50 MB each.\n'
                'Photos are graded right in your browser; nothing is uploaded.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Choose Photos'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.primary, width: 2),
              color: scheme.surface,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.file_download_outlined,
                    size: 44, color: scheme.primary),
                const SizedBox(height: 12),
                const Text('Drop photos to add them'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExportOverlay extends StatelessWidget {
  final AppState state;
  const _ExportOverlay({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.65),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Exporting',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: state.exportProgress,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 12),
              Text(
                state.exportLabel,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
