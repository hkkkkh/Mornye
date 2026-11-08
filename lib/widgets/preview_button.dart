import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mornye/l10n/l10n.dart';
import 'package:mornye/models/track.dart';
import 'package:mornye/providers/music_player_provider.dart';
import 'package:mornye/providers/preview_player_provider.dart';
import 'package:mornye/providers/settings_provider.dart';
import 'package:mornye/services/preview_lookup_service.dart';
import 'package:mornye/utils/desktop_platform.dart';
import 'package:mornye/widgets/app_icon_button.dart';
import 'package:mornye/widgets/app_loading_indicator.dart';

/// One shared lookup so every row reuses the same cache instead of asking
/// iTunes/Deezer again for a track another row already resolved.
final _previewLookup = PreviewLookupService();

class PreviewButton extends ConsumerStatefulWidget {
  final Track track;
  final double size;

  /// A 32dp pointer target for desktop table rows.
  final bool dense;

  const PreviewButton({
    super.key,
    required this.track,
    this.size = 24,
    this.dense = false,
  });

  @override
  ConsumerState<PreviewButton> createState() => _PreviewButtonState();
}

class _PreviewButtonState extends ConsumerState<PreviewButton> {
  /// Whether a public preview is currently being looked up for this track.
  bool _resolving = false;

  /// Preview URL found by the lookup service for a track whose extension
  /// supplied none. Kept so the button stays in sync with the preview
  /// player (play/pause icon) after the lookup, instead of resolving again
  /// on every tap.
  String? _resolvedUrl;

  Track get _track => widget.track;

  BoxConstraints get _constraints => widget.dense
      ? const BoxConstraints(minWidth: 32, minHeight: 32)
      : const BoxConstraints(minWidth: 48, minHeight: 48);

  ButtonStyle? get _style => widget.dense
      ? IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap)
      : null;

  void _showUnavailable() {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.previewUnavailable)));
  }

  Future<void> _onPressed() async {
    if (_resolving) return;

    // The extension's own preview when it has one, otherwise the URL this
    // button already resolved for the track.
    final direct = _track.previewUrl?.trim() ?? '';
    String? url = _resolvedUrl ?? (direct.isEmpty ? null : direct);
    if (url == null) {
      setState(() => _resolving = true);
      try {
        url = await _previewLookup.findPreviewUrl(_track);
      } catch (_) {
        url = null;
      }
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _resolvedUrl = url;
      });
      if (url == null) {
        _showUnavailable();
        return;
      }
    }

    try {
      await ref.read(previewPlayerProvider.notifier).toggle(url);
    } catch (_) {
      _showUnavailable();
    }
  }

  /// Loosely matches the built-in player's current item to this track so the
  /// per-track button stays in sync with the mini player instead of showing a
  /// conflicting preview state.
  bool _isCurrentMainTrack(MediaItem? item) {
    if (item == null) return false;
    String norm(String? s) => (s ?? '').toLowerCase().trim();
    return norm(item.title) == norm(_track.name) &&
        norm(item.artist) == norm(_track.artistName);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // When the built-in player is currently on this track, mirror and control
    // it (consistent with the mini player) rather than the preview snippet.
    final isCurrentMainTrack = ref.watch(
      currentMediaItemProvider.select(
        (item) => _isCurrentMainTrack(item.value),
      ),
    );
    if (isCurrentMainTrack) {
      final isPlaying = ref.watch(playbackPlayingProvider);
      return AppIconButton(
        iconSize: widget.size,
        padding: EdgeInsets.zero,
        constraints: _constraints,
        style: _style,
        icon: Icon(
          isPlaying
              ? Icons.pause_circle_filled_rounded
              : Icons.play_circle_fill_rounded,
          color: colorScheme.primary,
        ),
        tooltip: isPlaying
            ? context.l10n.previewStop
            : context.l10n.previewPlay,
        onPressed: () =>
            ref.read(musicPlayerControllerProvider).togglePlayPause(isPlaying),
      );
    }

    // A preview would need the output that exclusive mode holds.
    final exclusive =
        isDesktopPlatform &&
        ref.watch(settingsProvider.select((s) => s.exclusiveOutput));
    if (exclusive) return const SizedBox.shrink();

    // The button is always shown now: tracks without an extension preview
    // resolve one on tap through the lookup service, instead of the button
    // disappearing entirely for those sources.
    final effectiveUrl = _resolvedUrl ?? _track.previewUrl;
    final watchedStatus = ref.watch(
      previewPlayerProvider.select(
        (state) => state.isActiveUrl(effectiveUrl)
            ? state.status
            : PreviewStatus.idle,
      ),
    );
    final status = _resolving ? PreviewStatus.loading : watchedStatus;

    final Widget icon;
    final String tooltip;
    switch (status) {
      case PreviewStatus.loading:
        icon = AppLoadingIndicator(
          size: widget.size * 0.7,
          strokeWidth: 2,
          color: colorScheme.primary,
        );
        tooltip = context.l10n.previewStop;
        break;
      case PreviewStatus.playing:
        icon = Icon(
          Icons.pause_circle_filled_rounded,
          color: colorScheme.primary,
        );
        tooltip = context.l10n.previewStop;
        break;
      case PreviewStatus.paused:
        icon = Icon(Icons.play_circle_fill_rounded, color: colorScheme.primary);
        tooltip = context.l10n.previewPlay;
        break;
      case PreviewStatus.idle:
        icon = Icon(
          Icons.play_circle_outline_rounded,
          color: colorScheme.onSurfaceVariant,
        );
        tooltip = context.l10n.previewPlay;
        break;
    }

    return AppIconButton(
      iconSize: widget.size,
      padding: EdgeInsets.zero,
      constraints: _constraints,
      style: _style,
      icon: icon,
      tooltip: tooltip,
      onPressed: _onPressed,
    );
  }
}
