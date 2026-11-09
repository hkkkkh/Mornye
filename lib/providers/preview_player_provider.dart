import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mornye/providers/music_player_provider.dart';
import 'package:mornye/providers/system_volume_provider.dart';
import 'package:mornye/services/platform_bridge.dart';
import 'package:mornye/services/playback_deck.dart';
import 'package:mornye/services/system_volume_service.dart';
import 'package:mornye/utils/desktop_platform.dart';
import 'package:mornye/utils/logger.dart';
import 'package:volume_controller/volume_controller.dart';

final _log = AppLogger('PreviewPlayer');

/// Extensions that require the `deferredPreview` runtime feature can defer a
/// preview lookup until it plays, with a link such as
/// `mornye-preview:<extension id>/<track id>` (both segments URI-encoded).
/// The extension's `resolvePreview({id})` returns the URL.
const deferredPreviewScheme = 'mornye-preview';

Future<String> _playablePreviewUrl(String url) async {
  final link = Uri.tryParse(url);
  if (link == null || link.scheme != deferredPreviewScheme) return url;
  final segments = link.pathSegments;
  if (segments.length != 2 || segments.any((segment) => segment.isEmpty)) {
    throw FormatException('Invalid deferred preview link', url);
  }
  final result = await PlatformBridge.invokeExtensionAction(
    segments[0],
    'resolvePreview',
    input: {'id': segments[1]},
  );
  final resolved = result['preview_url']?.toString().trim() ?? '';
  final scheme = Uri.tryParse(resolved)?.scheme;
  if (scheme != 'https' && scheme != 'http') {
    throw StateError('The extension returned no playable preview');
  }
  return resolved;
}

enum PreviewStatus { idle, loading, playing, paused }

class PreviewPlayerState {
  final String? activeUrl;
  final PreviewStatus status;
  final Duration position;
  final Duration duration;

  /// Track shown in the preview bar/sheet. Null when the preview was
  /// started without metadata (only the URL is required to play).
  final String? title;
  final String? artist;
  final String? coverUrl;

  const PreviewPlayerState({
    this.activeUrl,
    this.status = PreviewStatus.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.title,
    this.artist,
    this.coverUrl,
  });

  bool get isActive => activeUrl != null && activeUrl!.isNotEmpty;

  bool isActiveUrl(String? url) =>
      url != null && url.isNotEmpty && url == activeUrl;

  PreviewPlayerState copyWith({
    String? activeUrl,
    bool clearActiveUrl = false,
    PreviewStatus? status,
    Duration? position,
    Duration? duration,
    String? title,
    String? artist,
    String? coverUrl,
  }) {
    return PreviewPlayerState(
      activeUrl: clearActiveUrl ? null : (activeUrl ?? this.activeUrl),
      status: status ?? this.status,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      coverUrl: coverUrl ?? this.coverUrl,
    );
  }
}

/// Plays previews through the runtime's preview deck, so desktop previews
/// use the same engine and in-app volume as the main player.
class PreviewPlayerController extends Notifier<PreviewPlayerState> {
  PlaybackDeck? _player;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  AppLifecycleListener? _lifecycleListener;

  /// False once the user stops the preview, so a completion event that
  /// arrives from the engine after `stop()` cannot restart playback.
  bool _loopAllowed = false;

  /// Last known phone system volume (0-1). The preview deck's gain mirrors
  /// it, so the preview is exactly as loud as the phone: a muted phone
  /// means a silent preview. Kept current by the subscription in [build].
  double _systemVolume = 1.0;
  StreamSubscription<double>? _volumeSubscription;

  /// Backstop for the volume-change event stream: while a preview plays,
  /// the phone's music-stream volume is re-read directly every 500 ms, so
  /// the preview follows the volume keys even if the event stream stays
  /// silent on this phone (the events are the fast path; the poll is the
  /// backstop). Only runs while a preview is playing.
  Timer? _volumePollTimer;

  /// Reads the phone's current music-stream volume (0-1) straight from
  /// the system, falling back to the last known value on error.
  Future<double> _readSystemVolume() async {
    if (isDesktopPlatform) return _systemVolume;
    try {
      final value = await VolumeController.instance.getVolume();
      if (value.isFinite) return value.clamp(0.0, 1.0);
    } catch (e) {
      _log.w('Failed to read system volume: $e');
    }
    return _systemVolume;
  }

  /// Applies the phone's current volume to the live preview deck when it
  /// moved since the last sync.
  Future<void> _syncVolumeFromSystem() async {
    if (!state.isActive) return;
    final current = await _readSystemVolume();
    if ((current - _systemVolume).abs() < 0.01) return;
    _systemVolume = current;
    if (isDesktopPlatform) return;
    final player = _player;
    if (player == null) return;
    try {
      await player.setVolume(current);
    } catch (e) {
      _log.w('Failed to sync preview volume: $e');
    }
  }

