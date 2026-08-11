import 'package:flutter_riverpod/flutter_riverpod.dart';

/// من قال السطر. لا حالة قرار هنا — المحادثة **سجلٌّ للعرض**، والقرار كلّه في
/// المحرّك خلف `FurnishingFlowController`.
enum ChatAuthor { assistant, user }

class ChatMessage {
  const ChatMessage(this.author, this.text);
  final ChatAuthor author;
  final String text;
}

/// سجلّ المحادثة في صفحة المساعد.
///
/// يعيش في موفّر لا في `State` عمدًا: الهيكل الثلاثي قد يُعيد بناء صفحته حين
/// يتغيّر العنوان، ومحادثةٌ تختفي لأن المستخدم سحب إلى غرفته ثم عاد ليست محادثة.
class AssistantChat extends Notifier<List<ChatMessage>> {
  static const greeting =
      'صف غرفتك وميزانيتك بكلماتك، وأبني لك أوّل خطة تشكّلها حتى تثق بها.';

  @override
  List<ChatMessage> build() =>
      const [ChatMessage(ChatAuthor.assistant, greeting)];

  void user(String text) => _add(ChatAuthor.user, text);
  void assistant(String text) => _add(ChatAuthor.assistant, text);

  void _add(ChatAuthor author, String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    state = [...state, ChatMessage(author, t)];
  }
}

final assistantChatProvider =
    NotifierProvider<AssistantChat, List<ChatMessage>>(AssistantChat.new);
