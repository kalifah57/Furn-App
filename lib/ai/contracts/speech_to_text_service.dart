import '../../core/errors/result.dart';

/// تجريد تحويل الصوت إلى نص (architecture.md — AI Layer).
/// الـ MVP يستخدم تنفيذًا وهميًا؛ يُستبدل بمزوّد حقيقي لاحقًا عبر provider override.
abstract interface class SpeechToTextService {
  /// [audioRef] مرجع/مسار وهمي للتسجيل في الـ MVP.
  Future<Result<String>> transcribe(String audioRef);
}
