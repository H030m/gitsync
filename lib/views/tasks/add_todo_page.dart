import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import '../../models/sub_task.dart';
import '../../models/task.dart';
import '../../services/authentication.dart';
import '../../services/functions_service.dart';
import '../../services/navigation.dart';
import '../../theme/app_dimens.dart';
import '../../view_models/tasks_board_vm.dart';

// How a task gets created: by hand (one task) or by AI breakdown (spec → list).
enum _AddMode { manual, ai }

// AddTodoPage — create a task manually, or paste a spec and let the AI break it
// into a task list. Manual is the default so adding a single task doesn't require
// going through the AI flow.
class AddTodoPage extends StatefulWidget {
  const AddTodoPage({super.key, required this.repoId});
  final String repoId;

  @override
  State<AddTodoPage> createState() => _AddTodoPageState();
}

class _AddTodoPageState extends State<AddTodoPage> {
  _AddMode _mode = _AddMode.manual;

  // Manual mode.
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  // AI mode.
  int _step = 0;
  String _goal = '';
  List<SubTask> _subtasks = const [];

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _addManual() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty || _busy) return;
    final vm = Provider.of<TasksBoardViewModel>(context, listen: false);
    final nav = Provider.of<NavigationService>(context, listen: false);
    final uid =
        Provider.of<AuthenticationService>(context, listen: false).currentUid;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await vm.addTask(Task(
        id: '',
        title: title,
        description: _descCtrl.text.trim(),
        createdBy: uid ?? '',
      ));
      if (!mounted) return;
      nav.goTasks(widget.repoId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runBreakdown() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final fn = Provider.of<FunctionsService>(context, listen: false);
      // W6: generate the tasks in the app's current language.
      final subs = await fn.breakdownTask(
        repoId: widget.repoId,
        goal: _goal,
        language: context.l10n.backendLanguage,
      );
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
    final s = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(s.addTaskTitle)),
      body: Padding(
        padding: const EdgeInsets.all(AppDimens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Only offer the mode switch before the AI flow has produced a
            // result (the confirm step is its own screen).
            if (!(_mode == _AddMode.ai && _step == 1)) ...[
              Center(
                child: SegmentedButton<_AddMode>(
                  segments: [
                    ButtonSegment(
                      value: _AddMode.manual,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(s.manual),
                    ),
                    ButtonSegment(
                      value: _AddMode.ai,
                      icon: const Icon(Icons.auto_awesome),
                      label: Text(s.aiBreakdown),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: _busy
                      ? null
                      : (s) => setState(() {
                            _mode = s.first;
                            _error = null;
                          }),
                ),
              ),
              const SizedBox(height: AppDimens.spacingMd),
            ],
            Expanded(
              child: switch (_mode) {
                _AddMode.manual => _manualView(),
                _AddMode.ai => _step == 0 ? _inputStep() : _confirmStep(),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _manualView() {
    final s = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _titleCtrl,
          autofocus: true,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: s.taskTitleLabel,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}), // refresh submit-enabled state
        ),
        const SizedBox(height: AppDimens.spacingMd),
        TextField(
          controller: _descCtrl,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            labelText: s.descriptionOptional,
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: AppDimens.spacingMd),
        FilledButton.icon(
          onPressed:
              _busy || _titleCtrl.text.trim().isEmpty ? null : _addManual,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add),
          label: Text(_busy ? s.addingTask : s.addTaskTitle),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppDimens.spacingMd),
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ],
    );
  }

  Widget _inputStep() {
    final s = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: TextField(
            decoration: InputDecoration(
              labelText: s.projectSpec,
              hintText: s.projectSpecHint,
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: null,
            minLines: 10,
            keyboardType: TextInputType.multiline,
            onChanged: (v) => setState(() => _goal = v),
          ),
        ),
        const SizedBox(height: AppDimens.spacingMd),
        FilledButton.icon(
          onPressed: _busy || _goal.trim().isEmpty ? null : _runBreakdown,
          icon: const Icon(Icons.auto_awesome),
          label: Text(_busy ? s.breakingDown : s.breakDownWithAI),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppDimens.spacingMd),
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ],
    );
  }

  Widget _confirmStep() {
    final s = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.generatedNSubtasks(_subtasks.length),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppDimens.spacingSm),
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
          child: Text(s.done),
        ),
      ],
    );
  }
}
