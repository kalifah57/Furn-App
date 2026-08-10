import '../../../core/storage/key_value_store.dart';
import '../../../core/storage/store_types.dart';

/// موافقة المستخدم على القياس، محفوظة عبر إغلاق المتصفّح.
///
/// ثلاث حالات: `granted` / `denied` / **غائب** (لم يُسأل بعد). الغياب ليس موافقة:
/// لا يُجمَع أي حدث قبل اختيار صريح — نظام حماية البيانات الشخصية (PDPL). قبل
/// هذا كان `analyticsConsentProvider` مثبّتًا على `true`، أي جمعٌ بلا إذن.
class ConsentStore {
  const ConsentStore({this.read = storeRead, this.write = storeWrite});

  final StoreRead read;
  final StoreWrite write;

  static const key = 'furn.analytics_consent';

  /// `null` = لم يُسأل بعد. قيمة غير معروفة تُقرأ كـ`null` أيضًا — لا نخمّن موافقة.
  bool? load() {
    switch (read(key)) {
      case 'granted':
        return true;
      case 'denied':
        return false;
      default:
        return null;
    }
  }

  void save({required bool granted}) {
    try {
      write(key, granted ? 'granted' : 'denied');
    } catch (_) {
      // فشل التخزين لا يُسقط الشاشة؛ أسوأ الأحوال أن نسأل مجددًا لاحقًا.
    }
  }
}
