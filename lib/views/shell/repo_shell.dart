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
      label: '任務',
      segment: 'tasks',
    ),
    _NavItem(
      icon: Icons.today_outlined,
      selectedIcon: Icons.today,
      label: '每日彙整',
      segment: 'daily',
    ),
    _NavItem(
      icon: Icons.bar_chart_outlined,
      selectedIcon: Icons.bar_chart,
      label: '統計',
      segment: 'stats',
    ),
    _NavItem(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: '設定',
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

class _SlidingBottomNavState extends State<_SlidingBottomNav>
    with SingleTickerProviderStateMixin {
  static const _height = 80.0;
  static const _pillHeight = 56.0;
  static const _pillWidth = 64.0;
  static const _duration = Duration(milliseconds: 300);

  late final AnimationController _controller;
  late int _activeIndex;
  late double _from;
  late double _to;

  double _fraction(int index) {
    final n = widget.items.length;
    return n <= 1 ? 0.0 : index / (n - 1);
  }

  double get _currentPosition {
    final curved = Curves.easeOut.transform(_controller.value);
    return _from + (_to - _from) * curved;
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);
    _activeIndex = widget.selectedIndex;
    _from = _fraction(_activeIndex);
    _to = _from;
  }

  @override
  void didUpdateWidget(covariant _SlidingBottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync if external navigation changed the index (e.g. deep link)
    // but only if we aren't already animating to it.
    if (widget.selectedIndex != _activeIndex && !_controller.isAnimating) {
      _activeIndex = widget.selectedIndex;
      _from = _fraction(_activeIndex);
      _to = _from;
    }
  }

  void _handleTap(int index) {
    if (index == _activeIndex) return;
    // Start animation IMMEDIATELY on tap — before GoRouter rebuilds.
    setState(() {
      _from = _currentPosition;
      _activeIndex = index;
      _to = _fraction(index);
      _controller.forward(from: 0);
    });
    // Then navigate.
    widget.onTap(index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      height: _height + bottomPadding,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF222630)
            : const Color(0xFFFFFFFF),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final tabWidth = totalWidth / widget.items.length;

          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final pos = _currentPosition;
              final pillLeft =
                  pos * (totalWidth - tabWidth) + (tabWidth - _pillWidth) / 2;

              return Stack(
                children: [
                  // Sliding pill
                  Positioned(
                    left: pillLeft,
                    top: (_height - _pillHeight) / 2,
                    child: Container(
                      width: _pillWidth,
                      height: _pillHeight,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(_pillHeight / 2),
                      ),
                    ),
                  ),
                  // Tab buttons — use _activeIndex for visual state
                  Row(
                    children: [
                      for (var i = 0; i < widget.items.length; i++)
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _handleTap(i),
                            child: SizedBox(
                              height: _height,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    i == _activeIndex
                                        ? widget.items[i].selectedIcon
                                        : widget.items[i].icon,
                                    size: 24,
                                    color: i == _activeIndex
                                        ? scheme.onPrimaryContainer
                                        : scheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.items[i].label,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: i == _activeIndex
                                          ? FontWeight.w600
                                          : null,
                                      color: i == _activeIndex
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
              );
            },
          );
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
