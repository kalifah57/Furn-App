import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../analytics/analytics.dart';
import '../../ai/contracts/llm_extraction_service.dart';
import '../../ai/contracts/speech_to_text_service.dart';
import '../../ai/contracts/vision_analysis_service.dart';
import '../../ai/mock/mock_llm_extraction_service.dart';
import '../../ai/mock/mock_speech_to_text_service.dart';
import '../../ai/mock/mock_vision_analysis_service.dart';
import '../../features/auth/data/mock_auth_repository.dart';
import '../../features/auth/domain/auth_repository.dart';
import '../../features/recommendations/data/recommendation_repository_impl.dart';
import '../../features/recommendations/domain/recommendation_repository.dart';
import '../../features/room_analysis/data/analysis_repository_impl.dart';
import '../../features/room_analysis/domain/analysis_repository.dart';
import '../../features/saved_projects/data/in_memory_project_repository.dart';
import '../../features/saved_projects/domain/project_repository.dart';
import '../../shared/services/catalog_repository.dart';

/// نقطة الحقن المركزية (ADR-0001 §4). التبديل mock ↔ real يتم عبر
/// `overrides` عند إنشاء `ProviderScope` دون لمس الـ UI.

final uuidProvider = Provider<Uuid>((ref) => const Uuid());

// ---- القياس (Analytics) ----
// الافتراضي Noop (لا يُسجّل شيئًا)؛ يُختار الـ sink الحقيقي عبر override في
// نقطة الدخول أو الاختبارات — دون لمس نقاط النداء.
final analyticsProvider = Provider<Analytics>((ref) => const NoopAnalytics());

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
final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => const AssetCatalogRepository(),
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

final projectRepositoryProvider = Provider<ProjectRepository>(
  (ref) => InMemoryProjectRepository(),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => MockAuthRepository(),
);
