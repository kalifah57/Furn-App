import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/consent_store.dart';

/// مخزن الموافقة — يُستبدَل في الاختبارات بمخزن في الذاكرة.
final consentStoreProvider =
    Provider<ConsentStore>((ref) => const ConsentStore());

/// حالة الموافقة على القياس: `null` لم يُسأل، `true` وافق، `false` رفض.
///
/// تُقرأ عند الإقلاع من التخزين، فيبقى اختيار المستخدم بين الجلسات.
class ConsentController extends Notifier<bool?> {
  @override
  bool? build() => ref.read(consentStoreProvider).load();

  void decide({required bool granted}) {
    ref.read(consentStoreProvider).save(granted: granted);
    state = granted;
  }
}

final consentControllerProvider =
    NotifierProvider<ConsentController, bool?>(ConsentController.new);
