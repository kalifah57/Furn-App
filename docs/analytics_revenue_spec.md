# G3 — قياس الإيراد: أفلييت/عمولة على `merchant_click` (spec قابلة للتفعيل)

> **الحالة:** spec جاهزة للتفعيل. الإشارة المرساة موصَّلة، والكتالوج الحقيقيّ وصل (٥٠/٥٠ روابط `/sa/en/` صالحة)، **فقِمع الإيراد صار حقيقيًّا من طرف البيانات**. يبقى التفعيل الكامل موقوفًا على اختيار شبكة أفلييت/شريك ونقطة النهاية (🔒F4).
> **الملكية:** المسار ٥ يملك إشارة الإيراد وتعريفها ومنطق الإسناد؛ نقطة النداء (زرّ المتجر) لمسار ٤. تلاحظ ولا تغيّر · التسوّق اختياريّ · بلا PII.
> يَحلّ محلّ المسودّة الخضراء `analytics_revenue_plan.md` (كُتبت قبل وصول الكتالوج).

---

## 0. الوصلات الحقيقية (ما هو موصَّل الآن)

| العنصر | الواقع في الكود/البيانات |
|---|---|
| **الإشارة المرساة** | `MerchantClicked(productId, category)` — `sandbox_screen.dart:211`، خلف بوابة الموافقة (يُسقَط بلا موافقة). |
| **الفعل الخارجيّ** | `openStore(p.productUrl)` — `sandbox_screen.dart:212` → `html.window.open(url, '_blank', 'noopener,noreferrer')`. |
| **الرابط** | `p.productUrl` = `urls.product_link` من الكتالوج، مثال حقيقي: `https://www.ikea.com/sa/en/p/strandmon-wing-chair-...-50613163/` (٥٠/٥٠ صالحة). |
| **السعر الحقيقيّ** | `price_sar` لكل منتج في `assets/catalog/ikea_ksa.json` (مثال: `1095.0`). |
| **الظهور** | الزرّ يظهر فقط إذا `productUrl.isNotEmpty` — كان خامدًا على البيانات الوهمية، وأضاء بوصول الكتالوج الحقيقيّ. |

**الأثر:** لم نعُد نُقدّر GMV بفرضية سعر — **السعر حقيقيّ**؛ يبقى معدّل التحويل والعمولة فرضيّتين حتى الشريك.

---

## 1. نموذج العائد وسلسلة الإسناد

Furn-App لا يبيع؛ يوجّه النيّة إلى IKEA KSA. نموذجان (network-agnostic):

- **أفلييت (Affiliate):** رابط مُتتبَّع يحمل مُعرّف ناشر؛ الشبكة تقيس التحويل وتحسب العمولة، ونقرأ تقريرها.
- **عمولة مباشرة (Commission):** اتفاق + Postback من الشريك على كل طلب مُتمَّم من إحالتنا.

```
النيّة                       الانتقال المُتتبَّع            التحويل الخارجيّ        التسوية
merchant_click  ──▶  openStore(tagged product_link)  ──▶  partner conversion  ──▶  commission
(نملكها، خلف موافقة)   (نملكها: رابط + click_id مجهول)    (شريك — لا نراها)     (شريك — postback/تقرير)
```

| الحلقة | نملكها؟ |
|---|---|
| `merchant_click` (النيّة) + السعر الحقيقيّ | **نعم — الآن** |
| الانتقال المُتتبَّع (`click_id` في الرابط) | **نعم — P1 (بنيتنا)** |
| التحويل/قيمة الطلب/العمولة | **لا — يحتاج شريكًا (P2)** |

---

## 2. المقاييس — ما يُقاس الآن (بيانات حقيقية)

خلف الموافقة، على الجلسات الموافِقة:

- **حجم النيّة:** عدد جلسات `merchant_click`.
- **CTR إلى التاجر:** `merchant_click / (options_opened ∪ ar_opened)` أو `/ flow_started` (مدخل قِمع الإيراد، انظر G2).
- **مزيج الفئات:** توزيع `merchant_click` حسب `category` (غير شخصيّ).
- **نيّة لكل خطة مُنجَزة:** `merchant_click / plan_finalized` — قياس أن «التسوّق مُضاف» لا مفروض.
- **GMV تقديريّ بأسعار حقيقية:** ‏`product_id` من الحدث يُوصَل بـ`price_sar` من الكتالوج (بُعد أسعار). التحويل/العمولة فرضيّتان مُعلَّمتان.

