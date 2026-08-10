import 'package:equatable/equatable.dart';

/// نموذج الأخطاء الموحّد (engineering_standards.md).
/// كل الأخطاء تمر عبر هذا النموذج مع تمييز نوعها.
sealed class Failure extends Equatable {
  const Failure(this.message, {this.cause});

  /// رسالة عربية صديقة للمستخدم.
  final String message;

  /// السبب التقني (يُسجَّل داخليًا فقط، لا يُعرض).
  final Object? cause;

  @override
  List<Object?> get props => [message, cause];
}

class NetworkFailure extends Failure {
  const NetworkFailure([String message = 'تعذّر الاتصال بالشبكة.', Object? cause])
      : super(message, cause: cause);
}

class ValidationFailure extends Failure {
  const ValidationFailure(String message, [Object? cause])
      : super(message, cause: cause);
}

class AiParsingFailure extends Failure {
  const AiParsingFailure([String message = 'تعذّر فهم مخرجات التحليل.', Object? cause])
      : super(message, cause: cause);
}

class NotFoundFailure extends Failure {
  const NotFoundFailure([String message = 'العنصر غير موجود.', Object? cause])
      : super(message, cause: cause);
}

class UnknownFailure extends Failure {
  const UnknownFailure([String message = 'حدث خطأ غير متوقع.', Object? cause])
      : super(message, cause: cause);
}
