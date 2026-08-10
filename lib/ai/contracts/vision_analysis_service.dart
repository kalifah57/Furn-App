import '../../core/errors/result.dart';

/// تجريد تحليل صور الغرفة إلى إشارات منظمة (architecture.md — AI Layer).
/// يُنتج ملخّصًا نصيًا يُحقن لاحقًا في الـ prompt ([Vision Signals]).
abstract interface class VisionAnalysisService {
  /// [imageRefs] مراجع/مسارات وهمية للصور في الـ MVP.
  Future<Result<String>> analyze(List<String> imageRefs);
}
