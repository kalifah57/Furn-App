import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/ai/parsing/plan_command.dart';
import 'package:furn_app/analytics/analytics.dart';
import 'package:furn_app/domain_engine/plan/plan_workspace.dart';
import 'package:furn_app/features/plan/presentation/plan_controller.dart';
import 'package:furn_app/shared/models/models.dart';

/// المساعد يفهم؛ المحرّك يقرّر. تُثبت هذه الاختبارات أن كل نيّةٍ تمرّ عبر عمليات
/// المحرّك الموجودة فتغيّر الخطة فعلًا (لا تَعِد فقط)، وأن المجهول لا يمسّ شيئًا.
void main() {
  const catalog = <CatalogProduct>[
    CatalogProduct(
        productId: 'bed',
        title: 'سرير',
        category: RecommendationCategory.bed,
        widthCm: 140,
        depthCm: 200,
        price: 800),
    CatalogProduct(
        productId: 'rug1',
        title: 'سجادة أوفر',
        category: RecommendationCategory.rug,
        widthCm: 160,
        depthCm: 230,
        price: 200),
    CatalogProduct(
        productId: 'rug2',
        title: 'سجادة أغلى',
        category: RecommendationCategory.rug,
        widthCm: 160,
        depthCm: 230,
        price: 400),
  ];

  FurnishingProject project({double budget = 2000}) => FurnishingProject(
        projectId: 'p',
        room: const Room(widthM: 3, lengthM: 3.5, roomType: RoomType.bedroom),
        budget: Budget(maxTotal: budget),
        items: const RequestedItems(essential: [RequestedItem(type: 'سرير')]),
      );

  PlanController controller({double budget = 2000, DebugAnalytics? analytics}) =>
      PlanController(
        PlanWorkspace(project: project(budget: budget), catalog: catalog),
        analytics: analytics ?? DebugAnalytics(log: false),
      );

  test('«اجعلها أوفر» يخفض الميزانية عبر المحرّك', () {
    final c = controller(budget: 2000);
    addTearDown(c.dispose);
    final r = c.runCommand('اجعلها أوفر');
    expect(r.understood, isTrue);
    expect(c.project.budget.maxTotal, 1700); // 2000 × 0.85
  });

  test('«ميزانيتي ٣٠٠٠» تحدّد الميزانية', () {
    final c = controller();
    addTearDown(c.dispose);
    c.runCommand('ميزانيتي ٣٠٠٠');
    expect(c.project.budget.maxTotal, 3000);
  });

  test('الميزانية الصريحة تُقيَّد بالحدّ الأدنى', () {
    final c = controller();
    addTearDown(c.dispose);
    c.applyCommand(const SetBudgetCommand(50));
    expect(c.project.budget.maxTotal, 500);
  });

  test('«أضف سجادة» يضيف الأوفر ويثبّتها', () {
    final c = controller();
    addTearDown(c.dispose);
    final r = c.runCommand('أضف سجادة');
    expect(r.understood, isTrue);
    expect(
        c.plan.items.any((e) =>
            e.item.category == RecommendationCategory.rug &&
            e.item.productId == 'rug1'),
        isTrue);
  });

  test('«احذف السرير» يزيله من الخطة', () {
    final c = controller();
    addTearDown(c.dispose);
    expect(
        c.plan.items
            .any((e) => e.item.category == RecommendationCategory.bed),
        isTrue);
    c.runCommand('احذف السرير');
    expect(
        c.plan.items
            .any((e) => e.item.category == RecommendationCategory.bed),
        isFalse);
  });

  test('طلبُ فئةٍ لا نوفّرها: يُفهَم دون أن يغيّر الخطة', () {
    final c = controller();
    addTearDown(c.dispose);
    final before = c.plan.itemCount;
    final r =
        c.applyCommand(const AddCategoryCommand(RecommendationCategory.lamp));
    expect(r.understood, isTrue);
    expect(c.plan.itemCount, before);
    expect(
        c.plan.items
            .any((e) => e.item.category == RecommendationCategory.lamp),
        isFalse);
  });

  test('«جاهز» يعتمد الخطة', () {
    final c = controller();
    addTearDown(c.dispose);
    c.runCommand('جاهز');
    expect(c.plan.isFinalized, isTrue);
  });

  test('المجهول لا يُفهَم ولا يغيّر شيئًا', () {
    final c = controller(budget: 2000);
    addTearDown(c.dispose);
    final r = c.runCommand('شكرا يا مساعد');
    expect(r.understood, isFalse);
    expect(c.project.budget.maxTotal, 2000);
    expect(c.plan.isFinalized, isFalse);
  });

  test('كل أمرٍ يُسجَّل assistant_command ثم حدث المحرّك', () {
    final a = DebugAnalytics(log: false);
    final c = controller(analytics: a);
    addTearDown(c.dispose);
    c.runCommand('أضف سجادة'); // assistant_command + item_pinned
    expect(a.names, ['plan_seeded', 'assistant_command', 'item_pinned']);
    expect(a.events.whereType<AssistantCommand>().single.understood, isTrue);
  });

  test('المجهول يُسجَّل understood=false', () {
    final a = DebugAnalytics(log: false);
    final c = controller(analytics: a);
    addTearDown(c.dispose);
    c.runCommand('كلام عام');
    expect(a.events.whereType<AssistantCommand>().single.understood, isFalse);
  });
}
