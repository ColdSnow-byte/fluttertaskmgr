import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 预热 shader（纯异步磁盘 → 内存，不阻塞首帧）。
  await LiquidGlassWidgets.initialize();

  runApp(
    LiquidGlassWidgets.wrap(
      // MaterialApp 必须传，否则玻璃会跟随系统明暗而不是 App 的 ThemeMode。
      brightnessResolver: Theme.maybeBrightnessOf,
      theme: GlassThemeData.simple(
        blur: 12,
        thickness: 28,
        quality: GlassQuality.standard,
      ),
      child: const PureFlutterApp(),
    ),
  );
}

class PureFlutterApp extends StatelessWidget {
  const PureFlutterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Windows 任务管理器',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6E8BFF),
          brightness: Brightness.dark,
        ),
      ),
      // 本库不依赖 Material，但 Text 需要一个 Material 祖先，
      // 否则会出现黄色下划线调试样式。
      builder: (context, child) => Material(
        type: MaterialType.transparency,
        child: child!,
      ),
      home: const AppShell(),
    );
  }
}
