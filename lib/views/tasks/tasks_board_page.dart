import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/task.dart';
import '../../services/navigation.dart';
import '../../view_models/tasks_board_vm.dart';
import 'widgets/task_graph_tab.dart';

// TasksBoardPage — kanban + relation-graph tabs.
// TODO: implement drag-and-drop kanban + relation graph per prototype
// `tasks/TasksBoard.tsx`.
class TasksBoardPage extends StatelessWidget {
  const TasksBoardPage({super.key, required this.repoId});
  final String repoId;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tasks'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.view_kanban), text: 'Board'),
              Tab(icon: Icon(Icons.account_tree), text: 'Graph'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () =>
              Provider.of<NavigationService>(context, listen: false)
                  .goAddTodo(repoId),
          child: const Icon(Icons.add),
        ),
        body: Consumer<TasksBoardViewModel>(
          builder: (ctx, vm, _) {
            if (vm.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            return TabBarView(
              children: [
                _BoardTab(vm: vm),
                TaskGraphTab(vm: vm),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BoardTab extends StatelessWidget {
  const _BoardTab({required this.vm});
  final TasksBoardViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _Column(title: 'To do', tasks: vm.todo)),
        Expanded(child: _Column(title: 'In progress', tasks: vm.inProgress)),
        Expanded(child: _Column(title: 'Done', tasks: vm.done)),
      ],
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.title, required this.tasks});
  final String title;
  final List<Task> tasks;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (ctx, i) {
              final t = tasks[i];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  title: Text(t.title),
                  subtitle:
                      t.description.isEmpty ? null : Text(t.description),
                  onTap: () => Provider.of<NavigationService>(ctx, listen: false)
                      .goTaskDetails(
                          Provider.of<TasksBoardViewModel>(ctx, listen: false)
                              .repoId,
                          t.id),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