**الاستعلام (بُعد أسعار من الكتالوج + أحداث):**
```sql
-- product_prices(product_id TEXT, price_sar NUMERIC)  ← يُحمَّل من ikea_ksa.json
WITH clicks AS (
  SELECT params->>'product_id' AS product_id,
         params->>'category'   AS category,
         COUNT(*)              AS clicks
  FROM events
  WHERE name='merchant_click' AND at >= NOW() - INTERVAL '30 days'
  GROUP BY 1,2
)
SELECT
  c.category,
  SUM(c.clicks)                                              AS merchant_clicks,
  SUM(c.clicks * p.price_sar)                                AS clicked_value_sar,      -- سعر حقيقيّ
  SUM(c.clicks * p.price_sar) * :assumed_conversion_rate     AS est_gmv_sar,            -- تحويل مفترض
  SUM(c.clicks * p.price_sar) * :assumed_conversion_rate
                              * :assumed_commission_rate      AS est_commission_sar      -- عمولة مفترضة
FROM clicks c
LEFT JOIN product_prices p ON p.product_id = c.product_id
GROUP BY c.category
ORDER BY merchant_clicks DESC;
```

> **حاجز:** `clicked_value_sar` قيمة نيّة حقيقية (سعر × نقرات)، **لا إيراد**. `est_*` تقديرات إرشادية — الأرقام تُرشد لا تقرّر — تُستبدَل ببيانات الشريك عند P2.

---

## 3. آلية الإسناد بلا PII (P1) — نقطة الحقن الدقيقة

الإسناد يمرّر **`click_id` مجهولًا عابرًا** في الرابط الخارجيّ، ويُطابَق لاحقًا — بلا هوية.

**موضع الحقن (في نقطة النداء، `sandbox_screen.dart:209-213`):** بين `track` و`openStore`:

```dart
onPressed: () {
  ref.read(analyticsProvider).track(
      MerchantClicked(p.productId, category: p.category.wire));
  // P1 — عند تفعيل الأفلييت (يملك النداء مسار ٤؛ الدالة إشارة إيراد يملكها ٥):
  final clickId = ref.read(uuidProvider).v4();            // مجهول لكل نقرة
  final url = buildAffiliateUrl(p.productUrl, clickId);   // دالة نقيّة (مسار ٥)
  openStore(url);
}
```

**`buildAffiliateUrl` (إشارة إيراد يملكها المسار ٥ — دالة نقيّة، تُفعَّل باختيار الشبكة):** تُلحق بمعاملات استعلام مجهولة برابط IKEA KSA:
```
https://www.ikea.com/sa/en/p/...-50613163/?utm_source=furn-app&utm_medium=plan&subid=<click_id>[&aff=<publisher_id>]
```
- `<click_id>` عشوائيّ مجهول، **لا يُشتق من هوية**، لكل نقرة.
- لا اسم/بريد/هوية في الرابط. UTM تصف القناة (`plan`) لا الشخص.
- **الموافقة شرط:** عند `denied`/`absent` لا `click_id` — يُفتح الرابط الأصليّ نظيفًا (التسوّق اختياريّ ولا يتأثّر).

**Postback (P2):** يُرسِل الشريك عند التحويل نداءً خلفيًّا يحمل **نفس `click_id`** وقيمة/حالة التحويل (بلا PII)؛ نطابقه مع `merchant_click` فنُغلق الحلقة دون معرفة المستخدم.

---

## 4. خارطة التفعيل

| المرحلة | ما يُفعَّل | يملكه | البوابة |
|---|---|---|---|
| **P0 — قياس النيّة** ✅ الآن | حجم النيّة، CTR، مزيج الفئات، GMV تقديريّ بأسعار حقيقية | المسار ٥ (SQL/تقرير) | الموافقة فقط |
| **P1 — إسناد الخروج** | `buildAffiliateUrl` + `click_id` في نقطة النداء | دالة: ٥ · النداء: ٤ | مراجعة PDPL لتوليد/تدوير `click_id` + اختيار الشبكة |
| **P2 — تسوية الشريك** | استقبال Postback/تقرير أفلييت والمطابقة على `click_id` | المسار ٥ + عقد الشريك | 🔒F4 + عقد يمنع إعادة أي PII |

---

## 5. موجَّه للمعماري (تفعيل P1)
- **نقطة نداء (مسار ٤):** حقن `buildAffiliateUrl(p.productUrl, clickId)` بين `track` و`openStore` في `sandbox_screen.dart` — **أُعرّف الدالة والإشارة، ويضيف مسار ٤ النداء** (كـ GAP-1).
- **قرار مؤسّس/عمل:** اختيار شبكة الأفلييت/الشريك وصيغة `subid`/`publisher_id`، وسياسة تدوير `click_id` (مراجعة PDPL).
- **قيد:** `buildAffiliateUrl` دالة نقيّة بلا شبكة؛ لا شيء داخل `lib/domain_engine/`.

> **مبدأ حاكم:** تحسين الإيراد **لا يمسّ حلقة الثقة** — لا ترتيب عناصر متحيّز، لا دفع للنقر، لا احتكاك. الخطة تبقى المنتج، والتسوّق مُضاف واختياريّ.
