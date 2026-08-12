import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../analytics/analytics.dart';
import '../../analytics/http_analytics.dart';
import '../../ai/contracts/llm_extraction_service.dart';
import '../../ai/contracts/speech_to_text_service.dart';
import '../../ai/contracts/vision_analysis_service.dart';
import '../../ai/mock/mock_llm_extraction_service.dart';
import '../../ai/mock/mock_speech_to_text_service.dart';
import '../../ai/mock/mock_vision_analysis_service.dart';
import '../../features/auth/data/mock_auth_repository.dart';
import '../../features/auth/domain/auth_repository.dart';
import '../../features/catalog/data/ikea_catalog_repository.dart';
import '../../features/consent/presentation/consent_controller.dart';
import '../../features/recommendations/data/recommendation_repository_impl.dart';
import '../../features/recommendations/domain/recommendation_repository.dart';
import '../../features/room_analysis/data/analysis_repository_impl.dart';
import '../../features/room_analysis/domain/analysis_repository.dart';
import '../../features/saved_projects/data/local_project_repository.dart';
import '../../features/saved_projects/domain/project_repository.dart';
import '../../shared/services/catalog_repository.dart';
import '../../shared/services/http_post.dart';

/// نقطة الحقن المركزية (ADR-0001 §4). التبديل mock ↔ real يتم عبر
/// `overrides` عند إنشاء `ProviderScope` دون لمس الـ UI.

final uuidProvider = Provider<Uuid>((ref) => const Uuid());

// ---- القياس (Analytics) ----
// الافتراضي Noop (لا يُسجّل شيئًا)؛ يُختار الـ sink الحقيقي عبر override في
// نقطة الدخول أو الاختبارات — دون لمس نقاط النداء.
/// وجهة القياس — تُضبط عند البناء:
/// `flutter build web --dart-define=ANALYTICS_ENDPOINT=https://…/events`
///
/// فارغة ⇒ لا إرسال. القياس **معطّل افتراضيًا** لا مفعّل: إرسال بيانات مستخدمين
/// إلى وجهة لم يخترها أحد قرار لا يُتخذ ضمنيًا.
const String kAnalyticsEndpoint =
    String.fromEnvironment('ANALYTICS_ENDPOINT');

/// موافقة المستخدم على القياس (نظام حماية البيانات الشخصية).
///
/// مربوطة بخيار المستخدم الصريح: `null` (لم يُسأل) و`false` (رفض) كلاهما **لا
/// جمع**. القياس معطّل حتى موافقة صريحة — لا نجمع بلا إذن.
final analyticsConsentProvider =
    Provider<bool>((ref) => ref.watch(consentControllerProvider) == true);

/// الـ sink الفعلي — **القرار كله هنا**، فلا يستبدله `main.dart` ولا غيره.
///
/// وضع التطوير يضيف [DebugAnalytics] ليبقى القِمع مرئيًا في الـ console، لكنه
/// لا يحلّ محلّ الإرسال الحقيقي بل يُضاف إليه.
final analyticsProvider = Provider<Analytics>((ref) {
  final sinks = <Analytics>[
    // GAP-4: حتى sink التطوير يحترم الموافقة — «لا جمع بلا إذن» تشمل الطباعة
    // في الـ console، فهي تسجيل للسلوك وإن لم تغادر الجهاز.
    if (kDebugMode)
      DebugAnalytics(log: true, consent: ref.watch(analyticsConsentProvider)),
  ];

  final uri = Uri.tryParse(kAnalyticsEndpoint);
  // GAP-5: أحداث المستخدمين لا تُرسل إلا مشفّرة — http صريح يُرفض لا يُجامَل.
  if (kAnalyticsEndpoint.isNotEmpty && uri != null && uri.scheme == 'https') {
    final remote = HttpAnalytics(
      endpoint: uri,
      post: httpPostJson,
      sessionId: ref.read(uuidProvider).v4(),
      consent: ref.watch(analyticsConsentProvider),
    );
    ref.onDispose(remote.dispose); // آخر فرصة لإرسال ما تبقّى
    sinks.add(remote);
  }

  if (sinks.isEmpty) return const NoopAnalytics();
  return sinks.length == 1 ? sinks.first : FanOutAnalytics(sinks);
});

// ---- طبقة الـ AI (mock-first) ----
final speechToTextServiceProvider = Provider<SpeechToTextService>(
  (ref) => const MockSpeechToTextService(),
);

final visionAnalysisServiceProvider = Provider<VisionAnalysisService>(
  (ref) => const MockVisionAnalysisService(),
);

final llmExtractionServiceProvider = Provider<LlmExtractionService>(
  (ref) => MockLlmExtractionService(uuidFactory: ref.read(uuidProvider).v4),
);

// ---- الكتالوج (Static JSON — القرار G2) ----
// المصدر الحيّ: كتالوج آيكيا السعودية الحقيقي عبر الابتلاع المتحقِّق (A7).
// كتالوج المحاكاة باقٍ أصلًا للاختبارات ولـ`AssetCatalogRepository`.
final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => const IkeaAssetCatalogRepository(),
);

// ---- المستودعات ----
final analysisRepositoryProvider = Provider<AnalysisRepository>(
  (ref) => AnalysisRepositoryImpl(
    speechToText: ref.read(speechToTextServiceProvider),
    vision: ref.read(visionAnalysisServiceProvider),
    llm: ref.read(llmExtractionServiceProvider),
  ),
);

final recommendationRepositoryProvider = Provider<RecommendationRepository>(
  (ref) => RecommendationRepositoryImpl(
    catalog: ref.read(catalogRepositoryProvider),
  ),
);

/// يبقى عبر إغلاق المتصفّح (`localStorage` على الويب). الانتقال إلى Firestore
/// لاحقًا (القرار G3) يبدّل هذا السطر وحده.
final projectRepositoryProvider = Provider<ProjectRepository>(
  (ref) => LocalProjectRepository(),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => MockAuthRepository(),
);
