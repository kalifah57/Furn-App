import '../../shared/models/models.dart';
import 'scored_candidate.dart';
import 'scoring.dart';

/// تحويل مرشَّح مُقيَّم إلى عنصر توصية + بناء نص السبب (L0 headline في explainability.md).
/// مشترك بين اختيار العناصر الفردية وتكوين الباقات لتفادي التكرار.

RecommendedItem toRecommendedItem(ScoredCandidate s, ItemPriority priority) {
  return RecommendedItem(
    name: s.product.title,
    category: s.product.category,
    price: s.product.price,
    reason: reasonFor(s.breakdown),
    priority: priority,
    productId: s.product.productId,
    score: double.parse(s.breakdown.total.toStringAsFixed(1)),
  );
}

String reasonFor(ScoreBreakdown b) {
  final parts = <String>[];
  if (b.room >= 0.8) parts.add('يناسب مساحة الغرفة');
  if (b.budget >= 0.7) parts.add('ضمن سقف الميزانية');
  if (b.style >= 0.7) parts.add('متوافق مع النمط المفضّل');
  if (b.quality >= 0.8) parts.add('تقييم مرتفع');
  if (parts.isEmpty) parts.add('خيار عملي متوازن');
  return '${parts.join('، ')}.';
}
