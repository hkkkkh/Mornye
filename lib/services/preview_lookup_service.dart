import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mornye/models/track.dart';
import 'package:mornye/utils/logger.dart';

final _log = AppLogger('PreviewLookup');

/// Finds a short preview clip for a track whose extension did not supply
/// one.
///
/// Search results only carry a `preview_url` when the extension that
/// produced them returns one, so for many sources the per-track play
/// button used to disappear entirely. This service fills that gap with
/// the public, key-free preview catalogues: iTunes Search first, then
/// Deezer. Both return 30-second clips. Nothing is downloaded and the
/// result is only ever played through the existing preview player.
///
/// The lookup is keyed by ISRC when the track has one, so an exact
/// recording is matched before falling back to an artist/title search.
class PreviewLookupService {
  PreviewLookupService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  /// Resolved preview URLs by track key, including misses (null) so a
  /// track without any public preview is not looked up again on every tap.
  final Map<String, String?> _cache = {};

  static const _timeout = Duration(seconds: 8);

  Future<String?> findPreviewUrl(Track track) async {
    final supplied = track.previewUrl?.trim() ?? '';
    if (supplied.isNotEmpty) return supplied;

    final key = _cacheKey(track);
    if (_cache.containsKey(key)) return _cache[key];

    String? url;
    try {
      url = await _fromItunes(track) ?? await _fromDeezer(track);
    } catch (e) {
      // A network failure is transient: retry once after a short pause
      // instead of reporting "no preview". A failed lookup is never
      // cached, so the next tap tries again instead of staying broken
      // for the rest of the app session.
      _log.w('Preview lookup failed for ${track.name}, retrying once: $e');
      try {
        await Future<void>.delayed(const Duration(seconds: 1));
        url = await _fromItunes(track) ?? await _fromDeezer(track);
      } catch (e) {
        _log.w('Preview lookup retry failed for ${track.name}: $e');
        return null;
      }
    }
    _cache[key] = url;
    return url;
  }

  String _cacheKey(Track track) {
    final isrc = track.isrc?.trim() ?? '';
    if (isrc.isNotEmpty) return 'isrc:$isrc';
    return 'id:${track.id}';
  }

  Future<String?> _fromItunes(Track track) async {
    final isrc = track.isrc?.trim() ?? '';
    if (isrc.isNotEmpty) {
      final lookup = await _getJson(
        Uri.https('itunes.apple.com', '/lookup', {
          'isrc': isrc,
          'entity': 'song',
        }),
      );
      final url = _firstPreview(
        lookup?['results'] as List<dynamic>?,
        titleKey: 'trackName',
        artistKey: 'artistName',
        previewKey: 'previewUrl',
        track: track,
      );
      if (url != null) return url;
    }
    final search = await _getJson(
      Uri.https('itunes.apple.com', '/search', {
        'term': '${track.artistName} ${track.name}',
        'entity': 'song',
        'limit': '5',
      }),
    );
    return _firstPreview(
      search?['results'] as List<dynamic>?,
      titleKey: 'trackName',
      artistKey: 'artistName',
      previewKey: 'previewUrl',
      track: track,
    );
  }

  Future<String?> _fromDeezer(Track track) async {
    final isrc = track.isrc?.trim() ?? '';
    if (isrc.isNotEmpty) {
      final byIsrc = await _getJson(
        Uri.https('api.deezer.com', '/track/isrc:$isrc'),
      );
      if (byIsrc != null && byIsrc['error'] == null) {
        final url = _playable(byIsrc['preview']?.toString());
        if (url != null) return url;
      }
    }
    final search = await _getJson(
      Uri.https('api.deezer.com', '/search', {
        'q': 'artist:"${track.artistName}" track:"${track.name}"',
        'limit': '5',
      }),
    );
    return _firstPreview(
      search?['data'] as List<dynamic>?,
      titleKey: 'title',
      artistKey: 'artist',
      previewKey: 'preview',
      track: track,
    );
  }

  /// Picks the best matching result, preferring an exact title/artist
  /// match and otherwise taking the first playable preview.
  String? _firstPreview(
    List<dynamic>? results, {
    required String titleKey,
    required String artistKey,
    required String previewKey,
    required Track track,
  }) {
    if (results == null) return null;
    String? first;
    for (final entry in results) {
      if (entry is! Map<String, dynamic>) continue;
      final url = _playable(entry[previewKey]?.toString());
      if (url == null) continue;
      first ??= url;
      final title = _norm(entry[titleKey]?.toString());
      final artist = _norm(_artistName(entry[artistKey]));
      if (title.isNotEmpty &&
          title == _norm(track.name) &&
          (artist.isEmpty || artist == _norm(track.artistName))) {
        return url;
      }
    }
    return first;
  }

  String _artistName(Object? value) {
    if (value is Map<String, dynamic>) return value['name']?.toString() ?? '';
    return value?.toString() ?? '';
  }

  String? _playable(String? url) {
    final trimmed = url?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final scheme = Uri.tryParse(trimmed)?.scheme;
    if (scheme != 'https' && scheme != 'http') return null;
    return trimmed;
  }

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    final response = await _client
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(_timeout);
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    return decoded;
  }

  static String _norm(String? value) => (value ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]+'), ' ')
      .trim();
}
