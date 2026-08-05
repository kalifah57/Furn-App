import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../domain/handoff_session.dart';
import '../domain/room_scanner_service.dart';

/// المسح عبر **جهاز ثانٍ**، منفَّذًا كتطبيق آخر لعقد [RoomScannerService].
///
/// هذه هي النقطة المعمارية كلها: المتصفّح لا يملك LiDAR، لكن [SandboxController]
/// يظلّ ينادي `scan()` ولا يعرف أن الجواب جاء من جوال في الغرفة المجاورة. لا
/// تتغيّر الحالة ولا الشاشة ولا المحرّك — يتبدّل المزوّد فقط.
///
/// الواجهة تعرض الرمز والمراحل عبر [sessions] بينما ينتظر [scan] النتيجة، فلا
/// نُحمّل العقد القائم مسؤولية التقدّم.
class HandoffRoomScannerService implements RoomScannerService {
  HandoffRoomScannerService({
    required this.channel,
    this.ttl = const Duration(minutes: 10),
  });

  final HandoffChannel channel;

  /// عمر الجلسة. قصير عمدًا: المعرّف مفتاح قراءة وكتابة، ويُعرض على شاشة في
  /// مكان عام.
  final Duration ttl;

  /// آخر جلسة نشطة — تتابعها الواجهة لعرض الرمز والمراحل.
  Stream<HandoffSession> get sessions => _sessions.stream;
  final _sessions = _Relay<HandoffSession>();

  /// المسح بالتسليم متاح على أي جهاز — لا يشترط LiDAR هنا، بل في الجوال.
  @override
  Future<bool> isSupported() async => true;

  @override
  Future<Result<ScannedRoom>> scan() async {
    final opened = await channel.open(ttl: ttl);
    final session = opened.valueOrNull;
    if (session == null) {
      return Err(opened.failureOrNull ?? const UnknownFailure());
    }

    _sessions.add(session);

    try {
      await for (final update in channel.watch(session.id)) {
        _sessions.add(update);
        if (!update.isTerminal) continue;

        return switch (update.status) {
          HandoffStatus.completed => update.room == null
              // اكتملت بلا قياسات: خطأ صريح خير من غرفة صفرية تصل إلى المحرّك.
              ? const Err(ValidationFailure('انتهى المسح دون قياسات.'))
              : Ok(update.room!),
          HandoffStatus.failed =>
            Err(UnknownFailure(update.failureMessage ?? 'تعذّر المسح على الجوال.')),
          HandoffStatus.expired =>
            const Err(ValidationFailure('انتهت مهلة الاقتران. أعد المحاولة.')),
          HandoffStatus.cancelled => const Err(ValidationFailure('أُلغي المسح.')),
          _ => const Err(UnknownFailure()),
        };
      }
      // انتهى البثّ دون حالة نهائية — الجلسة أُغلقت من تحتنا.
      return const Err(ValidationFailure('انقطعت جلسة المسح.'));
    } finally {
      await channel.close(session.id);
    }
  }
}

/// بثّ بسيط يحتفظ بآخر قيمة، فلا تفوت الواجهةَ الحالةُ الراهنة عند الاشتراك.
class _Relay<T> {
  final _listeners = <void Function(T)>[];
  T? _last;

  Stream<T> get stream {
    late final Stream<T> out;
    out = Stream<T>.multi((controller) {
      final last = _last;
      if (last != null) controller.add(last);
      void listener(T value) => controller.add(value);
      _listeners.add(listener);
      controller.onCancel = () => _listeners.remove(listener);
    });
    return out;
  }

  void add(T value) {
    _last = value;
    for (final l in [..._listeners]) {
      l(value);
    }
  }
}
