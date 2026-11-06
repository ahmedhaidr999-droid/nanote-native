import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/settings_controller.dart';
import '../i18n/strings.dart';

/// Outcome of a translation.
class TranslateResult {
  final String text;

  /// True when the offline word-by-word dictionary produced this result.
  final bool usedOffline;

  /// Offline word coverage 0..1 (1 for online results).
  final double coverage;

  const TranslateResult(this.text, this.usedOffline, this.coverage);
}

/// Online (MyMemory) + offline (AR↔EN dictionary) translation, Google-Translate
/// hand-off and Ask-AI deep links.
///
/// The online path uses `dart:io` [HttpClient] only — there is no `http`
/// package in the project.
class TranslateService {
  TranslateService._();

  // ---------------------------------------------------------------- detect

  /// 'ar' when more than 30% of the alphanumeric characters are Arabic.
  static String detectSource(String text) {
    var alnum = 0;
    var arabic = 0;
    for (final rune in text.runes) {
      final isAr = _isArabicRune(rune);
      final isAlnum = isAr ||
          (rune >= 0x30 && rune <= 0x39) || // 0-9
          (rune >= 0x41 && rune <= 0x5A) || // A-Z
          (rune >= 0x61 && rune <= 0x7A); // a-z
      if (isAlnum) {
        alnum++;
        if (isAr) arabic++;
      }
    }
    if (alnum == 0) return 'en';
    return arabic / alnum > 0.30 ? 'ar' : 'en';
  }

  static bool _isArabicRune(int r) =>
      (r >= 0x0600 && r <= 0x06FF) ||
      (r >= 0x0750 && r <= 0x077F) ||
      (r >= 0x08A0 && r <= 0x08FF) ||
      (r >= 0xFB50 && r <= 0xFDFF) ||
      (r >= 0xFE70 && r <= 0xFEFF);

  // ---------------------------------------------------------------- online

