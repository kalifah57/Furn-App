import 'dart:async';

import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../domain/handoff_session.dart';
import '../domain/room_scanner_service.dart';

/// تنفيذ [HandoffChannel] في الذاكرة — يحاكي الجهاز الثاني بلا خادم.
///
/// يمارس **آلة الحالة كاملة** (اقتران، مسح، معالجة، مهلة، إلغاء، فشل) وهي الجزء
/// الذي تختبئ فيه العيوب؛ الشبكة نفسها تفصيل يُبدَّل خلف نفس العقد. لذلك يمكن
/// عرض التجربة على العميل وكتابة اختباراتها قبل شراء أي خلفية.
///
/// الوقت مُحقَن عبر [now] كي لا تعتمد اختبارات المهلة على ساعة الجهاز.
class InMemoryHandoffChannel implements HandoffChannel {
  InMemoryHandoffChannel({
    required this.newSessionId,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// مصدر المعرّفات — يُحقن ليكون عشوائيًا في الإنتاج وثابتًا في الاختبار.
  final String Function() newSessionId;
  final DateTime Function() _now;

  final _sessions = <String, HandoffSession>{};
  final _controllers = <String, StreamController<HandoffSession>>{};

  @override
  Future<Result<HandoffSession>> open({Duration ttl = const Duration(minutes: 10)}) async {
    final createdAt = _now();
    final session = HandoffSession(
      id: newSessionId(),
      createdAt: createdAt,
      expiresAt: createdAt.add(ttl),
    );
    _sessions[session.id] = session;
    _controllers[session.id] = StreamController<HandoffSession>.broadcast();
    return Ok(session);
  }

  @override
  Stream<HandoffSession> watch(String sessionId) {
    final controller = _controllers[sessionId];
    if (controller == null) {
      return Stream.error(
          const NotFoundFailure('جلسة المسح غير موجودة أو انتهت.'));
    }
    return _watch(sessionId, controller);
  }

  /// الحالة الحالية أولًا ثم التحوّلات — كي لا يفوت المشترك المتأخّر ما حدث قبل
  /// اشتراكه (تبويب أُعيد تحميله أثناء المسح مثلًا).
  Stream<HandoffSession> _watch(
      String sessionId, StreamController<HandoffSession> controller) async* {
    final current = _sessions[sessionId];
    if (current != null) yield current;
    yield* controller.stream;
  }

  @override
  Future<Result<void>> publish(HandoffSession session) async {
    final known = _sessions[session.id];
    if (known == null) {
      return const Err(NotFoundFailure('جلسة المسح غير موجودة أو انتهت.'));
    }
    // الجلسة المنتهية لا تُستأنف: تحوّل متأخّر من جوال بطيء يجب أن يُرفض، لا أن
    // يُعيد فتح مشهد أغلقه المستخدم.
    if (known.isTerminal) {
      return const Err(ValidationFailure('انتهت جلسة المسح.'));
    }
    if (known.isExpiredAt(_now())) {
      _emit(known.copyWith(status: HandoffStatus.expired));
      return const Err(ValidationFailure('انتهت مهلة جلسة المسح.'));
    }
    _emit(session);
    return const Ok(null);
  }

  @override
  Future<void> close(String sessionId) async {
    _sessions.remove(sessionId);
    await _controllers.remove(sessionId)?.close();
  }

  void _emit(HandoffSession session) {
    _sessions[session.id] = session;
    _controllers[session.id]?.add(session);
    if (session.isTerminal) {
      // إغلاق البثّ بعد الحالة النهائية يُنهي انتظار الطرف الآخر بدل تعليقه.
      _controllers[session.id]?.close();
      _controllers.remove(session.id);
    }
  }

  // ---- محاكاة الجوال (للعرض والاختبار فقط) --------------------------------

  /// يمثّل الجوال وهو يمرّ بالمراحل حتى تسليم القياسات.
  ///
  /// الخطوات منفصلة عمدًا: هكذا تُختبر كل مرحلة، وتُعرض للمستخدم كما تحدث.
  Future<void> simulatePhone(
    String sessionId, {
    required HandoffStatus status,
    ScannedRoom? room,
    String? meshUrl,
    String? failureMessage,
  }) async {
    final current = _sessions[sessionId];
    if (current == null) return;
    await publish(current.copyWith(
      status: status,
      room: room,
      meshUrl: meshUrl,
      failureMessage: failureMessage,
    ));
  }

  /// يُنهي الجلسة بالمهلة — يستدعيه المؤقّت في الواجهة.
  Future<void> expire(String sessionId) async {
    final current = _sessions[sessionId];
    if (current == null || current.isTerminal) return;
    _emit(current.copyWith(status: HandoffStatus.expired));
  }
}
