import 'package:flutter/material.dart';

import '../state/app_state.dart';

/// Right-hand (or bottom, on mobile) panel with the grading controls.
class ControlsPanel extends StatelessWidget {
  final AppState state;
  const ControlsPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state.settings;
    final scene = state.selected?.scene;
    final hasPhotos = state.photos.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(
          children: [
            Text('Adjustments',
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton.icon(
              onPressed: state.resetSettings,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Reset'),
            ),
          ],
        ),
        if (scene != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                avatar: const Icon(Icons.auto_awesome, size: 16),
                label: Text('Scene: ${scene.label}'),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        _SliderTile(
          label: 'Strength',
          value: s.strength,
          min: 0,
          max: 1,
          display: _percent(s.strength),
          onChanged: (v) => state.updateSettings(s.copyWith(strength: v)),
        ),
        _SliderTile(
          label: 'Warmth',
          value: s.warmth,
          min: -1,
          max: 1,
          display: _signed(s.warmth),
          onChanged: (v) => state.updateSettings(s.copyWith(warmth: v)),
        ),
        _SliderTile(
          label: 'Contrast',
          value: s.contrast,
          min: -1,
          max: 1,
          display: _signed(s.contrast),
          onChanged: (v) => state.updateSettings(s.copyWith(contrast: v)),
        ),
        _SliderTile(
          label: 'Highlights',
          value: s.highlights,
          min: -1,
          max: 1,
          display: _signed(s.highlights),
          onChanged: (v) => state.updateSettings(s.copyWith(highlights: v)),
        ),
        _SliderTile(
          label: 'Shadows',
          value: s.shadows,
          min: -1,
          max: 1,
          display: _signed(s.shadows),
          onChanged: (v) => state.updateSettings(s.copyWith(shadows: v)),
        ),
        _SliderTile(
          label: 'Skin Warmth',
          value: s.skinWarmth,
          min: -1,
          max: 1,
          display: _signed(s.skinWarmth),
          onChanged: (v) => state.updateSettings(s.copyWith(skinWarmth: v)),
        ),
        _SliderTile(
          label: 'Greens',
          value: s.greens,
          min: 0,
          max: 1,
          display: _percent(s.greens),
          onChanged: (v) => state.updateSettings(s.copyWith(greens: v)),
        ),
        _SliderTile(
          label: 'Blues',
          value: s.blues,
          min: 0,
          max: 1,
          display: _percent(s.blues),
          onChanged: (v) => state.updateSettings(s.copyWith(blues: v)),
        ),
        _SliderTile(
          label: 'Bloom',
          value: s.bloom,
          min: 0,
          max: 1,
          display: _percent(s.bloom),
          onChanged: (v) => state.updateSettings(s.copyWith(bloom: v)),
        ),
        _SliderTile(
          label: 'Sharpness',
          value: s.sharpness,
          min: 0,
          max: 1,
          display: _percent(s.sharpness),
          onChanged: (v) => state.updateSettings(s.copyWith(sharpness: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Film Grain'),
          value: s.grainEnabled,
          onChanged: (v) => state.updateSettings(s.copyWith(grainEnabled: v)),
        ),
        if (s.grainEnabled)
          _SliderTile(
            label: 'Grain Amount',
            value: s.grain,
            min: 0,
            max: 1,
            display: _percent(s.grain),
            onChanged: (v) => state.updateSettings(s.copyWith(grain: v)),
          ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        Text('Export', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Full resolution · 95% quality',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: state.selected != null && !state.exporting
              ? () => state.exportSelected(png: false)
              : null,
          icon: const Icon(Icons.download),
          label: const Text('Download JPEG'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: state.selected != null && !state.exporting
              ? () => state.exportSelected(png: true)
              : null,
          icon: const Icon(Icons.download_outlined),
          label: const Text('Download PNG'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: hasPhotos && !state.exporting
              ? state.exportAllZip
              : null,
          icon: const Icon(Icons.folder_zip_outlined),
          label: const Text('Export All as ZIP'),
        ),
      ],
    );
  }

  static String _percent(double v) => '${(v * 100).round()}%';
  static String _signed(double v) {
    final n = (v * 100).round();
    return n > 0 ? '+$n' : '$n';
  }
}

class _SliderTile extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  const _SliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: theme.textTheme.bodyMedium),
            const Spacer(),
            Text(
              display,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
          ],
        ),
        SizedBox(
          height: 32,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
