import '../../shared/models/enums.dart';

/// أمرٌ منظّم على الخطة — **مخرَج فهمٍ لا قرار**.
///
/// المساعد داخل «غرفتي» (وهميًّا الآن، مزوّد LLM لاحقًا) يفهم جملة المستخدم
/// ويحوّلها إلى واحدٍ من هذه الأوامر؛ ثم ينفّذها المحرّك الحتمي
/// (`PlanController`/`PlanWorkspace`) ويملك عواقبها. هذا هو الحدّ الجوهري في
/// التطبيق: الذكاء الاصطناعي يفهم اللغة، والمحرّك وحده يقرّر.
sealed class PlanCommand {
  const PlanCommand();

  /// اسم النيّة المستقر (snake_case) — للقياس والعرض: set_budget … unknown.
  String get intent;
}

/// «ميزانيتي ٣٠٠٠» — تحديد الميزانية عند مبلغٍ صريح.
class SetBudgetCommand extends PlanCommand {
  const SetBudgetCommand(this.amountSar);
  final double amountSar;
  @override
  String get intent => 'set_budget';
}

/// «اجعلها أوفر» / «زد الميزانية» — إزاحة الميزانية دون رقمٍ صريح.
/// [direction] = ‎-1‎ أوفر، ‎+1‎ أعلى.
class NudgeBudgetCommand extends PlanCommand {
  const NudgeBudgetCommand(this.direction);
  final int direction;
  @override
  String get intent => 'nudge_budget';
}

/// «أضف طاولة» — إضافة فئة إلى الخطة.
class AddCategoryCommand extends PlanCommand {
  const AddCategoryCommand(this.category);
  final RecommendationCategory category;
  @override
  String get intent => 'add';
}

/// «احذف الأريكة» — إزالة فئة من الخطة.
class RemoveCategoryCommand extends PlanCommand {
  const RemoveCategoryCommand(this.category);
  final RecommendationCategory category;
  @override
  String get intent => 'remove';
}

/// «جاهز» / «اعتمد الخطة» — اعتماد الخطة.
class FinalizeCommand extends PlanCommand {
  const FinalizeCommand();
  @override
  String get intent => 'finalize';
}

/// لم نفهم الطلب — نطلب صياغةً أوضح بدل أن نخمّن فعلًا لم يُطلَب. الصمت الآمن
/// خيرٌ من إجراءٍ خاطئ يُفقِد الثقة.
class UnknownCommand extends PlanCommand {
  const UnknownCommand(this.text);
  final String text;
  @override
  String get intent => 'unknown';
}
