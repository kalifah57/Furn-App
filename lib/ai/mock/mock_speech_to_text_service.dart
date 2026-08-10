import '../../core/errors/result.dart';
import '../contracts/speech_to_text_service.dart';

/// تنفيذ وهمي لتحويل الصوت إلى نص (mock-first — ADR-0001 §6/§7).
/// يعيد نصًا تمثيليًا مطابقًا لمثال PRD؛ يُستبدل بمزوّد حقيقي لاحقًا.
class MockSpeechToTextService implements SpeechToTextService {
  const MockSpeechToTextService();

  @override
  Future<Result<String>> transcribe(String audioRef) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return const Ok(
      'الغرفة 4 في 6، أبي سرير وكنب صغير، وإذا الميزانية تسمح أضيف سجادة، '
      'وميزانيتي 1800 ريال.',
    );
  }
}
