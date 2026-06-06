import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';
import 'package:provider/provider.dart';

import '../../../models/task.dart';
import '../../../services/navigation.dart';
import '../../../theme/app_dimens.dart';
import '../../../view_models/tasks_board_vm.dart';

// Dependency-DAG visualization of a repo's tasks (TasksBoardPage "關聯圖" tab).
// Nodes = tasks, edges = `dependsOn` (prerequisite -> dependent). Built with the
// `graphview` package using a top-down Sugiyama (layered) layout, wrapped in an
// InteractiveViewer for pan/zoom. See task 06-02-task-graph-view.
//
// 06-06 layout polish: keep the top-down Sugiyama orientation but make it read
// cleanly — open level spacing, tighter in-layer gaps, uniform node size, softer
// short edges, a status legend, and a one-time fit-to-view so the whole graph is
// framed on open (the long sweeping edges over empty canvas were the eyesore).
class TaskGraphTab extends StatefulWidget {
  const TaskGraphTab({super.key, required this.vm});

  final TasksBoardViewModel vm;

  @override
  State<TaskGraphTab> createState() => _TaskGraphTabState();
}

class _TaskGraphTabState extends State<TaskGraphTab> {
  final _transform = TransformationController();
  // Key on the laid-out graph so we can measure it and fit it to the viewport.
  final _graphKey = GlobalKey();
  // Fit-to-view runs once per built graph; re-armed when the task set changes.
  bool _fitted = false;
  int _fitSignature = 0;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  // Frame the whole graph in the viewport the first time it lays out: scale to
  // fit (never zoom past 1×) and center. Guarded so it doesn't fight the user's
  // pan/zoom afterwards.
  void _maybeFit(Size viewport) {
    if (_fitted || viewport.isEmpty) return;
    final ctx = _graphKey.currentContext;
    final size = ctx?.size;
    if (size == null || size.width == 0 || size.height == 0) return;
    final scale = math
        .min(viewport.width / size.width, viewport.height / size.height)
        .clamp(0.2, 1.0);
    final dx = (viewport.width - size.width * scale) / 2;
    final dy = (viewport.height - size.height * scale) / 2;
    // viewport = scale * child + translate. Scale on the diagonal, translation
    // in column 3 (translate is not itself scaled, which is what we want).
    _transform.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(2, 2, scale)
      ..setEntry(0, 3, dx < 0 ? 0.0 : dx)
      ..setEntry(1, 3, dy < 0 ? 0.0 : dy);
    _fitted = true;
  }

  @override
  Widget build(BuildContext context) {
    final tasks = widget.vm.tasks;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (tasks.isEmpty) {
      return Center(
        child: Text('No tasks yet', style: theme.textTheme.bodyLarge),
      );
    }

    // Re-arm fit-to-view when the task set changes (add/remove shifts the layout).
    final signature = Object.hashAll(tasks.map((t) => t.id));
    if (signature != _fitSignature) {
      _fitSignature = signature;
      _fitted = false;
    }

    final byId = {for (final t in tasks) t.id: t};

    final graph = Graph();
    for (final t in tasks) {
      graph.addNode(Node.Id(t.id));
    }
    for (final t in tasks) {
      for (final depId in t.dependsOn) {
        if (byId.containsKey(depId)) {
          graph.addEdge(Node.Id(depId), Node.Id(t.id));
        }
      }
    }

    final configuration = SugiyamaConfiguration()
      ..orientation = SugiyamaConfiguration.ORIENTATION_TOP_BOTTOM
      // Tighter within a layer, more breathing room between layers — shortens the
      // long diagonal sweeps and lines siblings up neatly.
      ..nodeSeparation = 24
      ..levelSeparation = 90
      // Shorter, gentler bends than before (was 16) so edges read as quick
      // connectors, not big arcs.
      ..bendPointShape = CurvedBendPointShape(curveLength: 8)
      ..addTriangleToEdge = true;

    // Softer, thinner themed edge so the nodes (not the lines) carry the eye.
    final edgePaint = Paint()
      ..color = scheme.primary.withValues(alpha: 0.4)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _maybeFit(constraints.biggest),
        );
        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _transform,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(200),
                minScale: 0.1,
                maxScale: 4,
                child: GraphView(
                  key: _graphKey,
                  graph: graph,
                  algorithm: SugiyamaAlgorithm(configuration),
                  paint: edgePaint,
                  builder: (Node node) {
                    final task = byId[node.key!.value];
                    if (task == null) return const SizedBox.shrink();
                    return _TaskNode(task: task, vm: widget.vm);
                  },
                ),
              ),
            ),
            // Status legend, pinned (doesn't pan with the canvas).
            Positioned(
              left: AppDimens.spacingSm,
              top: AppDimens.spacingSm,
              child: _StatusLegend(),
            ),
          ],
        );
      },
    );
  }
}

// (bg, fg, accent) palette for a task status — shared by the node + legend.
(Color, Color, Color) _statusColors(ColorScheme scheme, TaskStatus status) {
  return switch (status) {
    TaskStatus.todo => (
        scheme.surfaceContainerHighest,
        scheme.onSurface,
        scheme.outline,
      ),
    TaskStatus.inProgress => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        scheme.primary,
      ),
    TaskStatus.done => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        scheme.secondary,
      ),
  };
}

// Small pinned legend mapping the status dot colors.
class _StatusLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.spacingSm,
        vertical: AppDimens.spacingXs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final status in TaskStatus.values) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _statusColors(scheme, status).$3,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppDimens.spacingXs),
            Text(status.wire, style: theme.textTheme.labelSmall),
            const SizedBox(width: AppDimens.spacingSm),
          ],
        ],
      ),
    );
  }
}

class _TaskNode extends StatelessWidget {
  const _TaskNode({required this.task, required this.vm});

  final Task task;
  final TasksBoardViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (bg, fg, accent) = _statusColors(scheme, task.status);

    return InkWell(
      onTap: () => Provider.of<NavigationService>(context, listen: false)
          .goTaskDetails(vm.repoId, task.id),
      borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      // Uniform node footprint so every layer lines up cleanly regardless of
      // 1- vs 2-line titles.
      child: Container(
        width: 176,
        height: 76,
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.spacingMd,
          vertical: AppDimens.spacingSm,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.10),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: AppDimens.spacingSm),
                Expanded(
                  child: Text(
                    task.status.wire,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: fg.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.spacingXs + 2),
            Expanded(
              child: Text(
                task.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: fg, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
