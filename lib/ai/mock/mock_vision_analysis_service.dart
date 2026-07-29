import '../../core/errors/result.dart';
import '../contracts/vision_analysis_service.dart';

/// تنفيذ وهمي لتحليل صور الغرفة (mock-first).
/// يعيد ملخّص إشارات تمثيليًا يُحقن في [Vision Signals] بالـ prompt.
class MockVisionAnalysisService implements VisionAnalysisService {
  const MockVisionAnalysisService();

  @override
  Future<Result<String>> analyze(List<String> imageRefs) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (imageRefs.isEmpty) return const Ok('');
    return const Ok(
      'غرفة مستطيلة بإضاءة طبيعية جيدة، جدران فاتحة، ونافذة واحدة على الجدار الأطول.',
    );
  }
}
