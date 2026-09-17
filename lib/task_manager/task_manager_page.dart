import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'process_info.dart';
import 'process_manager.dart';

/// Windows 任务管理器页面：进程列表 / 搜索 / 结束进程 / 运行新任务。
class TaskManagerPage extends StatefulWidget {
  const TaskManagerPage({super.key});

  @override
  State<TaskManagerPage> createState() => _TaskManagerPageState();
}

enum _SortMode { name, cpu, memory }

class _TaskManagerPageState extends State<TaskManagerPage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _launchController = TextEditingController();

  List<ProcessEntry> _processes = <ProcessEntry>[];
  String? _error;
  bool _loading = true;
  bool _autoRefresh = true;
  _SortMode _sortMode = _SortMode.memory;

  static const _refreshInterval = Duration(seconds: 2);

  bool get _isSupported => ProcessManager.isSupported;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _startAutoRefresh());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _launchController.dispose();
    super.dispose();
  }

  /// 用递归定时器而不是 Timer.periodic：前一次请求没回来就不会叠加下一次。
  void _startAutoRefresh() {
    if (!mounted) return;
    Future<void>.delayed(_refreshInterval, () async {
      if (!mounted) return;
      if (_autoRefresh && _isSupported) {
        await _refresh();
      }
      _startAutoRefresh();
    });
  }

  Future<void> _refresh() async {
    if (!_isSupported) return;
    try {
      final processes = await ProcessManager.getProcesses();
      if (!mounted) return;
      setState(() {
        _processes = processes;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  List<ProcessEntry> get _visibleProcesses {
    final query = _searchController.text.trim().toLowerCase();
    final list = _processes.where((process) {
      if (query.isEmpty) return true;
      return process.name.toLowerCase().contains(query) ||
          process.path.toLowerCase().contains(query) ||
          process.pid.toString().contains(query);
    }).toList();

    switch (_sortMode) {
      case _SortMode.name:
        list.sort((a, b) => a.displayName
            .toLowerCase()
            .compareTo(b.displayName.toLowerCase()));
      case _SortMode.cpu:
        list.sort((a, b) => b.cpuPercent.compareTo(a.cpuPercent));
      case _SortMode.memory:
        list.sort((a, b) => b.memoryBytes.compareTo(a.memoryBytes));
    }
    return list;
  }

  int get _totalMemory => _processes.fold<int>(
        0,
        (sum, process) => sum + process.memoryBytes,
      );

  @override
  Widget build(BuildContext context) {
    if (!_isSupported) {
      return const Center(
        child: Text(
          '进程管理仅在 Windows 端可用',
          style: TextStyle(color: CupertinoColors.systemGrey),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolbar(),
        _buildSortRow(),
        _buildSummary(),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: GlassTextField(
              controller: _searchController,
              placeholder: '搜索进程名 / PID / 路径',
              prefixIcon: const Icon(CupertinoIcons.search, size: 18),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : const Icon(CupertinoIcons.clear_circled_solid, size: 18),
              onSuffixTap: () => _searchController.clear(),
              useOwnLayer: true,
            ),
          ),
          const SizedBox(width: 10),
          GlassIconButton(
            icon: Icon(_autoRefresh ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill),
            onPressed: () => setState(() => _autoRefresh = !_autoRefresh),
            useOwnLayer: true,
            semanticLabel: _autoRefresh ? '暂停自动刷新' : '开始自动刷新',
          ),
          const SizedBox(width: 8),
          GlassIconButton(
            icon: const Icon(CupertinoIcons.refresh),
            onPressed: _refresh,
            useOwnLayer: true,
            semanticLabel: '立即刷新',
          ),
        ],
      ),
    );
  }

  Widget _buildSortRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: GlassSegmentedControl(
              segments: const [
                GlassSegment(label: '名称'),
                GlassSegment(label: 'CPU'),
                GlassSegment(label: '内存'),
              ],
              selectedIndex: _SortMode.values.indexOf(_sortMode),
              onSegmentSelected: (index) =>
                  setState(() => _sortMode = _SortMode.values[index]),
              useOwnLayer: true,
            ),
          ),
          const SizedBox(width: 10),
          GlassButton.custom(
            width: 108,
            height: 44,
            onTap: _showRunSheet,
            useOwnLayer: true,
            child: const Text(
              '运行新任务',
              style: TextStyle(color: CupertinoColors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final visible = _visibleProcesses;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 6),
      child: Row(
        children: [
          Text(
            '${visible.length} / ${_processes.length} 个进程',
            style: const TextStyle(
              color: CupertinoColors.systemGrey,
              fontSize: 12,
            ),
          ),
          const Spacer(),
          Text(
            '工作集合计 ${(_totalMemory / (1024 * 1024)).toStringAsFixed(0)} MB',
            style: const TextStyle(
              color: CupertinoColors.systemGrey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '读取进程失败：$_error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: CupertinoColors.systemRed),
          ),
        ),
      );
    }

    final processes = _visibleProcesses;
    if (processes.isEmpty) {
      return const Center(
        child: Text(
          '没有匹配的进程',
          style: TextStyle(color: CupertinoColors.systemGrey),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: processes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) =>
          _ProcessRow(process: processes[index], onKill: _confirmKill),
    );
  }

  Future<void> _confirmKill(ProcessEntry process) async {
    await GlassDialog.show<void>(
      context: context,
      title: '结束 ${process.displayName}？',
      message: 'PID ${process.pid}${process.hasPath ? '\n${process.path}' : ''}',
      actions: [
        GlassDialogAction(
          label: '取消',
          onPressed: () => Navigator.of(context).pop(),
        ),
        GlassDialogAction(
          label: '请求关闭',
          onPressed: () {
            Navigator.of(context).pop();
            _kill(process, force: false);
          },
        ),
        GlassDialogAction(
          label: '结束进程',
          isDestructive: true,
          onPressed: () {
            Navigator.of(context).pop();
            _kill(process, force: true);
          },
        ),
      ],
    );
  }

  Future<void> _kill(ProcessEntry process, {required bool force}) async {
    if (process.pid == ProcessManager.selfPid) {
      GlassToast.show(
        context,
        message: '不能结束本应用自己',
        type: GlassToastType.warning,
      );
      return;
    }

    final ok = await ProcessManager.killProcess(process.pid, force: force);
    if (!mounted) return;
    GlassToast.show(
      context,
      message: ok
          ? '已结束 ${process.displayName}'
          : '结束失败（权限不足或进程已退出）',
      type: ok ? GlassToastType.success : GlassToastType.error,
    );
    await _refresh();
  }

  void _showRunSheet() {
    _launchController.clear();
    GlassModalSheet.show<void>(
      context: context,
      initialState: GlassSheetState.half,
      halfSize: 0.55,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '运行新任务',
              style: TextStyle(
                color: CupertinoColors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '输入可执行程序、文件或网址，例如 notepad.exe',
              style: TextStyle(color: CupertinoColors.systemGrey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            CupertinoTextField(
              controller: _launchController,
              placeholder: 'notepad.exe',
              style: const TextStyle(color: CupertinoColors.white),
              placeholderStyle: const TextStyle(
                color: CupertinoColors.systemGrey,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: CupertinoColors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: CupertinoColors.white.withValues(alpha: 0.16),
                ),
              ),
              onSubmitted: (_) => _launch(sheetContext),
            ),
            const SizedBox(height: 16),
            const Text(
              '快速启动',
              style: TextStyle(color: CupertinoColors.systemGrey, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final item in _quickLaunch)
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    minimumSize: const Size(36, 36),
                    color: CupertinoColors.white.withValues(alpha: 0.12),
                    onPressed: () => _launch(sheetContext, target: item.path),
                    child: Text(
                      item.label,
                      style: const TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            CupertinoButton.filled(
              onPressed: () => _launch(sheetContext),
              child: const Text('启动'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launch(BuildContext sheetContext, {String? target}) async {
    final value = (target ?? _launchController.text).trim();
    if (value.isEmpty) return;

    final appContext = context;
    final navigator = Navigator.of(sheetContext);
    final ok = await ProcessManager.launch(value);
    if (!appContext.mounted) return;

    if (navigator.canPop()) {
      navigator.pop();
    }
    GlassToast.show(
      appContext,
      message: ok ? '已启动 $value' : '启动失败：$value',
      type: ok ? GlassToastType.success : GlassToastType.error,
    );
    await _refresh();
  }
}

const List<({String label, String path})> _quickLaunch = [
  (label: '记事本', path: 'notepad.exe'),
  (label: '计算器', path: 'calc.exe'),
  (label: '资源管理器', path: 'explorer.exe'),
  (label: '终端', path: 'wt.exe'),
  (label: '画图', path: 'mspaint.exe'),
  (label: '任务管理器', path: 'taskmgr.exe'),
];

class _ProcessRow extends StatelessWidget {
  const _ProcessRow({required this.process, required this.onKill});

  final ProcessEntry process;
  final ValueChanged<ProcessEntry> onKill;

  @override
  Widget build(BuildContext context) {
    final isSelf = process.pid == ProcessManager.selfPid;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CupertinoColors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: CupertinoColors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              process.displayName.isNotEmpty
                  ? process.displayName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: CupertinoColors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        process.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CupertinoColors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isSelf) ...[
                      const SizedBox(width: 6),
                      const Text(
                        '本应用',
                        style: TextStyle(
                          color: CupertinoColors.systemGreen,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'PID ${process.pid} · ${process.threadCount} 线程'
                  '${process.startTime != null ? ' · ${_formatTime(process.startTime!)} 启动' : ''}',
                  style: const TextStyle(
                    color: CupertinoColors.systemGrey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 58,
            child: Text(
              process.cpuText,
              textAlign: TextAlign.right,
              style: const TextStyle(color: CupertinoColors.white, fontSize: 13),
            ),
          ),
          SizedBox(
            width: 82,
            child: Text(
              process.memoryText,
              textAlign: TextAlign.right,
              style: const TextStyle(color: CupertinoColors.white, fontSize: 13),
            ),
          ),
          CupertinoButton(
            minimumSize: const Size(32, 32),
            padding: const EdgeInsets.all(4),
            onPressed: process.hasPath
                ? () => ProcessManager.revealProcess(process.pid)
                : null,
            child: const Icon(
              CupertinoIcons.folder,
              size: 18,
              color: CupertinoColors.systemGrey,
            ),
          ),
          CupertinoButton(
            minimumSize: const Size(32, 32),
            padding: const EdgeInsets.all(4),
            onPressed: () => onKill(process),
            child: const Icon(
              CupertinoIcons.xmark_circle_fill,
              size: 18,
              color: CupertinoColors.systemRed,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatTime(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
