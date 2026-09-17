import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'glass_backdrop.dart';
import 'system/performance_page.dart';
import 'task_manager/task_manager_page.dart';

/// 应用外壳：底部两个 tab —— 性能 / 进程。
///
/// GlassScaffold 负责背景、层级（栏永远压在内容之上）、滚动边缘渐隐、
/// 安全区留白与状态栏配色，因此这里不需要自己搭 Stack。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  static const _titles = ['性能', '进程'];
  static const _pages = <Widget>[
    PerformancePage(),
    TaskManagerPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      // 没有背景的玻璃是“看不见”的：折射与模糊必须有内容可采样。
      background: const GlassBackdrop(),
      statusBarStyle: GlassStatusBarStyle.auto,
      // 导航栏/标签栏会根据滚过背后的内容自动切换明暗。
      contentAwareBrightness: true,
      appBar: GlassAppBar(
        title: Text(
          _titles[_selectedIndex],
          style: const TextStyle(
            color: CupertinoColors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      bottomBar: GlassTabBar.bottom(
        selectedIndex: _selectedIndex,
        onTabSelected: (index) => setState(() => _selectedIndex = index),
        adaptiveBrightness: true,
        tabs: const [
          GlassTab(
            icon: Icon(CupertinoIcons.speedometer),
            label: '性能',
          ),
          GlassTab(
            icon: Icon(CupertinoIcons.square_grid_2x2_fill),
            label: '进程',
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
    );
  }
}
