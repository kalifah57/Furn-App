import '../../shared/models/catalog_product.dart';
import 'scoring.dart';

/// مرشَّح بعد احتساب درجته — يقرن منتج الكتالوج بتفصيل الدرجة.
/// (كان سابقًا نوعًا خاصًا داخل RecommendationEngine؛ رُفِّع ليُشارَك بين المحرّكات.)
class ScoredCandidate {
  const ScoredCandidate(this.product, this.breakdown);

  final CatalogProduct product;
  final ScoreBreakdown breakdown;
}
