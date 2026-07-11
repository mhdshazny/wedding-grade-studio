import 'package:flutter/material.dart';

import '../state/app_state.dart';

/// Horizontal thumbnail strip with per-photo status and remove buttons.
class PhotoStrip extends StatelessWidget {
  final AppState state;
  const PhotoStrip({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 96,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        scrollDirection: Axis.horizontal,
        itemCount: state.photos.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == state.photos.length) {
            return _AddTile(onTap: state.pickAndAdd);
          }
          final item = state.photos[index];
          final isSelected = item == state.selected;
          return GestureDetector(
            onTap: () => state.selectPhoto(item),
            child: Stack(
              children: [
                Container(
                  width: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? scheme.primary : scheme.outlineVariant,
                      width: isSelected ? 2 : 1,
                    ),
                    color: scheme.surfaceContainerHigh,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: item.thumb != null
                      ? RawImage(image: item.thumb, fit: BoxFit.cover)
                      : const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                ),
                // Status badge.
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: _statusBadge(item, scheme),
                ),
                // Remove button.
                Positioned(
                  right: 2,
                  top: 2,
                  child: InkWell(
                    onTap: () => state.removePhoto(item),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child:
                          const Icon(Icons.close, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statusBadge(PhotoItem item, ColorScheme scheme) {
    switch (item.status) {
      case PhotoStatus.ready:
        return Icon(Icons.check_circle, size: 16, color: scheme.primary);
      case PhotoStatus.error:
        return Tooltip(
          message: item.error ?? 'Failed',
          child: Icon(Icons.error, size: 16, color: scheme.error),
        );
      case PhotoStatus.decoding:
      case PhotoStatus.analyzing:
      case PhotoStatus.grading:
        return Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            shape: BoxShape.circle,
          ),
          child: const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case PhotoStatus.queued:
        return const SizedBox.shrink();
    }
  }
}

class _AddTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AddTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Icon(Icons.add_photo_alternate_outlined,
            color: scheme.primary, size: 28),
      ),
    );
  }
}