  void _startVolumePolling() {
    _volumePollTimer?.cancel();
    _volumePollTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(_syncVolumeFromSystem()),
    );
  }

  void _stopVolumePolling() {
    _volumePollTimer?.cancel();
    _volumePollTimer = null;
  }

  @override
  PreviewPlayerState build() {
    _lifecycleListener = AppLifecycleListener(
      onStateChange: _handleAppLifecycleState,
    );
    final runtime = ref.read(musicPlayerRuntimeProvider);
    Future<void> stopPreview() async {
      if (state.isActive) await stop();
    }

    // Mirror the phone's volume onto the live preview deck (mobile only:
    // on desktop the deck already multiplies by the in-app gain). This is
    // what makes the preview follow the phone's volume buttons and go
    // silent when the phone is muted, even if the system does not route
    // the keys to the media stream on its own.
    _volumeSubscription = SystemVolumeService.instance.changes.listen((value) {
      _systemVolume = value;
      if (isDesktopPlatform) return;
      final player = _player;
      if (player != null && state.isActive) {
        unawaited(
          player
              .setVolume(value)
              .catchError(
                (Object error) =>
                    _log.w('Failed to sync preview volume: $error'),
              ),
        );
      }
    });

    runtime.exclusiveAudioHook = stopPreview;
    ref.onDispose(() {
      _stopVolumePolling();
      _volumeSubscription?.cancel();
      if (identical(runtime.exclusiveAudioHook, stopPreview)) {
        runtime.exclusiveAudioHook = null;
      }
      _disposePlayer();
    });
    return const PreviewPlayerState();
  }

  void _handleAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.hidden ||
        lifecycleState == AppLifecycleState.detached) {
      if (state.isActive) {
        unawaited(stop());
      }
    }
  }

  PlaybackDeck _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;

    final player = ref
        .read(musicPlayerRuntimeProvider)
        .dependencies
        .createPreviewDeck('preview-player');
    player.startPositionUpdates(const Duration(milliseconds: 200));
    _attachListeners(player);
    _player = player;
    return player;
  }

  void _attachListeners(PlaybackDeck player) {
    _subscriptions.add(
      player.onPlayerStateChanged.listen(
        _handlePlayerStateChanged,
        onError: (Object error) => _log.w('Preview playback error: $error'),
      ),
    );
    _subscriptions.add(
      player.onPositionChanged.listen((position) {
        if (state.status == PreviewStatus.playing ||
            state.status == PreviewStatus.paused) {
          state = state.copyWith(position: position);
        }
      }),
    );
    _subscriptions.add(
      player.onDurationChanged.listen((duration) {
        state = state.copyWith(duration: duration);
      }),
    );
    _subscriptions.add(
      player.onPlayerComplete.listen((_) {
        unawaited(_restartLoop());
      }),
    );
  }

  /// Preview clips are ~30 seconds: restart the same clip when it ends
  /// instead of stopping, until the user pauses, stops, or switches
  /// tracks. Guarded so a completion event arriving after a stop, a
  /// pause, or a track switch cannot restart playback.
  Future<void> _restartLoop() async {
    final player = _player;
    if (player == null ||
        !_loopAllowed ||
        !state.isActive ||
        state.status != PreviewStatus.playing) {
      return;
    }
    try {
      await player.seek(Duration.zero);
      await player.resume();
      state = state.copyWith(position: Duration.zero);
    } catch (e) {
      _log.w('Failed to loop preview: $e');
    }
  }

  void _discardActivePlayer() {
    _stopVolumePolling();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    final player = _player;
    _player = null;
    if (player != null) {
      unawaited(
        player.dispose().catchError(
          (Object error) => _log.w('Failed to release preview: $error'),
        ),
      );
    }
  }

  void _handlePlayerStateChanged(PlaybackDeckState playerState) {
    switch (playerState) {
      case PlaybackDeckState.playing:
        state = state.copyWith(status: PreviewStatus.playing);
        break;
      case PlaybackDeckState.paused:
        if (state.isActive) {
          state = state.copyWith(status: PreviewStatus.paused);
        }
        break;
      case PlaybackDeckState.stopped:
      case PlaybackDeckState.completed:
        break;
      case PlaybackDeckState.disposed:
        break;
    }
  }

  Future<void> toggle(
    String? url, {
    String? title,
    String? artist,
    String? coverUrl,
  }) async {
    final trimmed = url?.trim() ?? '';
    if (trimmed.isEmpty) return;

    if (state.isActiveUrl(trimmed)) {
      if (state.status == PreviewStatus.playing) {
        await pause();
      } else if (state.status == PreviewStatus.paused) {
        await resume();
      }
      return;
    }

    await play(trimmed, title: title, artist: artist, coverUrl: coverUrl);
  }

  Future<void> play(
    String url, {
    String? title,
    String? artist,
    String? coverUrl,
  }) async {
    final trimmed = url.trim();
    // The main player holds the device in exclusive mode.
    if (trimmed.isEmpty || playbackExclusiveOutput.value) return;

    try {
      await ref.read(musicPlayerRuntimeProvider).handler?.pause();
    } catch (_) {}

    // A fresh preview (nothing playing) starts at medium system volume:
    // there is no in-app volume for previews anymore — the preview plays
    // at the phone's volume, and the user adjusts it with the phone's
    // own volume buttons. Track switches keep the current volume.
    if (!state.isActive) {
      try {
        await ref.read(systemVolumeWriterProvider)(0.5);
      } catch (e) {
        _log.w('Could not set system volume to medium: $e');
      }
    }
    state = PreviewPlayerState(
      activeUrl: trimmed,
      status: PreviewStatus.loading,
      title: title,
      artist: artist,
      coverUrl: coverUrl,
    );
    _loopAllowed = true;

    final String source;
    try {
      source = await _playablePreviewUrl(trimmed);
    } catch (e) {
      _log.w('Preview link could not be resolved: $e');
      if (state.isActiveUrl(trimmed)) {
        _loopAllowed = false;
        state = const PreviewPlayerState();
      }
      rethrow;
    }
    // Another preview may have started, or this one stopped, meanwhile.
    if (!state.isActiveUrl(trimmed)) return;

    try {
      await _playOnPlayer(_ensurePlayer(), source);
    } catch (e) {
      _log.w('Preview playback failed, recreating player and retrying: $e');
      _discardActivePlayer();
      try {
        await _playOnPlayer(_ensurePlayer(), source);
      } catch (retryError) {
        _log.e('Preview playback failed after retry', retryError);
        _discardActivePlayer();
        _loopAllowed = false;
        state = const PreviewPlayerState();
        rethrow;
      }
    }
  }

  Future<void> _playOnPlayer(PlaybackDeck player, String url) async {
    // Same output setup as the other decks (media stream, release mode).
    // The deck gain mirrors the phone's system volume (kept current by the
    // subscription in build), so the preview is exactly as loud as the
    // phone: muted phone means a silent preview. On desktop the deck
    // already multiplies by the in-app gain, so it stays at full gain
    // there. Previews have no normalization gain. The volume is re-read
    // from the system here (not trusted from the last event) and then
    // polled while the preview plays, so the volume keys keep working
    // even if the event stream stays silent.
    await player.configureOutput();
    _systemVolume = isDesktopPlatform ? 1 : await _readSystemVolume();
    await player.setVolume(_systemVolume);
    await player.setNetworkSource(url);
    await player.resume();
    _startVolumePolling();
  }

  Future<void> pause() async {
    final player = _player;
    if (player == null) return;
    _stopVolumePolling();
    try {
      await player.pause();
      state = state.copyWith(status: PreviewStatus.paused);
    } catch (e) {
      _log.w('Failed to pause preview: $e');
    }
  }

  Future<void> resume() async {
    final player = _player;
    if (player == null || !state.isActive) return;
    try {
      await player.resume();
      state = state.copyWith(status: PreviewStatus.playing);
      _startVolumePolling();
    } catch (e) {
      _log.w('Failed to resume preview: $e');
    }
  }

  /// Jumps the playing preview to [position] (bottom bar / details sheet).
  Future<void> seek(Duration position) async {
    final player = _player;
    if (player == null || !state.isActive) return;
    try {
      await player.seek(position);
      state = state.copyWith(position: position);
    } catch (e) {
      _log.w('Failed to seek preview: $e');
    }
  }

  /// Jumps the playing preview forward/backward by [offset] (skip buttons),
  /// clamped to the clip's bounds.
  Future<void> seekBy(Duration offset) async {
    final player = _player;
    if (player == null || !state.isActive) return;
    final total = state.duration.inMilliseconds;
    final target = (state.position + offset).inMilliseconds.clamp(
      0,
      total > 0 ? total : 0,
    );
    await seek(Duration(milliseconds: target));
  }

  Future<void> stop() async {
    // Clear first: a completion event from the engine must not restart
    // the preview after the user stopped it.
    _loopAllowed = false;
    _stopVolumePolling();
    final player = _player;
    if (player == null) {
      state = const PreviewPlayerState();
      return;
    }
    try {
      await player.stop();
    } catch (e) {
      _log.w('Failed to stop preview: $e');
    }
    state = const PreviewPlayerState();
  }

  void _disposePlayer() {
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
    _discardActivePlayer();
  }
}

final previewPlayerProvider =
    NotifierProvider<PreviewPlayerController, PreviewPlayerState>(
      PreviewPlayerController.new,
    );
