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
  const NetworkFailure([super.message = 'تعذّر الاتصال بالشبكة.', {super.cause}]);
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message, {super.cause});
}

class AiParsingFailure extends Failure {
  const AiParsingFailure(
      [super.message = 'تعذّر فهم مخرجات التحليل.', {super.cause}]);
}

class NotFoundFailure extends Failure {
  const NotFoundFailure([super.message = 'العنصر غير موجود.', {super.cause}]);
}

class UnknownFailure extends Failure {
  const UnknownFailure([super.message = 'حدث خطأ غير متوقع.', {super.cause}]);
}
