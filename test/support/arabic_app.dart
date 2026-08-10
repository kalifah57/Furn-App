import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// The app shell **as the app actually runs**: Arabic locale, therefore RTL.
///
/// A bare `MaterialApp(home: …)` in a test inherits the runner's locale and
/// lays the screen out left-to-right — the one direction no user of this app
/// will ever see. Direction bugs then pass every test by construction: an
/// `EdgeInsets.fromLTRB` whose start and end are mirrored looks correct in
/// exactly the direction the suite runs in.
///
/// Mirrors `lib/app/app.dart` deliberately. It does **not** copy the 480px
/// width clamp: that belongs to the real shell, and a test that needs a
/// narrow surface should say so with `tester.view.physicalSize`.
Widget arabicApp(Widget home) => MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    );
