import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'router.dart';

class DocViewApp extends StatelessWidget {
  const DocViewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'DocView',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