  /// MyMemory: `https://api.mymemory.translated.net/get?q=..&langpair=SRC|TGT`.
  /// Returns null on any failure (network, timeout, bad payload) so the
  /// caller can fall back to the offline dictionary.
  static Future<TranslateResult?> translateOnline(
      String text, String target) async {
    if (text.trim().isEmpty) return null;
    final source = detectSource(text);
    if (source == target) return TranslateResult(text, false, 1);
    try {
      final uri = Uri.https('api.mymemory.translated.net', '/get', {
        'q': text,
        'langpair': '$source|$target',
      });
      final body = await _httpGet(uri).timeout(const Duration(seconds: 10));
      if (body == null) return null;
      final data = jsonDecode(body);
      if (data is! Map) return null;
      final rd = data['responseData'];
      if (rd is! Map) return null;
      final raw = rd['translatedText'];
      if (raw is! String || raw.isEmpty) return null;
      if (raw.contains('MYMEMORY WARNING') ||
          raw.contains('QUERY LENGTH LIMIT') ||
          raw.contains('INVALID SOURCE')) {
        return null;
      }
      return TranslateResult(_decodeEntities(raw), false, 1);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _httpGet(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) return null;
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }

  /// Replaces the common HTML entities MyMemory returns.
  static String _decodeEntities(String s) {
    return s
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&'); // last, per HTML semantics
  }

  // ---------------------------------------------------------------- offline

  /// Offline word-by-word translation. Refuses (null) when fewer than 25% of
  /// the words are known.
  static TranslateResult? translateOffline(String text, String target) {
    final pass = _offlinePass(text, target);
    if (pass == null) return null;
    final (coverage, translated) = pass;
    if (coverage < 0.25) return null;
    return TranslateResult(translated, true, coverage);
  }

  /// Preview of the offline pass WITHOUT the coverage threshold — used by the
  /// translate popup to distinguish "offline dictionary refused (low
  /// coverage)" from a general failure. Returns (coverage, joined text) or
  /// null when there were no words at all.
  static (double, String)? offlinePreview(String text, String target) =>
      _offlinePass(text, target);

  static (double, String)? _offlinePass(String text, String target) {
    var tgt = target;
    if (tgt == 'auto') tgt = S.isAr ? 'en' : 'ar';
    final source = detectSource(text);
    if (source == tgt) return (1.0, text);
    final words = text
        .split(_wordSplitter)
        .where((w) => w.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) return null;
    final out = <String>[];
    var translated = 0;
    for (final w in words) {
      final t = _lookupWord(w, source, tgt);
      if (t != null) {
        if (t.isNotEmpty) out.add(t);
        translated++;
      } else {
        out.add(w);
      }
    }
    final coverage = translated / words.length;
    return (coverage, out.join(' '));
  }

  static String? _lookupWord(String word, String source, String target) {
    if (source == 'ar') {
      return _lookupArEn(word);
    }
    return _lookupEnAr(word);
  }

  static String? _lookupArEn(String word) {
    final direct = _arEn[word] ?? _arEnNormalized[_normalizeAr(word)];
    if (direct != null) return direct;
    // Try without the definite article (الكتاب -> كتاب).
    final norm = _normalizeAr(word);
    if (norm.length >= 5 && norm.startsWith('ال')) {
      final stripped = norm.substring(2);
      return _arEn[stripped] ?? _arEnNormalized[stripped];
    }
    return null;
  }

  static String? _lookupEnAr(String word) {
    final lower = word.toLowerCase();
    final extra = _enArExtra[lower];
    if (extra != null) return extra; // may be '' (dropped word)
    return _enArMap[lower];
  }

  /// Strips harakat (0x064B–0x0652) and unifies common letter variants so
  /// everyday spelling still matches dictionary keys.
  static String _normalizeAr(String w) {
    final sb = StringBuffer();
    for (final r in w.runes) {
      if (r >= 0x064B && r <= 0x0652) continue; // diacritics
      switch (r) {
        case 0x0623: // أ
        case 0x0625: // إ
        case 0x0622: // آ
          sb.write('\u0627'); // ا
          break;
        case 0x0649: // ى
          sb.write('\u064A'); // ي
          break;
        case 0x0629: // ة
          sb.write('\u0647'); // ه
          break;
        default:
          sb.writeCharCode(r);
      }
    }
    return sb.toString();
  }

  /// Splits text into words on whitespace and common (Latin + Arabic)
  /// punctuation.
  static final RegExp _wordSplitter = RegExp(
    r'''[\s\u060C\u061B\u061F\u06D4,.!?;:()\[\]{}«»"“”'’…/\\\-–—]+''',
  );

  /// Reverse index (English lowercase -> Arabic key), built lazily.
  static Map<String, String>? _enAr;
  static Map<String, String> get _enArMap {
    final cached = _enAr;
    if (cached != null) return cached;
    final built = <String, String>{};
    _arEn.forEach((k, v) => built.putIfAbsent(v.toLowerCase(), () => k));
    _enAr = built;
    return built;
  }

  /// Normalized-key index (diacritics/hamza variants removed), built lazily.
  static Map<String, String>? _arEnNorm;
  static Map<String, String> get _arEnNormalized {
    final cached = _arEnNorm;
    if (cached != null) return cached;
    final built = <String, String>{};
    _arEn.forEach((k, v) => built.putIfAbsent(_normalizeAr(k), () => v));
    _arEnNorm = built;
    return built;
  }

  /// English function words with no standalone Arabic equivalent. Empty
  /// translations are dropped from the output but still count as "known".
  static const Map<String, String> _enArExtra = {
    'the': '',
    'a': '',
    'an': '',
    'is': '',
    'are': '',
    'was': '',
    'were': '',
    'am': '',
    'do': '',
    'does': '',
    'did': '',
    'of': '',
    'my': 'لي',
    'your': 'لك',
    'his': 'له',
    'her': 'لها',
    'our': 'لنا',
    'their': 'لهم',
  };

  /// Offline AR→EN dictionary (~400 single-word pairs). Keys are base forms;
  /// lookups are normalized (diacritics stripped, hamza unified, optional
  /// leading "ال" removed) so spelling variants still match.
  static const Map<String, String> _arEn = {
    // ---- function words, questions, politeness ----
    'ما': 'what',
    'من': 'who',
    'اين': 'where',
    'متى': 'when',
    'كيف': 'how',
    'لماذا': 'why',
    'كم': 'how much',
    'اي': 'which',
    'الذي': 'that',
    'و': 'and',
    'او': 'or',
    'في': 'in',
    'على': 'on',
    'الى': 'to',
    'مع': 'with',
    'عن': 'about',
    'عند': 'at',
    'بدون': 'without',
    'بين': 'between',
    'قبل': 'before',
    'بعد': 'after',
    'فوق': 'above',
    'تحت': 'under',
    'امام': 'front',
    'خلف': 'behind',
    'داخل': 'inside',
    'خارج': 'outside',
    'هذا': 'this',
    'هذه': 'this',
    'ذلك': 'that',
    'تلك': 'that',
    'هنا': 'here',
    'هناك': 'there',
    'كل': 'every',
    'بعض': 'some',
    'ليس': 'not',
    'هو': 'he',
    'هي': 'she',
    'هم': 'they',
    'انا': 'I',
    'انت': 'you',
    'نحن': 'we',
    'لدي': 'have',
    'يوجد': 'exists',
    'لكن': 'but',
    'كذلك': 'also',
    'ايضا': 'also',
    'جدا': 'very',
    'فقط': 'only',
    'ربما': 'maybe',
    'طبعا': 'of course',
    'حسنا': 'okay',
    'دائما': 'always',
    'ابدا': 'never',
    'احيانا': 'sometimes',
    'غالبا': 'often',
    'الان': 'now',
    'لاحقا': 'later',
    'مبكرا': 'early',
    'متاخر': 'late',
    'نعم': 'yes',
    'لا': 'no',
    'مرحبا': 'hello',
    'اهلا': 'hi',
    'شكرا': 'thanks',
    'عفوا': 'pardon',
    'اسف': 'sorry',
    'وداعا': 'goodbye',
    'سلام': 'peace',
    'رجاء': 'please',

    // ---- time ----
    'وقت': 'time',
    'ساعة': 'hour',
    'دقيقة': 'minute',
    'ثانية': 'second',
    'يوم': 'day',
    'اسبوع': 'week',
    'شهر': 'month',
    'سنة': 'year',
    'عام': 'year',
    'اليوم': 'today',
    'غدا': 'tomorrow',
    'امس': 'yesterday',
    'صباح': 'morning',
    'مساء': 'evening',
    'ليل': 'night',
    'ليلة': 'night',
    'نهار': 'daytime',
    'فجر': 'dawn',
    'غروب': 'sunset',

    // ---- numbers ----
    'صفر': 'zero',
    'واحد': 'one',
    'اثنان': 'two',
    'ثلاثة': 'three',
    'اربعة': 'four',
    'خمسة': 'five',
    'ستة': 'six',
    'سبعة': 'seven',
    'ثمانية': 'eight',
    'تسعة': 'nine',
    'عشرة': 'ten',
    'عشرون': 'twenty',
    'مئة': 'hundred',
    'مائة': 'hundred',
    'الف': 'thousand',
    'نصف': 'half',
    'اول': 'first',
    'اخير': 'last',

    // ---- days ----
    'الاثنين': 'Monday',
    'الثلاثاء': 'Tuesday',
    'الاربعاء': 'Wednesday',
    'الخميس': 'Thursday',
    'الجمعة': 'Friday',
    'السبت': 'Saturday',
    'الاحد': 'Sunday',

    // ---- months ----
    'يناير': 'January',
    'فبراير': 'February',
    'مارس': 'March',
    'ابريل': 'April',
    'مايو': 'May',
    'يونيو': 'June',
    'يوليو': 'July',
    'اغسطس': 'August',
    'سبتمبر': 'September',
    'اكتوبر': 'October',
    'نوفمبر': 'November',
    'ديسمبر': 'December',

    // ---- people & family ----
    'رجل': 'man',
    'امراة': 'woman',
    'طفل': 'child',
    'اطفال': 'children',
    'صبي': 'boy',
    'بنت': 'girl',
    'ابن': 'son',
    'اب': 'father',
    'ام': 'mother',
    'اخ': 'brother',
    'اخت': 'sister',
    'جد': 'grandfather',
    'جدة': 'grandmother',
    'عم': 'uncle',
    'عمة': 'aunt',
    'خالة': 'aunt',
    'عائلة': 'family',
    'صديق': 'friend',
    'صديقة': 'friend',
    'جار': 'neighbor',
    'ضيف': 'guest',
    'شريك': 'partner',
    'زوج': 'husband',
    'زوجة': 'wife',
    'طبيب': 'doctor',
    'مهندس': 'engineer',
    'معلم': 'teacher',
    'طالب': 'student',
    'مدير': 'manager',
    'عامل': 'worker',
    'مزارع': 'farmer',
    'شرطي': 'policeman',
    'سائق': 'driver',
    'خبير': 'expert',
    'شخص': 'person',
    'ناس': 'people',

    // ---- adjectives ----
    'مهم': 'important',
    'عاجل': 'urgent',
    'كبير': 'big',
    'صغير': 'small',
    'جديد': 'new',
    'قديم': 'old',
    'جيد': 'good',
    'سيء': 'bad',
    'جميل': 'beautiful',
    'قبيح': 'ugly',
    'سريع': 'fast',
    'بطيء': 'slow',
    'سهل': 'easy',
    'صعب': 'hard',
    'طويل': 'long',
    'قصير': 'short',
    'عالي': 'high',
    'منخفض': 'low',
    'قوي': 'strong',
    'ضعيف': 'weak',
    'سعيد': 'happy',
    'حزين': 'sad',
    'غني': 'rich',
    'فقير': 'poor',
    'ساخن': 'hot',
    'بارد': 'cold',
    'دافئ': 'warm',
    'نظيف': 'clean',
    'قذر': 'dirty',
    'ممتاز': 'excellent',
    'رائع': 'wonderful',
    'صح': 'right',
    'خطا': 'wrong',
    'كثير': 'many',
    'قليل': 'few',
    'ممكن': 'possible',
    'مستحيل': 'impossible',
    'مشغول': 'busy',
    'حر': 'free',
    'مجاني': 'free',
    'غالي': 'expensive',
    'رخيص': 'cheap',

    // ---- colors ----
    'احمر': 'red',
    'اخضر': 'green',
    'ازرق': 'blue',
    'اصفر': 'yellow',
    'اسود': 'black',
    'ابيض': 'white',
    'رمادي': 'gray',
    'بني': 'brown',
    'برتقالي': 'orange',
    'بنفسجي': 'purple',
    'وردي': 'pink',
    'ذهبي': 'gold',
    'فضي': 'silver',

    // ---- note-taking ----
    'قلم': 'pen',
    'ورقة': 'paper',
    'كتاب': 'book',
    'دفتر': 'notebook',
    'كتابة': 'writing',
    'قراءة': 'reading',
    'ملاحظة': 'note',
    'ملاحظات': 'notes',
    'مسودة': 'draft',
    'ملخص': 'summary',
    'قائمة': 'list',
    'فكرة': 'idea',
    'سطر': 'line',
    'عنوان': 'title',
    'محتوى': 'content',

    // ---- tech ----
    'حاسوب': 'computer',
    'كمبيوتر': 'computer',
    'هاتف': 'phone',
    'جوال': 'mobile',
    'انترنت': 'internet',
    'ملف': 'file',
    'مجلد': 'folder',
    'شبكة': 'network',
    'موقع': 'site',
    'صفحة': 'page',
    'بريد': 'email',
    'رسالة': 'message',
    'صورة': 'image',
    'صوت': 'sound',
    'فيديو': 'video',
    'تطبيق': 'application',
    'شاشة': 'screen',
    'لوحة': 'board',
    'مفاتيح': 'keys',
    'فأرة': 'mouse',
    'طابعة': 'printer',
    'خيار': 'option',
    'اعدادات': 'settings',
    'زر': 'button',
    'بيانات': 'data',
    'كلمة': 'word',
    'كلمات': 'words',
    'لغة': 'language',
    'عربي': 'Arabic',
    'انجليزي': 'English',
    'ترجمة': 'translation',
    'قاموس': 'dictionary',
    'ذكاء': 'intelligence',
    'اصطناعي': 'artificial',
    'تحميل': 'download',
    'رفع': 'upload',
    'تحديث': 'update',
    'كاميرا': 'camera',
    'بطارية': 'battery',
    'سماعة': 'headphones',
    'ذاكرة': 'memory',
    'برمجة': 'programming',
    'كود': 'code',
    'مشكلة': 'problem',
    'حل': 'solution',
    'مشروع': 'project',
    'مهمة': 'task',
    'اجتماع': 'meeting',
    'بحث': 'search',
    'نسخ': 'copy',
    'لصق': 'paste',
    'حذف': 'delete',
    'حفظ': 'save',
    'فتح': 'open',
    'اغلاق': 'close',
    'ارسال': 'send',
    'معلومات': 'information',
    'رقم': 'number',
    'اسم': 'name',

    // ---- common verbs ----
    'ذهب': 'went',
    'جاء': 'came',
    'اخذ': 'took',
    'اعطى': 'gave',
    'قال': 'said',
    'سمع': 'heard',
    'شرب': 'drank',
    'نام': 'slept',
    'كتب': 'wrote',
    'قرا': 'read',
    'تعلم': 'learn',
    'درس': 'studied',
    'عمل': 'work',
    'لعب': 'played',
    'ركض': 'ran',
    'مشي': 'walked',
    'تحدث': 'spoke',
    'ساعد': 'helped',
    'اشترى': 'bought',
    'باع': 'sold',
    'اكل': 'food',

    // ---- home, places, nature ----
    'ماء': 'water',
    'طعام': 'food',
    'بيت': 'house',
    'منزل': 'home',
    'غرفة': 'room',
    'مطبخ': 'kitchen',
    'حمام': 'bathroom',
    'باب': 'door',
    'نافذة': 'window',
    'طاولة': 'table',
    'كرسي': 'chair',
    'سرير': 'bed',
    'مدرسة': 'school',
    'جامعة': 'university',
    'مكتبة': 'library',
    'مستشفى': 'hospital',
    'صيدلية': 'pharmacy',
    'سوق': 'market',
    'متجر': 'shop',
    'مطعم': 'restaurant',
    'فندق': 'hotel',
    'مطار': 'airport',
    'محطة': 'station',
    'سيارة': 'car',
    'قطار': 'train',
    'طائرة': 'plane',
    'دراجة': 'bicycle',
    'طريق': 'road',
    'شارع': 'street',
    'مدينة': 'city',
    'قرية': 'village',
    'بلد': 'country',
    'عالم': 'world',
    'شمس': 'sun',
    'قمر': 'moon',
    'نجم': 'star',
    'سماء': 'sky',
    'ارض': 'ground',
    'بحر': 'sea',
    'نهر': 'river',
    'جبل': 'mountain',
    'صحراء': 'desert',
    'شجرة': 'tree',
    'زهرة': 'flower',
    'حيوان': 'animal',
    'قطة': 'cat',
    'كلب': 'dog',
    'طائر': 'bird',
    'سمكة': 'fish',
    'حصان': 'horse',

    // ---- abstract ----
    'حب': 'love',
    'حياة': 'life',
    'موت': 'death',
    'حقيقة': 'truth',
    'كذب': 'lie',
    'امل': 'hope',
    'خوف': 'fear',
    'فرح': 'joy',
    'غضب': 'anger',
    'علم': 'science',
    'تاريخ': 'history',
    'حلم': 'dream',
    'هدف': 'goal',
    'خطة': 'plan',
    'سبب': 'reason',
    'نتيجة': 'result',
    'سؤال': 'question',
    'جواب': 'answer',
    'مثال': 'example',
    'قصة': 'story',
    'شعر': 'poetry',
    'اغنية': 'song',
    'موسيقى': 'music',
    'لعبة': 'game',
    'رياضة': 'sport',
    'صحة': 'health',
    'مرض': 'illness',
    'دواء': 'medicine',
    'نقود': 'money',
    'سعر': 'price',
    'تذكرة': 'ticket',
    'هدية': 'gift',
    'خريطة': 'map',
    'مفتاح': 'key',
    'تذكير': 'reminder',
    'خبر': 'news',
    'وظيفة': 'job',
    'عطلة': 'holiday',
    'سفر': 'travel',
    'رحلة': 'trip',
    'حقيبة': 'bag',
    'ملابس': 'clothes',
    'قميص': 'shirt',
    'حذاء': 'shoes',
  };

  // ---------------------------------------------------------- orchestration

  /// Chain: online → offline → null. [target] defaults to the language the
  /// UI is NOT in ("auto follows UI": Arabic UI → English and vice versa).
  static Future<TranslateResult?> translate(String text,
      {String? target}) async {
    if (text.trim().isEmpty) return null;
    final tgt = (target == null || target == 'auto')
        ? (S.isAr ? 'en' : 'ar')
        : target;
    final online = await translateOnline(text, tgt);
    if (online != null) return online;
    return translateOffline(text, tgt);
  }

  /// Opens Google Translate in the browser with the text pre-filled.
  static Future<bool> openGoogleTranslate(String text, String target) {
    final url =
        'https://translate.google.com/?sl=auto&tl=$target&op=translate&text=${Uri.encodeComponent(text)}';
    return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  /// Opens a web search for [text] (PDF text-selection "Search the web").
  static Future<bool> openWebSearch(String text) {
    final url = 'https://www.google.com/search?q=${Uri.encodeComponent(text)}';
    return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  /// Copies [text] to the clipboard, then launches the configured AI chat
  /// (chatgpt.com / gemini.google.com / claude.ai) with the text as query.
  static Future<void> askAi(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.t('copiedToClipboard'))),
      );
    }
    final service = SettingsController.I.settings.aiService;
    final q = Uri.encodeComponent(text);
    final Uri uri;
    if (service == 'gemini') {
      uri = Uri.parse('https://gemini.google.com/app?q=$q');
    } else if (service == 'claude') {
      uri = Uri.parse('https://claude.ai/new?q=$q');
    } else {
      uri = Uri.parse('https://chatgpt.com/?q=$q');
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('error'))),
        );
      }
    }
  }
}
