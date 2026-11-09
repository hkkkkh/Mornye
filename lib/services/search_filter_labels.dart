import 'package:flutter/widgets.dart';
import 'package:mornye/models/extension.dart';

/// Persian display labels for the search filter chips.
///
/// When an extension provides search (e.g. Amazon Music), its own filter
/// list carries English labels ("Songs", "Albums", "Artists",
/// "Playlists"), so the app translation does not cover them. This is a
/// display-only mapping: filter ids and the search itself are never
/// touched. Only the label is translated, and only when the app runs in
/// Persian. Any filter not listed here falls back to the extension text
/// unchanged.
class SearchFilterLabels {
  const SearchFilterLabels._();

  static const Map<String, String> _faById = {
    'track': 'آهنگ‌ها',
    'artist': 'خوانندگان',
    'album': 'آلبوم‌ها',
    'playlist': 'فهرست‌های پخش',
  };

  static const Map<String, String> _faByLabel = {
    'Songs': 'آهنگ‌ها',
    'Song': 'آهنگ‌ها',
    'Tracks': 'آهنگ‌ها',
    'Track': 'آهنگ‌ها',
    'Music': 'آهنگ‌ها',
    'Artists': 'خوانندگان',
    'Artist': 'خوانندگان',
    'Albums': 'آلبوم‌ها',
    'Album': 'آلبوم‌ها',
    'Playlists': 'فهرست‌های پخش',
    'Playlist': 'فهرست‌های پخش',
  };

  /// Persian label for [filter] when the app runs in Persian, otherwise
  /// the extension label unchanged.
  static String label(BuildContext context, SearchFilter filter) {
    if (Localizations.localeOf(context).languageCode != 'fa') {
      return filter.label ?? filter.id;
    }
    final byId = _faById[canonicalExtensionSearchFilterId(filter.id)];
    if (byId != null) return byId;
    return _faByLabel[filter.label ?? ''] ?? filter.label ?? filter.id;
  }
}
