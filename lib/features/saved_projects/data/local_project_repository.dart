import 'dart:convert';

import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/storage/key_value_store.dart';
import '../../../core/storage/store_types.dart';
import '../../../shared/models/furnishing_project.dart';
import '../domain/project_repository.dart';

/// المشاريع المحفوظة تنجو من إغلاق المتصفّح.
///
/// قبل هذا كان زرّ «احفظ المشروع» يعرض «تم الحفظ» ثم يمحو كل شيء عند أول تحديث
/// للصفحة. وعدٌ مكسور أسرع طريق لفقد ثقة المستخدم — وهي المنتج نفسه هنا.
///
/// نقرأ ونكتب القائمة كاملة في كل عملية: على مقياس الـ MVP (مشاريع معدودة) هذا
/// أبسط من فهرس، وأصعب في الإفساد.
class LocalProjectRepository implements ProjectRepository {
  LocalProjectRepository({
    this.read = storeRead,
    this.write = storeWrite,
    this.now = DateTime.now,
  });

  final StoreRead read;
  final StoreWrite write;
  final DateTime Function() now;

  static const key = 'furn.projects';
  static const version = 1;

  @override
  Future<Result<void>> save(FurnishingProject project) async {
    final store = _load();
    store[project.projectId] = project.copyWith(updatedAt: now());
    _persist(store);
    return const Ok(null);
  }

  @override
  Future<Result<List<FurnishingProject>>> listProjects() async {
    final list = _load().values.toList()
      ..sort((a, b) {
        final byTime = (b.updatedAt ?? DateTime(0))
            .compareTo(a.updatedAt ?? DateTime(0));
        // ترتيب كلّي: `List.sort` في Dart غير مستقرّ، فمشروعان بنفس الطابع
        // الزمني كانا سيتبادلان المواضع بين استدعاءين بلا سبب.
        return byTime != 0 ? byTime : a.projectId.compareTo(b.projectId);
      });
    return Ok(list);
  }

  @override
  Future<Result<FurnishingProject>> getById(String projectId) async {
    final p = _load()[projectId];
    return p == null ? const Err(NotFoundFailure('المشروع غير موجود.')) : Ok(p);
  }

  @override
  Future<Result<void>> delete(String projectId) async {
    final store = _load()..remove(projectId);
    _persist(store);
    return const Ok(null);
  }

  /// تخزين تالف أو من إصدار سابق ⇒ قائمة فارغة، لا استثناء: شاشة «المحفوظة»
  /// الفارغة مزعجة، وسقوط التطبيق عند الإقلاع قاتل.
  Map<String, FurnishingProject> _load() {
    final raw = read(key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['v'] != version) return {};
      final out = <String, FurnishingProject>{};
      for (final entry in (map['projects'] as List)) {
        if (entry is! Map) continue;
        final p = FurnishingProject.fromJson(entry.cast<String, dynamic>());
        // `fromJson` يعطي معرّفًا فارغًا للمدخل الناقص؛ إدخاله يعني أن مشاريع
        // تالفة متعدّدة تدهس بعضها تحت نفس المفتاح.
        if (p.projectId.isEmpty) continue;
        out[p.projectId] = p;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  void _persist(Map<String, FurnishingProject> store) {
    try {
      write(
        key,
        jsonEncode({
          'v': version,
          'projects': [for (final p in store.values) p.toJson()],
        }),
      );
    } catch (_) {
      // الحصّة ممتلئة أو التخزين مرفوض — لا نُسقط الشاشة على المستخدم.
    }
  }
}
