import '../../../core/errors/result.dart';
import 'room_scanner_service.dart';

/// **تسليم المسح بين جهازين** — المتصفّح يعرض رمزًا، والجوال يمسح الغرفة ويُعيد
/// القياسات إلى نفس الجلسة.
///
/// نمذجة نقيّة بلا Flutter وبلا شبكة: [HandoffChannel] هو المنفذ الوحيد الذي
/// يعرف كيف تنتقل الجلسة بين الجهازين، وكل ما عداه قابل للاختبار بمعزل.

/// مراحل الجلسة — تُعرض للمستخدم كما هي، فلا يبقى أمام دوّارة صامتة دقيقتين.
enum HandoffStatus {
  /// أُنشئت الجلسة وتُعرض على الشاشة، بانتظار الجوال.
  pending,

  /// فتح الجوال الرابط — الاقتران تمّ.
  linked,

  /// المسح جارٍ على الجوال.
  scanning,

  /// انتهى المسح ويُعالَج (RoomPlan تُخرج الغرفة بعد التوقّف).
  processing,

  /// وصلت القياسات — الجلسة انتهت بنجاح.
  completed,

  /// فشل على الجوال (رفض الإذن، جهاز غير مدعوم، خطأ مسح).
  failed,

  /// انتهت المهلة قبل أن يصل شيء.
  expired,

  /// ألغى المستخدم من أي طرف.
  cancelled,
}

/// حالة جلسة تسليم واحدة. كائن قيمة ثابت: كل انتقال يُنتج نسخة جديدة.
class HandoffSession {
  const HandoffSession({
    required this.id,
    required this.createdAt,
    required this.expiresAt,
    this.status = HandoffStatus.pending,
    this.room,
    this.meshUrl,
    this.failureMessage,
  });

  /// معرّف الجلسة — **يُعامل كسرّ**: من يعرفه يكتب في الجلسة ويقرأ أبعاد منزل
  /// شخص آخر. يجب أن يكون عشوائيًا لا متسلسلًا، وقصير العمر.
  final String id;

  final DateTime createdAt;
  final DateTime expiresAt;
  final HandoffStatus status;

  /// القياسات — تصل أولًا وهي كل ما يحتاجه المحرّك (بضع مئات بايت).
  final ScannedRoom? room;

  /// شبكة الغرفة — تصل **لاحقًا** وقد لا تصل. لا ينتظرها أحد.
  final String? meshUrl;

  final String? failureMessage;

  /// رمز اقتران قصير يُكتب باليد حين يتعذّر مسح الرمز (أو قبل إضافة حزمة QR).
  ///
  /// مشتقّ من [id] بشكل حتمي، وبأحرف بلا التباس بصري (لا O/0 ولا I/1).
  String get pairingCode {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    final buffer = StringBuffer();
    for (var i = 0; i < 6; i++) {
      buffer.write(alphabet[hash % alphabet.length]);
      hash ~/= alphabet.length;
    }
    return buffer.toString();
  }

  bool get isTerminal => switch (status) {
        HandoffStatus.completed ||
        HandoffStatus.failed ||
        HandoffStatus.expired ||
        HandoffStatus.cancelled =>
          true,
        _ => false,
      };

  /// هل بدأ الجوال فعليًا؟ (تُستخدم لإخفاء الرمز بمجرّد الاقتران.)
  bool get isLinked => status != HandoffStatus.pending && !isTerminal;

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);

  Duration remainingAt(DateTime now) {
    final left = expiresAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  HandoffSession copyWith({
    HandoffStatus? status,
    ScannedRoom? room,
    String? meshUrl,
    String? failureMessage,
  }) =>
      HandoffSession(
        id: id,
        createdAt: createdAt,
        expiresAt: expiresAt,
        status: status ?? this.status,
        room: room ?? this.room,
        meshUrl: meshUrl ?? this.meshUrl,
        failureMessage: failureMessage ?? this.failureMessage,
      );
}

/// **المنفذ الوحيد الذي يعرف الشبكة.** التنفيذ الوهمي، وتنفيذ التبويبات على
/// الويب، وتنفيذ Firebase لاحقًا — كلها خلف هذا العقد، ولا يتغيّر شيء فوقه.
abstract interface class HandoffChannel {
  /// ينشئ جلسة جديدة (جانب المتصفّح).
  Future<Result<HandoffSession>> open({Duration ttl});

  /// يتابع تحوّلات جلسة. يُغلق البثّ عند الوصول لحالة نهائية.
  Stream<HandoffSession> watch(String sessionId);

  /// ينشر تحوّلًا (جانب الجوال، أو المحاكاة).
  ///
  /// **مرحلتان مقصودتان:** تُنشر القياسات فور جاهزيتها لتفتح المشهد فورًا، ثم
  /// تُنشر الشبكة لاحقًا في تحوّل منفصل — فلا يتوقّف المستخدم على رفع ميغابايتات.
  Future<Result<void>> publish(HandoffSession session);

  /// يُنهي الجلسة ويحرّر مواردها.
  Future<void> close(String sessionId);
}
