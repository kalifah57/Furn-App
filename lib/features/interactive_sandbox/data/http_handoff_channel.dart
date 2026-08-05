import 'dart:async';
import 'dart:convert';

import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../domain/handoff_session.dart';
import '../domain/room_scanner_service.dart';

/// جلب نصّ من رابط — `null` يعني 404 (لا جلسة بعد).
typedef HandoffGet = Future<String?> Function(Uri url);

/// إرسال نصّ إلى رابط.
typedef HandoffPost = Future<void> Function(Uri url, String body);

/// [HandoffChannel] فوق خادم الالتقاء المحلّي (`tools/handoff_server.py`).
///
/// المتصفّح يستطلع `GET /handoff/<CODE>` كل [pollInterval]. الاستطلاع — لا
/// WebSocket — مقصود: المسح يستغرق دقائق لا مللي ثانية، وثانية تأخير غير محسوسة،
/// مقابل تنفيذ يعمل خلف أي شبكة ولا يحتاج إعادة اتصال.
///
/// النقل مُحقَن ([get]/[post]) كي يبقى هذا الصنف نقيًّا: `dart:html` على الويب
/// و`dart:io` على الـ VM يبقيان في ملفَّين صغيرين خلف استيراد شرطي.
class HttpHandoffChannel implements HandoffChannel {
  HttpHandoffChannel({
    required this.baseUrl,
    required this.get,
    required this.post,
    required this.newSessionId,
    this.pollInterval = const Duration(seconds: 1),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// عنوان الماك كما يراه المتصفّح، مثل `http://192.168.1.20:8080`.
  final Uri baseUrl;
  final HandoffGet get;
  final HandoffPost post;
  final String Function() newSessionId;
  final Duration pollInterval;
  final DateTime Function() _now;

  Uri _endpoint(String code) => baseUrl.replace(path: '/handoff/$code');

  @override
  Future<Result<HandoffSession>> open({Duration ttl = const Duration(minutes: 10)}) async {
    final createdAt = _now();
    final session = HandoffSession(
      id: newSessionId(),
      createdAt: createdAt,
      expiresAt: createdAt.add(ttl),
    );
    // لا نكتب شيئًا على الخادم عند الفتح: الجلسة تُنشأ بأول كتابة من الجوال،
    // فلا تتراكم جلسات فارغة لكل ضغطة زر.
    return Ok(session);
  }

  @override
  Stream<HandoffSession> watch(String sessionId) async* {
    throw UnsupportedError(
        'watch(sessionId) غير مستخدم هنا؛ استخدم watchSession لأن الاستطلاع '
        'يحتاج رمز الاقتران لا المعرّف.');
  }

  /// يستطلع الجلسة حتى تصل حالة نهائية أو تنتهي المهلة.
  ///
  /// نمرّر الجلسة كاملة (لا المعرّف) لأن العنوان على الخادم هو **رمز الاقتران**
  /// المشتقّ منها — وهو ما يكتبه المستخدم على الجوال.
  Stream<HandoffSession> watchSession(HandoffSession session) async* {
    var current = session;
    yield current;

    while (true) {
      if (current.isExpiredAt(_now())) {
        yield current.copyWith(status: HandoffStatus.expired);
        return;
      }
      await Future<void>.delayed(pollInterval);

      String? body;
      try {
        body = await get(_endpoint(session.pairingCode));
      } catch (_) {
        // انقطاع شبكة عابر: نواصل الاستطلاع حتى المهلة بدل إسقاط الجلسة.
        continue;
      }
      if (body == null || body.isEmpty) continue; // لم يكتب الجوال بعد

      final parsed = _parse(current, body);
      if (parsed == null) continue;
      current = parsed;
      yield current;
      if (current.isTerminal) return;
    }
  }

  @override
  Future<Result<void>> publish(HandoffSession session) async {
    try {
      await post(_endpoint(session.pairingCode), jsonEncode(_encode(session)));
      return const Ok(null);
    } catch (e) {
      return Err(NetworkFailure('تعذّر إرسال حالة المسح.', e));
    }
  }

  @override
  Future<void> close(String sessionId) async {}

  Map<String, Object?> _encode(HandoffSession s) => {
        'status': s.status.name,
        if (s.failureMessage != null) 'failure': s.failureMessage,
        if (s.meshUrl != null) 'mesh_url': s.meshUrl,
        if (s.room != null)
          'room': {
            'width_cm': s.room!.widthCm,
            'length_cm': s.room!.lengthCm,
            'ceiling_cm': s.room!.ceilingCm,
            'confidence': s.room!.confidence,
          },
      };

  /// يقرأ ما كتبه الجوال. يعيد `null` إن كانت الحمولة غير مفهومة، فيواصل
  /// الاستطلاع بدل إسقاط الجلسة على رسالة تالفة واحدة.
  HandoffSession? _parse(HandoffSession current, String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final status = HandoffStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => current.status,
      );

      ScannedRoom? room;
      final r = json['room'];
      if (r is Map) {
        final w = (r['width_cm'] as num?)?.toDouble() ?? 0;
        final l = (r['length_cm'] as num?)?.toDouble() ?? 0;
        // أبعاد صفرية لا تصل إلى المحرّك: تُعامل الجلسة كفاشلة بسبب واضح.
        if (w <= 0 || l <= 0) {
          return current.copyWith(
            status: HandoffStatus.failed,
            failureMessage: 'وصلت قياسات غير صالحة من الجوال.',
          );
        }
        final c = (r['ceiling_cm'] as num?)?.toDouble() ?? 0;
        room = ScannedRoom(
          widthCm: w,
          lengthCm: l,
          ceilingCm: c > 0 ? c : 280,
          confidence: (r['confidence'] as num?)?.toDouble() ?? 1.0,
        );
      }

      return current.copyWith(
        status: status,
        room: room,
        meshUrl: json['mesh_url'] as String?,
        failureMessage: json['failure'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
