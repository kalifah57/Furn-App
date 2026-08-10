import 'dart:async';
import 'dart:convert';

import 'analytics.dart';

/// دالة الإرسال — تُحقن كي يبقى هذا الصنف قابلًا للاختبار بلا شبكة، وكي يبقى
/// `dart:html` / `dart:io` خلف استيراد شرطي في طبقة الحقن.
typedef AnalyticsPost = Future<void> Function(Uri url, String body);

/// **sink القياس الحقيقي** — يُجمّع الأحداث ويرسلها دفعات إلى نقطة نهاية.
///
/// قبل هذا الصنف كانت الأحداث الثلاثة عشر تُعرَّف ثم تُطبع في الـ console وتضيع:
/// أي أن **activation — المقياس الوحيد الذي يملكه VP-1 — لم يكن قابلًا للرؤية**.
///
/// ثلاثة قرارات تشكّل هذا التنفيذ:
///
/// 1. **الموافقة تُفحص قبل التخزين لا قبل الإرسال.** حدث بلا موافقة لا يدخل
///    الذاكرة أصلًا، فلا يوجد ما قد يُرسل لاحقًا بالخطأ (نظام حماية البيانات).
/// 2. **الفشل صامت ومحدود.** القياس يلاحظ حلقة الثقة ولا يعطّلها؛ سقوط الشبكة
///    يجب ألّا يُسقط شاشة المستخدم. لذا لا استثناءات تخرج من [track].
/// 3. **المخزن محدود.** بلا سقف، جلسة طويلة بلا شبكة تكبر بلا حدّ. عند الامتلاء
///    نُسقط **الأقدم** — الأحداث الحديثة أقرب لما يحدث للمستخدم الآن.
class HttpAnalytics implements Analytics {
  HttpAnalytics({
    required this.endpoint,
    required this.post,
    required this.sessionId,
    this.consent = true,
    this.batchSize = 20,
    this.flushInterval = const Duration(seconds: 15),
    this.maxBuffer = 200,
  });

  final Uri endpoint;
  final AnalyticsPost post;

  /// معرّف جلسة مجهول — بلا أي معلومة شخصية.
  final String sessionId;

  /// مفتاح الإيقاف. `false` ⇒ لا يُسجَّل ولا يُخزَّن أي حدث.
  final bool consent;

  final int batchSize;
  final Duration flushInterval;
  final int maxBuffer;

  final List<Map<String, Object?>> _buffer = [];
  Timer? _timer;
  bool _sending = false;

  /// عدد الأحداث المنتظرة — للاختبار والتشخيص.
  int get pending => _buffer.length;

  @override
  void track(AnalyticsEvent event) {
    if (!consent) return;

    _buffer.add({
      'name': event.name,
      'session_id': sessionId,
      // الوقت يُسجَّل عند الالتقاط لا عند الإرسال: دفعة تأخّرت عشر دقائق يجب
      // ألّا تبدو كأنها وقعت كلها في لحظة الإرسال.
      'at': DateTime.now().toUtc().toIso8601String(),
      'params': event.params,
    });

    if (_buffer.length > maxBuffer) {
      _buffer.removeRange(0, _buffer.length - maxBuffer);
    }
    if (_buffer.length >= batchSize) {
      unawaited(flush());
    } else {
      _scheduleFlush();
    }
  }

  void _scheduleFlush() {
    _timer ??= Timer(flushInterval, () {
      _timer = null;
      unawaited(flush());
    });
  }

  /// يرسل ما تجمّع. آمن للاستدعاء في أي وقت؛ لا يرمي أبدًا.
  Future<void> flush() async {
    if (_sending || _buffer.isEmpty) return;
    _sending = true;
    _timer?.cancel();
    _timer = null;

    // ننتزع الدفعة قبل الإرسال حتى لا يتضخّم المخزن أثناء انتظار الشبكة.
    final batch = List<Map<String, Object?>>.from(_buffer);
    _buffer.clear();

    try {
      await post(endpoint, jsonEncode({'events': batch}));
    } catch (_) {
      // الشبكة سقطت: نُعيد الدفعة إلى مقدّمة المخزن لتُحاوَل لاحقًا، مع احترام
      // السقف — القياس لا يجوز أن يستهلك ذاكرة المستخدم بلا حدّ.
      _buffer.insertAll(0, batch);
      if (_buffer.length > maxBuffer) {
        _buffer.removeRange(0, _buffer.length - maxBuffer);
      }
      _scheduleFlush();
    } finally {
      _sending = false;
    }
  }

  /// يُستدعى عند إغلاق التطبيق — آخر فرصة لإرسال ما تبقّى.
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await flush();
  }
}

/// يوزّع كل حدث على أكثر من sink.
///
/// يسمح بإبقاء [DebugAnalytics] أثناء التطوير مع الإرسال الحقيقي في آنٍ واحد،
/// دون أن تعرف نقاط النداء شيئًا عن ذلك.
class FanOutAnalytics implements Analytics {
  const FanOutAnalytics(this.sinks);
  final List<Analytics> sinks;

  @override
  void track(AnalyticsEvent event) {
    for (final s in sinks) {
      // sink معطّل يجب ألّا يمنع البقية من التسجيل.
      try {
        s.track(event);
      } catch (_) {}
    }
  }
}
