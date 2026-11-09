import 'package:flutter/widgets.dart';

/// Persian display text for the 14 official store extensions.
///
/// The store registry only ships English names and descriptions, and the
/// extension packages themselves are not ours to change, so this is a
/// display-only mapping keyed by extension id: ids, download URLs and
/// versions are never touched. Brand names stay as they are (Spotify Web,
/// YouTube Music, ...); only the description is translated, and only when
/// the app runs in Persian. Any id not listed here falls back to the
/// registry text unchanged.
class ExtensionDisplayText {
  const ExtensionDisplayText._();

  static const Map<String, String> _faDescriptions = {
    'spotify-web':
        'منبع اطلاعات اسپاتیفای برای مورنی؛ با اطلاعات کامل انتشار، دیسک، شناسه کاتالوگ، عوامل و تصویر جلد.',
    'amazon':
        'اطلاعات و دانلود از آمازون موزیک؛ با برچسب دالبی اتموس، اطلاعات کامل انتشار، تصویر جلد اصلی و صدای بدون افت کیفیت.',
    'apple-music':
        'منبع اطلاعات و متن آهنگ اپل موزیک برای مورنی؛ با تطابق دقیق آهنگ و اطلاعات کامل انتشار.',
    'soundcloud':
        'اطلاعات و دانلود از ساندکلاود؛ جستجوی آهنگ، آلبوم، لیست پخش و خواننده، و دانلود مستقیم.',
    'ytmusic-spotiflac':
        'اطلاعات و دانلود از یوتیوب موزیک؛ با اطلاعات آلبوم، خواننده، انتشار و عوامل آهنگ.',
    'deezer':
        'اطلاعات و دانلود بدون افت کیفیت از دیزر؛ با اطلاعات کامل انتشار، دیسک، عوامل، ژانر و تصویر جلد باکیفیت.',
    'qobuz-web':
        'اطلاعات و دانلود از کوبوز برای مورنی؛ با جستجوی آلبوم، اطلاعات کامل انتشار، عوامل و تصویر جلد اصلی.',
    'tidal-web':
        'اطلاعات، جستجو و دانلود از تایدال برای مورنی؛ با اطلاعات کامل انتشار، عوامل و دیسک.',
    'bugs-music':
        'اطلاعات باگز موزیک؛ کاتالوگ خواننده‌ها، جدول‌های لحظه‌ای، روزانه و هفتگی، جدول ژانر و وارد کردن با لینک.',
    'melon-music':
        'اطلاعات ملون موزیک؛ جدول‌های دوره‌ای و ژانر، HOT100، کاتالوگ آلبوم و خواننده، لیست‌های دی‌جی و وارد کردن با لینک.',
    'genie-music':
        'اطلاعات جینی موزیک؛ کاتالوگ خواننده‌ها، جدول TOP200 دوره‌ای، جدول ژانر، لیست‌های دی‌جی و وارد کردن با لینک.',
    'jiosaavn':
        'جستجو و دانلود آهنگ‌های جیو ساون؛ با اطلاعات آلبوم، لیست پخش و خواننده و خوراک خانه.',
    'beatport':
        'جستجوی آهنگ، خواننده و انتشار در بیت‌پورت؛ دیسکوگرافی خواننده و دانلود FLAC اصلی یا AAC با کیفیت ۲۵۶.',
    'jellyfin':
        'سرور جلی‌فین خودت را به‌عنوان منبع جستجو، دانلود، متن آهنگ و خوراک خانه استفاده کن.',
  };

  /// Persian description for [id] when the app runs in Persian, otherwise
  /// [fallback] (the registry text) unchanged.
  static String description(BuildContext context, String id, String fallback) {
    if (Localizations.localeOf(context).languageCode != 'fa') {
      return fallback;
    }
    return _faDescriptions[id] ?? fallback;
  }
}
