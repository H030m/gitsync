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

  // GlobalKey preserves _SlidingBottomNavState across GoRouter rebuilds,
  // so AnimatedAlign always has a previous value to interpolate from.
  static final _navKey = GlobalKey();

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
      bottomNavigationBar: _SlidingBottomNav(
        key: _navKey,
        selectedIndex: _selectedIndex(context),
        items: _items,
        onTap: (i) {
          context.go('/repos/$repoId/${_items[i].segment}');
        },
      ),
    );
  }
}

class _SlidingBottomNav extends StatefulWidget {
  const _SlidingBottomNav({
    super.key,
    required this.selectedIndex,
    required this.items,
    required this.onTap,
  });

  final int selectedIndex;
  final List<_NavItem> items;
  final ValueChanged<int> onTap;

  @override
  State<_SlidingBottomNav> createState() => _SlidingBottomNavState();
}

class _SlidingBottomNavState extends State<_SlidingBottomNav> {
  static const _height = 80.0;
  static const _pillHeight = 56.0;
  static const _pillWidth = 64.0;
  static const _duration = Duration(milliseconds: 300);
  static const _curve = Curves.easeOut;

  Alignment _pillAlignment() {
    // Map index 0..n-1 to alignment -1..1.
    // Wrapping the pill in a FractionallySizedBox(widthFactor: 1/n) makes
    // AnimatedAlign land the pill exactly centered on each Expanded tab.
    final n = widget.items.length;
    final t = n <= 1 ? 0.0 : (widget.selectedIndex / (n - 1)) * 2 - 1;
    return Alignment(t, 0);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      height: _height + bottomPadding,
      decoration: BoxDecoration(
        color: const Color(0xFF222630),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Sliding pill indicator — FractionallySizedBox ensures the
          // alignment maps 1:1 to the Expanded tab positions.
          AnimatedAlign(
            duration: _duration,
            curve: _curve,
            alignment: _pillAlignment(),
            child: FractionallySizedBox(
              widthFactor: 1 / widget.items.length,
              child: Center(
                child: Container(
                  width: _pillWidth,
                  height: _pillHeight,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(_pillHeight / 2),
                  ),
                ),
              ),
            ),
          ),
          // Tab buttons
          Row(
            children: [
              for (var i = 0; i < widget.items.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onTap(i),
                    child: SizedBox(
                      height: _height,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            i == widget.selectedIndex
                                ? widget.items[i].selectedIcon
                                : widget.items[i].icon,
                            size: 24,
                            color: i == widget.selectedIndex
                                ? scheme.onPrimaryContainer
                                : scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.items[i].label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: i == widget.selectedIndex
                                  ? FontWeight.w600
                                  : null,
                              color: i == widget.selectedIndex
                                  ? scheme.onPrimaryContainer
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
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
