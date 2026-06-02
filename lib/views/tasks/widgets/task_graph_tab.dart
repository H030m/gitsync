import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';
import 'package:provider/provider.dart';

import '../../../models/task.dart';
import '../../../services/navigation.dart';
import '../../../view_models/tasks_board_vm.dart';

// Dependency-DAG visualization of a repo's tasks (TasksBoardPage "Graph" tab).
// Nodes = tasks, edges = `dependsOn` (prerequisite -> dependent). Built with the
// `graphview` package using a top-down Sugiyama (layered) layout, wrapped in an
// InteractiveViewer for pan/zoom. See task 06-02-task-graph-view.
class TaskGraphTab extends StatelessWidget {
  const TaskGraphTab({super.key, required this.vm});

  final TasksBoardViewModel vm;

  @override
  Widget build(BuildContext context) {
    final tasks = vm.tasks;
    if (tasks.isEmpty) {
      return Center(
        child: Text(
          'No tasks yet',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    final byId = {for (final t in tasks) t.id: t};

    final graph = Graph();
    // Ensure every task appears as a node even when it has no edges.
    for (final t in tasks) {
      graph.addNode(Node.Id(t.id));
    }
    // Edge prerequisite (depId) -> dependent (t.id); skip dangling references.
    for (final t in tasks) {
      for (final depId in t.dependsOn) {
        if (byId.containsKey(depId)) {
          graph.addEdge(Node.Id(depId), Node.Id(t.id));
        }
      }
    }

    final configuration = SugiyamaConfiguration()
      ..orientation = SugiyamaConfiguration.ORIENTATION_TOP_BOTTOM
      ..nodeSeparation = 24
      ..levelSeparation = 48;

    final edgePaint = Paint()
      ..color = Theme.of(context).colorScheme.outline
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    return InteractiveViewer(
      constrained: false,
      boundaryMargin: const EdgeInsets.all(80),
      minScale: 0.1,
      maxScale: 4,
      child: GraphView(
        graph: graph,
        algorithm: SugiyamaAlgorithm(configuration),
        paint: edgePaint,
        builder: (Node node) {
          final task = byId[node.key!.value];
          if (task == null) return const SizedBox.shrink();
          return _TaskNode(task: task, vm: vm);
        },
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
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (task.status) {
      TaskStatus.todo => (scheme.surfaceContainerHighest, scheme.onSurface),
      TaskStatus.inProgress => (scheme.primaryContainer, scheme.onPrimaryContainer),
      TaskStatus.done => (scheme.secondaryContainer, scheme.onSecondaryContainer),
    };

    return InkWell(
      onTap: () => Provider.of<NavigationService>(context, listen: false)
          .goTaskDetails(vm.repoId, task.id),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 140,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Text(
          task.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: fg, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
