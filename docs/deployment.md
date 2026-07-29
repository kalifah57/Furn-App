# deployment.md — النشر والإصدار

> يوسّع القسم §9 من `docs/adr/0001-mvp-architecture-decisions.md` بما يتوافق مع
> `engineering_standards.md` والحالة الحالية للمستودع. **CI/CD والنشر الفعلي خارج
> نطاق المرحلة الحالية** — هذه الوثيقة تصميم + خطوات تشغيل.

## 1) حالة المستودع
- يحتوي `lib/`، `test/`، `assets/`، `docs/` وملفات الإعداد فقط — **بلا مجلدات
  المنصّات** (تُولَّد بـ `flutter create .` دون لمس `lib/`).
- المتطلبات: Flutter ≥ 3.24 · Dart ≥ 3.5.

## 2) التشغيل المحلي
```bash
flutter create .      # يولّد android/ ios/ web/ … دون لمس lib/
flutter pub get
flutter analyze
flutter test
flutter run
```

## 3) البيئات (Flavors)
| البيئة | الاستخدام | آلية |
|---|---|---|
| dev | تطوير محلي، mock-first | `--dart-define=ENV=dev` |
| staging | تكامل/اختبار | `--dart-define=ENV=staging` |
| prod | إنتاج | `--dart-define=ENV=prod` |

- تُقرأ الإعدادات من طبقة `core/config` (تُضاف عند الحاجة) — لا قيم مضمّنة في الكود.

## 4) الأسرار وإدارة المفاتيح (engineering_standards.md)
- **مفاتيح الـ API خارج الكود**: عبر `--dart-define` أو environment/secure config.
- `.gitignore` يستثني مسبقًا: `.env`, `lib/core/config/firebase_options.dart`,
  `google-services.json`, `GoogleService-Info.plist`.
- **ممنوع** إيداع أي مفتاح/سر في المستودع.

## 5) البناء
```bash
flutter build apk --release            # Android
flutter build appbundle --release      # Play Store
flutter build ios --release            # iOS
flutter build web --release            # Web
```

## 6) تصميم CI/CD (غير مُنفَّذ الآن)
عند تفعيله لاحقًا (GitHub Actions) — تصميم مقترح، **لا يُضاف كملف في هذه المرحلة**:
```yaml
# .github/workflows/ci.yml  (تصميم مستقبلي)
on: [pull_request]
jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.24.x' }
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
      - run: flutter build apk --debug   # فحص بناء
```
- على كل PR: `analyze` + `test` + فحص بناء. Release workflow لاحقًا.

## 7) سير عمل Git (engineering_standards.md)
- `main` مستقر · فروع `feature/*` لكل ميزة · PR لكل دمج · **مراجعة كود قبل الدمج**.

## 8) Firebase (مؤجّل — تصميم فقط)
- `firebase_options.dart` لكل flavor (خارج الـ VCS).
- `google-services.json` / `GoogleService-Info.plist` (خارج الـ VCS).
- قواعد `Firestore` و`Storage` تُضاف مع تفعيل الربط الحقيقي (المرحلة ٢+).
- **لا يُفعَّل الآن** (Auth/Firestore/Storage خارج نطاق المرحلة الحالية).

## 9) التوزيع والإصدار
- التوزيع (خارج الـ MVP): Firebase App Distribution → المتاجر.
- الإصدار: `version` في `pubspec.yaml`؛ توثيق **إصدارات الـ schema والـ prompt**
  (`supported_schema_version`, `prompt version` في `lib/ai/prompt/prompt_template.dart`).
- التراجع (Rollback): عبر وسم الإصدارات في Git والبناءات السابقة.

## 10) خارج النطاق الآن
CI/CD فعلي · نشر Firebase · توزيع متاجر — كلّها مرحلة لاحقة، بعد جولة التحقق النهائية.
