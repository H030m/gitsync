import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/task.dart';
import '../../services/authentication.dart';
import '../../services/navigation.dart';
import '../../view_models/tasks_board_vm.dart';

// Shared shell with bottom navigation for the per-repo routes
// (tasks / daily / stats / settings). Wraps the ShellRoute child from
// `app_router.dart`.
//
// Also hosts the in-app assignment banner: it watches the repo's tasks and, when
// a task newly becomes assigned to the signed-in user, surfaces a SnackBar with
// a "View" action. This is the foreground counterpart to the FCM push (which
// covers the background/closed case) and works in both live and fake modes.
class RepoShell extends StatefulWidget {
  const RepoShell({
    super.key,
    required this.repoId,
    required this.child,
  });

  final String repoId;
  final Widget child;

  @override
  State<RepoShell> createState() => _RepoShellState();
}

class _RepoShellState extends State<RepoShell> {
  TasksBoardViewModel? _tasksVm;
  String? _uid;
  Set<String> _assignedToMe = {};
  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _uid = context.read<AuthenticationService>().currentUid;
    final tasksVm = context.read<TasksBoardViewModel>();
    if (!identical(tasksVm, _tasksVm)) {
      _tasksVm?.removeListener(_onTasksChanged);
      _tasksVm = tasksVm..addListener(_onTasksChanged);
      _seeded = false;
      _onTasksChanged();
    }
  }

  // Detect tasks that newly become assigned to me. The first loaded snapshot is
  // the baseline (no banner); only later transitions notify.
  void _onTasksChanged() {
    final vm = _tasksVm;
    final uid = _uid;
    if (vm == null || uid == null || uid.isEmpty) return;
    // Wait for the first real snapshot so existing assignments aren't announced.
    if (vm.loading) return;

    final mine = {
      for (final t in vm.tasks)
        if (t.assigneeId == uid) t.id,
    };
    if (!_seeded) {
      _assignedToMe = mine;
      _seeded = true;
      return;
    }

    final newly = mine.difference(_assignedToMe);
    _assignedToMe = mine;
    if (newly.isEmpty) return;

    final taskId = newly.first;
    final task = vm.tasks.firstWhere(
      (t) => t.id == taskId,
      orElse: () => Task(id: taskId, title: 'a task', createdBy: ''),
    );
    _showAssignedBanner(task);
  }

  void _showAssignedBanner(Task task) {
    final messenger = ScaffoldMessenger.of(context);
    final nav = context.read<NavigationService>();
    // Defer to after the current frame — the listener can fire mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('New task assigned to you: ${task.title}'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => nav.goTaskDetails(widget.repoId, task.id),
            ),
          ),
        );
    });
  }

  @override
  void dispose() {
    _tasksVm?.removeListener(_onTasksChanged);
    super.dispose();
  }

  static const _items = <_NavItem>[
    _NavItem(
      icon: Icons.view_kanban_outlined,
      selectedIcon: Icons.view_kanban,
      label: 'Tasks',
      segment: 'tasks',
    ),
    _NavItem(
      icon: Icons.today_outlined,
      selectedIcon: Icons.today,
      label: 'Daily',
      segment: 'daily',
    ),
    _NavItem(
      icon: Icons.bar_chart_outlined,
      selectedIcon: Icons.bar_chart,
      label: 'Stats',
      segment: 'stats',
    ),
    _NavItem(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Settings',
      segment: 'settings',
    ),
  ];

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    for (var i = 0; i < _items.length; i++) {
      if (location.contains('/${_items[i].segment}')) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex(context),
        destinations: [
          for (final item in _items)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: item.label,
            ),
        ],
        onDestinationSelected: (i) {
          context.go('/repos/${widget.repoId}/${_items[i].segment}');
        },
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.segment,
  });
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String segment;
}
