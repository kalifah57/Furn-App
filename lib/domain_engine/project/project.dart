import 'package:equatable/equatable.dart';

import '../../shared/models/models.dart';
import '../plan/plan.dart';
import 'decision.dart';

/// دورة حياة المشروع — من مسوّدة إلى معتمَد.
enum ProjectStatus { draft, active, approved }

/// حارس «لم يُمرَّر» لـ [Project.copyWith] — يميّزه عن null الصريحة.
class _Unset {
  const _Unset();
}

const _unset = _Unset();

/// **الجذر الكلّي (Aggregate Root).** المشروع = المُلخّص (الغرفة/الميزانية/الاحتياج)
/// + الخطة المشتقّة الحالية + مسار القرارات + الحالة. المنتج النهائي المُباع هو
/// **خطة التأثيث داخل مشروع معتمَد.** كيان نقي بلا Flutter (قابل للاختبار بمعزل).
class Project extends Equatable {
  const Project({
    required this.id,
    required this.brief,
    required this.plan,
    this.status = ProjectStatus.draft,
    this.timeline = const DecisionTimeline(),
    this.title = 'خطتي',
    this.approvedAt,
  });

  final String id;

  /// المُلخّص الثابت: الغرفة، الميزانية، النمط، الاحتياج (مدخل المستخدم).
  final FurnishingProject brief;

  /// الخطة المشتقّة الحالية + الثقة (يُعيد المحرّك اشتقاقها بعد كل قرار).
  final Plan plan;

  final ProjectStatus status;
  final DecisionTimeline timeline;
  final String title;
  final DateTime? approvedAt;

  int get confidence => plan.confidence;
  bool get isApproved => status == ProjectStatus.approved;
  bool get isDraft => status == ProjectStatus.draft;
  double get budgetMax => brief.budget.maxTotal;
  double get total => plan.total;

  /// [approvedAt] وحده حقل قابل لـ null، ولذلك لا يصلح معه `??`: تمرير null
  /// صراحةً (كما يفعل [reopen]) كان يُفسَّر «لم يُمرَّر» فيبقى تاريخ الاعتماد
  /// على مشروع أُعيد فتحه. الحارس يفصل «لم يُمرَّر» عن «امسحه».
  Project copyWith({
    FurnishingProject? brief,
    Plan? plan,
    ProjectStatus? status,
    DecisionTimeline? timeline,
    String? title,
    Object? approvedAt = _unset,
  }) =>
      Project(
        id: id,
        brief: brief ?? this.brief,
        plan: plan ?? this.plan,
        status: status ?? this.status,
        timeline: timeline ?? this.timeline,
        title: title ?? this.title,
        approvedAt: identical(approvedAt, _unset)
            ? this.approvedAt
            : approvedAt as DateTime?,
      );

  /// يسجّل قرارًا على المسار، يربط الخطة المُعاد اشتقاقها، وينقل الحالة إلى active
  /// (ما لم يكن معتمَدًا). هذا هو المدخل الوحيد لتغيير خطة المشروع.
  Project record(Decision decision, Plan rebuilt) => copyWith(
        plan: rebuilt,
        status: status == ProjectStatus.approved
            ? ProjectStatus.approved
            : ProjectStatus.active,
        timeline: timeline.add(decision),
      );

  /// اعتماد المشروع (Draft/Active → Approved) — نقطة «إكمال الخطة».
  Project approve(DateTime at) => copyWith(
        status: ProjectStatus.approved,
        approvedAt: at,
        timeline: timeline.add(Decision(
          kind: DecisionKind.approved,
          at: at,
          confidenceAfter: plan.confidence,
        )),
      );

  /// إعادة الفتح للتعديل بعد الاعتماد (Approved → active).
  Project reopen(DateTime at) => copyWith(
        status: ProjectStatus.active,
        approvedAt: null,
        timeline: timeline.add(Decision(kind: DecisionKind.reopened, at: at)),
      );

  @override
  List<Object?> get props =>
      [id, brief, plan, status, timeline, title, approvedAt];
}
