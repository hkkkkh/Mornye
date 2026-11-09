import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mornye/l10n/l10n.dart';
import 'package:mornye/providers/preview_player_provider.dart';
import 'package:mornye/widgets/app_loading_indicator.dart';
import 'package:mornye/widgets/cached_cover_image.dart';

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

double _progressOf(PreviewPlayerState state) {
  final total = state.duration.inMilliseconds;
  if (total <= 0) return 0;
  return (state.position.inMilliseconds / total).clamp(0.0, 1.0);
}

/// Compact bar shown above the bottom navigation while a preview plays.
///
/// The main player's mini player never appears for previews (it follows the
/// main player only), so without this bar a playing preview had no visible
/// controls at all: no way to pause, stop, or see the track. Tapping the
/// bar opens [_PreviewDetailsSheet].
class PreviewPlayerBar extends ConsumerWidget {
  const PreviewPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(previewPlayerProvider);
    if (state.status == PreviewStatus.idle) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final notifier = ref.read(previewPlayerProvider.notifier);
    final title = state.title ?? '';
    final artist = state.artist ?? '';
    final coverUrl = state.coverUrl;

    return Material(
      color: scheme.surfaceContainer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => showModalBottomSheet<void>(
              context: context,
              useSafeArea: true,
              builder: (_) => const _PreviewDetailsSheet(),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  _CoverThumbnail(coverUrl: coverUrl, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        if (artist.isNotEmpty)
                          Text(
                            artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  if (state.status == PreviewStatus.loading)
                    AppLoadingIndicator(
                      size: 24,
                      strokeWidth: 2,
                      color: scheme.primary,
                    )
                  else ...[
                    IconButton(
                      iconSize: 22,
                      icon: const Icon(Icons.replay_10_rounded),
                      onPressed: () =>
                          notifier.seekBy(const Duration(seconds: -10)),
                    ),
                    IconButton(
                      icon: Icon(
                        state.status == PreviewStatus.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      tooltip: state.status == PreviewStatus.playing
                          ? context.l10n.previewStop
                          : context.l10n.previewPlay,
                      onPressed: () {
                        if (state.status == PreviewStatus.playing) {
                          notifier.pause();
                        } else if (state.status == PreviewStatus.paused) {
                          notifier.resume();
                        }
                      },
                    ),
                    IconButton(
                      iconSize: 22,
                      icon: const Icon(Icons.forward_10_rounded),
                      onPressed: () =>
                          notifier.seekBy(const Duration(seconds: 10)),
                    ),
                  ],
                  IconButton(
                    icon: const Icon(Icons.stop_rounded),
                    tooltip: context.l10n.previewStop,
                    onPressed: notifier.stop,
                  ),
                ],
              ),
            ),
          ),
          const _SeekBar(),
        ],
      ),
    );
  }
}

class _CoverThumbnail extends StatelessWidget {
  const _CoverThumbnail({required this.coverUrl, required this.size});

  final String? coverUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = coverUrl?.trim() ?? '';
    if (url.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.music_note_rounded),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedCoverImage(
        imageUrl: url,
        width: size,
        height: size,
        memCacheWidth: 128,
        memCacheHeight: 128,
      ),
    );
  }
}

/// Thin progress bar that seeks when tapped or dragged, so the preview can
/// be jumped forward (or back) from the bottom bar or the details sheet.
/// The bar is wrapped in vertical padding so the tap target is taller than
/// the thin visual line. Seeking reads the tap position, so it works even
/// while the position stream keeps updating.
class _SeekBar extends ConsumerWidget {
  const _SeekBar({this.minHeight = 2});

  final double minHeight;

  void _seekFromTap(
    WidgetRef ref,
    PreviewPlayerState state,
    BuildContext context,
    Offset globalPosition,
  ) {
    final total = state.duration.inMilliseconds;
    final box = context.findRenderObject() as RenderBox?;
    if (total <= 0 || box == null || !box.hasSize) return;
    final width = box.size.width;
    if (width <= 0) return;
    final raw = (box.globalToLocal(globalPosition).dx / width).clamp(0.0, 1.0);
    // In RTL (e.g. Persian) the bar fills from the right, so a tap/drag on
    // the right is the start of the clip: mirror the physical x coordinate.
    // Without this, dragging forward seeks backward.
    final fraction = Directionality.of(context) == TextDirection.rtl
        ? 1.0 - raw
        : raw;
    ref
        .read(previewPlayerProvider.notifier)
        .seek(Duration(milliseconds: (fraction * total).round()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(previewPlayerProvider);
    final progress = _progressOf(state);
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) =>
          _seekFromTap(ref, state, context, details.globalPosition),
      onHorizontalDragUpdate: (details) =>
          _seekFromTap(ref, state, context, details.globalPosition),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(
          value: progress,
          minHeight: minHeight,
          backgroundColor: scheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}

/// Track details for the playing preview.
///
/// There is no in-app volume here on purpose: the preview plays at the
/// phone's system volume, adjusted with the phone's own volume buttons.
class _PreviewDetailsSheet extends ConsumerWidget {
  const _PreviewDetailsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(previewPlayerProvider);
    // The preview ended (stopped, or the main player took over): close the
    // sheet instead of showing an empty one.
    ref.listen(previewPlayerProvider.select((s) => s.status), (_, status) {
      if (status == PreviewStatus.idle && context.mounted) {
        Navigator.of(context).pop();
      }
    });

    final scheme = Theme.of(context).colorScheme;
    final notifier = ref.read(previewPlayerProvider.notifier);
    final title = state.title ?? '';
    final artist = state.artist ?? '';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            _CoverThumbnail(coverUrl: state.coverUrl, size: 160),
            const SizedBox(height: 16),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (artist.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            const _SeekBar(minHeight: 4),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(state.position),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  _formatDuration(state.duration),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 28,
                  icon: const Icon(Icons.replay_10_rounded),
                  onPressed: () =>
                      notifier.seekBy(const Duration(seconds: -10)),
                ),
                const SizedBox(width: 16),
                IconButton.filled(
                  iconSize: 32,
                  icon: Icon(
                    state.status == PreviewStatus.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  tooltip: state.status == PreviewStatus.playing
                      ? context.l10n.previewStop
                      : context.l10n.previewPlay,
                  onPressed: () {
                    if (state.status == PreviewStatus.playing) {
                      notifier.pause();
                    } else if (state.status == PreviewStatus.paused) {
                      notifier.resume();
                    }
                  },
                ),
                const SizedBox(width: 16),
                IconButton(
                  iconSize: 28,
                  icon: const Icon(Icons.forward_10_rounded),
                  onPressed: () => notifier.seekBy(const Duration(seconds: 10)),
                ),
                const SizedBox(width: 16),
                IconButton.outlined(
                  iconSize: 28,
                  icon: const Icon(Icons.stop_rounded),
                  tooltip: context.l10n.previewStop,
                  onPressed: notifier.stop,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
