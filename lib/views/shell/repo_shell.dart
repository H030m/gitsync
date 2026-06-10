import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// Shared shell with bottom navigation for the per-repo routes
// (tasks / daily / stats / settings). Wraps the ShellRoute child from
// `app_router.dart`.
class RepoShell extends StatelessWidget {
  const RepoShell({
    super.key,
    required this.repoId,
    required this.child,
  });

  final String repoId;
  final Widget child;

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
      body: child,
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
          context.go('/repos/$repoId/${_items[i].segment}');
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
