import 'package:flutter/widgets.dart';

/// Persian display titles for the home-feed sections.
///
/// Section titles come from the music extension's home feed (e.g. Amazon
/// Music: "Hot Artists", "Hot Songs"), not from the app's own strings, so
/// the app translation does not cover them. This is a display-only mapping
/// keyed by the exact English title: section ids, uris and items are never
/// touched. Only the title is translated, and only when the app runs in
/// Persian. Any title not listed here falls back to the feed text
/// unchanged.
class ExploreSectionTitles {
  const ExploreSectionTitles._();

  static const Map<String, String> _faTitles = {
    'Hot Artists': 'خواننده‌های داغ',
    'Hot Songs': 'آهنگ‌های داغ',
    'Hot Albums': 'آلبوم‌های داغ',
    'Hot Playlists': 'لیست‌های داغ',
    'New Release Playlists': 'لیست‌های تازه منتشرشده',
    'New Release Albums': 'آلبوم‌های تازه منتشرشده',
    'New Release Songs': 'آهنگ‌های تازه منتشرشده',
    'New Releases': 'تازه‌های انتشار',
    'Top Artists': 'خواننده‌های برتر',
    'Top Songs': 'آهنگ‌های برتر',
    'Top Albums': 'آلبوم‌های برتر',
    'Top Playlists': 'لیست‌های برتر',
    'New Artists': 'خواننده‌های جدید',
    'Featured': 'ویژه',
    'Quick Picks': 'انتخاب‌های سریع',
    'Recently Played': 'اخیراً پخش‌شده',
    'Made For You': 'ساخته‌شده برای تو',
    'Trending': 'ترند',
    'Top Charts': 'جدول‌های برتر',
    'Charts': 'جدول‌ها',
  };

  /// Persian title for [title] when the app runs in Persian, otherwise
  /// [title] unchanged.
  static String title(BuildContext context, String title) {
    if (Localizations.localeOf(context).languageCode != 'fa') {
      return title;
    }
    return _faTitles[title] ?? title;
  }
}
