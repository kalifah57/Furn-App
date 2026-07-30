import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/constants/app_strings.dart';
import '../core/router/app_router.dart';
import '../core/theme/app_theme.dart';

/// جذر التطبيق: عربي-أولًا مع RTL كامل (يُضبط عبر locale = ar).
class FurnApp extends StatelessWidget {
  const FurnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppStrings.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: appRouter,
      // على الشاشات العريضة (ويب/لوحي): اجعل التطبيق عمودًا وسطيًا بعرض هاتف،
      // فلا يتمدّد أو ينزاح. على الهاتف (أضيق من 480) لا يؤثّر.
      builder: (context, child) => ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
      // العربية-أولًا مع RTL كامل.
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
