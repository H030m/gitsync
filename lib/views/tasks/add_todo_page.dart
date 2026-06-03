import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/sub_task.dart';
import '../../services/functions_service.dart';
import '../../services/navigation.dart';

// AddTodoPage — 3-step flow (input → AI breakdown → confirm).
// TODO: implement per prototype `tasks/AddTodo.tsx`.
class AddTodoPage extends StatefulWidget {
  const AddTodoPage({super.key, required this.repoId});
  final String repoId;

  @override
  State<AddTodoPage> createState() => _AddTodoPageState();
}

class _AddTodoPageState extends State<AddTodoPage> {
  int _step = 0;
  String _goal = '';
  List<SubTask> _subtasks = const [];
  bool _busy = false;
  String? _error;

  Future<void> _runBreakdown() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final fn = Provider.of<FunctionsService>(context, listen: false);
      final subs = await fn.breakdownTask(repoId: widget.repoId, goal: _goal);
      if (!mounted) return;
      setState(() {
        _subtasks = subs;
        _step = 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新增任務'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _step == 0 ? _inputStep() : _confirmStep(),
      ),
    );
  }

  Widget _inputStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: TextField(
            decoration: const InputDecoration(
              labelText: '專案架構',
              hintText: '輸入專案架構…',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: null,
            minLines: 10,
            keyboardType: TextInputType.multiline,
            onChanged: (v) => setState(() => _goal = v),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy || _goal.trim().isEmpty ? null : _runBreakdown,
          icon: const Icon(Icons.auto_awesome),
          label: Text(_busy ? '生成中…' : '生成 Todos'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!,
              style:
                  TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ],
    );
  }

  Widget _confirmStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('已生成 ${_subtasks.length} 個子任務',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: _subtasks.length,
            itemBuilder: (ctx, i) {
              final s = _subtasks[i];
              return Card(
                child: ListTile(
                  title: Text(s.title),
                  subtitle: Text(s.description),
                  trailing: Text('${s.estimatedHours.toStringAsFixed(1)}h'),
                ),
              );
            },
          ),
        ),
        FilledButton(
          onPressed: () =>
              Provider.of<NavigationService>(context, listen: false)
                  .goTasks(widget.repoId),
          child: const Text('確認並增加 Todos'),
        ),
      ],
    );
  }
}
