import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_strings.dart';
import '../../models/app_user.dart';
import '../../models/member.dart';
import '../../models/task.dart';
import '../../services/functions_service.dart';
import '../../services/navigation.dart';
import '../../theme/app_dimens.dart';
import '../../view_models/graph_edit_ops.dart';
import '../../view_models/members_vm.dart';
import '../../view_models/repo_vm.dart';
import '../../view_models/tasks_board_vm.dart';
import '../../widgets/markdown_view.dart';

// Sentinels returned by the assignee picker: clear the assignee, or trigger a
// GitHub-collaborator import (vs. `null` = dismissed, or a uid = pick that user).
const String _kUnassign = '__unassign__';
const String _kImport = '__import__';

// Full task-detail view: status, assignee (with inline picker), description,
// implementation details (acceptance criteria), subtasks, dependencies, linked
// GitHub issue / PRs, and the AI handoff doc. Reads tasks + member profiles from
// the repo-scoped ViewModels provided by the shell route.
class TaskDetailsPage extends StatefulWidget {
  const TaskDetailsPage({
    super.key,
    required this.repoId,
    required this.taskId,
  });

  final String repoId;
  final String taskId;

  @override
  State<TaskDetailsPage> createState() => _TaskDetailsPageState();
}

class _TaskDetailsPageState extends State<TaskDetailsPage> {
  bool _generatingHandoff = false;
  // Holds the just-generated handoff so the UI reflects it immediately even when
  // the backend doesn't persist it back into the task stream (fake mode).
  String? _localHandoff;

  Future<void> _regenerateHandoff(Task task) async {
    if (_generatingHandoff) return;
    final s = context.l10n;
    final functions = context.read<FunctionsService>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _generatingHandoff = true);
    try {
      final markdown = await functions.generateHandoff(
        repoId: widget.repoId,
        taskId: task.id,
        // W6: regenerate in the app's current language.
        language: s.backendLanguage,
      );
      if (!mounted) return;
      setState(() => _localHandoff = markdown);
    } catch (_) {
      if (!mounted) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(s.couldNotGenerateHandoff)),
        );
    } finally {
      if (mounted) setState(() => _generatingHandoff = false);
    }
  }

  Future<void> _importCollaborators() async {
    final s = context.l10n;
    final functions = context.read<FunctionsService>();
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(s.importingCollaborators)),
      );
    try {
      final r = await functions.importCollaborators(repoId: widget.repoId);
      if (!mounted) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              s.importedSummary(r.added, r.alreadyMembers, r.pending.length),
            ),
          ),
        );
    } catch (_) {
      if (!mounted) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(s.couldNotImport)),
        );
    }
  }

  Future<void> _openUrl(String url) async {
    final s = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(s.couldNotOpenLink)));
    }
  }

  Future<void> _pickAssignee(Task task) async {
    final s = context.l10n;
    final tasksVm = context.read<TasksBoardViewModel>();
    final membersVm = context.read<MembersViewModel>();
    final messenger = ScaffoldMessenger.of(context);

    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _AssigneePicker(
        members: membersVm.members,
        membersVm: membersVm,
        currentAssigneeId: task.assigneeId,
      ),
    );
    if (result == null) return; // dismissed
    if (result == _kImport) {
      await _importCollaborators();
      return;
    }
    final newAssignee = result == _kUnassign ? null : result;
    if (newAssignee == task.assigneeId) return;

    try {
      await tasksVm.assignTo(task.id, newAssignee);
    } catch (_) {
      if (!mounted) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(s.couldNotUpdateAssignee)),
        );
    }
  }

  // Open a scrollable picker of tasks eligible to become a prerequisite of
  // [task] (excludes itself, current prerequisites, and any choice that would
  // create a cycle), then link the picked one.
  Future<void> _addPrerequisite(Task task) async {
    final s = context.l10n;
    final vm = context.read<TasksBoardViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    final deps = {for (final t in vm.tasks) t.id: t.dependsOn};
    final candidates = vm.tasks
        .where((t) =>
            t.id != task.id &&
            !task.dependsOn.contains(t.id) &&
            !wouldCreateCycle(deps, task.id, t.id))
        .toList();
    if (candidates.isEmpty) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(s.noEligibleTasks)),
        );
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _PrereqPicker(candidates: candidates),
    );
    if (picked == null || !mounted) return;
    final ok = await vm.addDependency(task.id, picked);
    if (!mounted || ok) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(s.couldNotAddPrereq)),
      );
  }

  Future<void> _removePrerequisite(Task task, String prereqId) async {
    await context.read<TasksBoardViewModel>().removeDependency(task.id, prereqId);
  }

  Future<void> _deleteCurrentTask() async {
    final s = context.l10n;
    final vm = context.read<TasksBoardViewModel>();
    final nav = context.read<NavigationService>();
    Task? task;
    for (final t in vm.tasks) {
      if (t.id == widget.taskId) {
        task = t;
        break;
      }
    }
    if (task == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteTaskQuestion),
        content: Text(s.deleteTaskBody(task!.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              s.delete,
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await vm.deleteTaskBridging(widget.taskId);
    if (!mounted) return;
    nav.goTasks(widget.repoId);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.taskDetailsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: s.deleteTaskTooltip,
            onPressed: _deleteCurrentTask,
          ),
        ],
      ),
      body: Consumer2<TasksBoardViewModel, MembersViewModel>(
        builder: (ctx, tasksVm, membersVm, _) {
          final task = tasksVm.tasks.firstWhere(
            (t) => t.id == widget.taskId,
            orElse: () =>
                Task(id: widget.taskId, title: '(deleted)', createdBy: ''),
          );
          final theme = Theme.of(ctx);

          final byId = {for (final t in tasksVm.tasks) t.id: t};
          final deps = [
            for (final id in task.dependsOn)
              if (byId[id] != null) byId[id]!,
          ];
          final subtasks = [
            for (final t in tasksVm.tasks)
              if (t.parentTaskId == task.id) t,
          ];
          // A just-regenerated handoff (local) wins over the persisted one so
          // the result shows immediately even when the backend doesn't write it
          // back into the stream (fake mode).
          final handoff = _localHandoff ?? task.handoffDoc;
          // Repo URL (from the shell-scoped RepoViewModel) lets us deep-link the
          // linked GitHub issue / PRs; null/empty → chips stay non-tappable.
          final repoUrl = ctx.watch<RepoViewModel>().repo?.url;
          final hasRepoUrl = repoUrl != null && repoUrl.isNotEmpty;

          return ListView(
            padding: const EdgeInsets.all(AppDimens.spacingMd),
            children: [
              Text(
                task.title,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppDimens.spacingSm),
              _StatusChip(status: task.status),

              // ---- Assignee ----
              const SizedBox(height: AppDimens.spacingLg),
              _SectionTitle(s.assignee),
              const SizedBox(height: AppDimens.spacingSm),
              _AssigneeRow(
                assigneeId: task.assigneeId,
                membersVm: membersVm,
                onEdit: () => _pickAssignee(task),
              ),

              // ---- Description ----
              if (task.description.isNotEmpty) ...[
                const SizedBox(height: AppDimens.spacingLg),
                _SectionTitle(s.descriptionSection),
                const SizedBox(height: AppDimens.spacingSm),
                Text(task.description, style: theme.textTheme.bodyMedium),
              ],

              // ---- Implementation details (acceptance criteria) ----
              if (task.acceptanceCriteria.isNotEmpty) ...[
                const SizedBox(height: AppDimens.spacingLg),
                _SectionTitle(s.implementationDetails),
                const SizedBox(height: AppDimens.spacingSm),
                for (final c in task.acceptanceCriteria)
                  Padding(
                    padding:
                        const EdgeInsets.only(bottom: AppDimens.spacingXs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.check_box_outline_blank,
                          size: 18,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(width: AppDimens.spacingSm),
                        Expanded(
                          child: Text(c, style: theme.textTheme.bodyMedium),
                        ),
                      ],
                    ),
                  ),
              ],

              // ---- Subtasks ----
              if (subtasks.isNotEmpty) ...[
                const SizedBox(height: AppDimens.spacingLg),
                _SectionTitle(s.subtasks),
                const SizedBox(height: AppDimens.spacingSm),
                for (final t in subtasks)
                  _TaskRefTile(repoId: widget.repoId, task: t),
              ],

              // ---- Dependencies (parents) ----
              const SizedBox(height: AppDimens.spacingLg),
              Row(
                children: [
                  Expanded(child: _SectionTitle(s.dependsOn)),
                  TextButton.icon(
                    onPressed: () => _addPrerequisite(task),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(s.add),
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.spacingSm),
              if (deps.isEmpty)
                Text(
                  s.noPrerequisites,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                )
              else
                for (final t in deps)
                  _TaskRefTile(
                    repoId: widget.repoId,
                    task: t,
                    onRemove: () => _removePrerequisite(task, t.id),
                  ),

              // ---- GitHub links ----
              if (task.githubIssueNumber != null ||
                  task.linkedPRNumbers.isNotEmpty) ...[
                const SizedBox(height: AppDimens.spacingLg),
                _SectionTitle('GitHub'),
                const SizedBox(height: AppDimens.spacingSm),
                Wrap(
                  spacing: AppDimens.spacingSm,
                  runSpacing: AppDimens.spacingSm,
                  children: [
                    if (task.githubIssueNumber != null)
                      _RefChip(
                        icon: Icons.adjust,
                        label: 'Issue #${task.githubIssueNumber}',
                        onTap: hasRepoUrl
                            ? () => _openUrl(
                                '$repoUrl/issues/${task.githubIssueNumber}')
                            : null,
                      ),
                    for (final pr in task.linkedPRNumbers)
                      _RefChip(
                        icon: Icons.merge,
                        label: 'PR #$pr',
                        onTap:
                            hasRepoUrl ? () => _openUrl('$repoUrl/pull/$pr') : null,
                      ),
                  ],
                ),
              ],

              // ---- Handoff doc ----
              const SizedBox(height: AppDimens.spacingLg),
              Row(
                children: [
                  Expanded(child: _SectionTitle(s.handoff)),
                  TextButton.icon(
                    onPressed:
                        _generatingHandoff ? null : () => _regenerateHandoff(task),
                    icon: _generatingHandoff
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome, size: 18),
                    label: Text(
                      handoff == null ? s.generate : s.regenerate,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.spacingSm),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(AppDimens.spacingMd),
                  child: handoff == null
                      ? Text(
                          s.noHandoffYet,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      : MarkdownView(data: handoff),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Status pill, shared by the header + task-reference tiles.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final TaskStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (bg, fg) = switch (status) {
      TaskStatus.todo => (scheme.surfaceContainerHighest, scheme.onSurface),
      TaskStatus.inProgress => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
        ),
      TaskStatus.done => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.spacingMd,
        vertical: AppDimens.spacingSm - 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
      ),
      child: Text(
        status.wire,
        style: theme.textTheme.labelMedium
            ?.copyWith(color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// Current assignee with an avatar + label and an edit affordance that opens the
// picker. Falls back to "Unassigned" when no one is assigned.
class _AssigneeRow extends StatelessWidget {
  const _AssigneeRow({
    required this.assigneeId,
    required this.membersVm,
    required this.onEdit,
  });

  final String? assigneeId;
  final MembersViewModel membersVm;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final id = assigneeId;
    final profile = id == null ? null : membersVm.profileFor(id);
    final label = id == null ? s.unassigned : membersVm.labelFor(id);

    return Row(
      children: [
        _Avatar(user: profile, fallbackSeed: id),
        const SizedBox(width: AppDimens.spacingSm),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: id == null ? scheme.onSurfaceVariant : null,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.person_outline, size: 18),
          label: Text(id == null ? s.assign : s.change),
        ),
      ],
    );
  }
}

// Bottom-sheet body listing repo members + an "Unassign" option. Pops the
// selected uid (or [_kUnassign]).
class _AssigneePicker extends StatelessWidget {
  const _AssigneePicker({
    required this.members,
    required this.membersVm,
    required this.currentAssigneeId,
  });

  final List<Member> members;
  final MembersViewModel membersVm;
  final String? currentAssigneeId;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: AppDimens.spacingMd),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.spacingMd,
              0,
              AppDimens.spacingMd,
              AppDimens.spacingSm,
            ),
            child: Text(
              s.assignToTitle,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          for (final m in members)
            ListTile(
              leading: _Avatar(
                user: membersVm.profileFor(m.userId),
                fallbackSeed: m.userId,
              ),
              title: Text(membersVm.labelFor(m.userId)),
              subtitle: Text(m.role.wire),
              trailing: m.userId == currentAssigneeId
                  ? Icon(Icons.check, color: theme.colorScheme.primary)
                  : null,
              onTap: () => Navigator.of(context).pop(m.userId),
            ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.person_off_outlined),
            title: Text(s.unassign),
            enabled: currentAssigneeId != null,
            onTap: () => Navigator.of(context).pop(_kUnassign),
          ),
          ListTile(
            leading: const Icon(Icons.group_add_outlined),
            title: Text(s.importCollaborators),
            subtitle: Text(s.importCollaboratorsSub),
            onTap: () => Navigator.of(context).pop(_kImport),
          ),
        ],
      ),
    );
  }
}

// Round avatar from the user's photo URL, falling back to an initial derived
// from the label / uid.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.user, this.fallbackSeed});
  final AppUser? user;
  final String? fallbackSeed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = user?.avatarUrl;
    final seed = (user?.githubLogin.isNotEmpty ?? false)
        ? user!.githubLogin
        : (user?.name.isNotEmpty ?? false)
            ? user!.name
            : (fallbackSeed ?? '?');
    return CircleAvatar(
      radius: 16,
      backgroundColor: scheme.primaryContainer,
      foregroundImage:
          (url != null && url.isNotEmpty) ? NetworkImage(url) : null,
      child: Text(
        seed.isNotEmpty ? seed.characters.first.toUpperCase() : '?',
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// A tappable row for a related task (subtask / dependency): title + status,
// navigates to that task's detail page.
class _TaskRefTile extends StatelessWidget {
  const _TaskRefTile({
    required this.repoId,
    required this.task,
    this.onRemove,
  });
  final String repoId;
  final Task task;
  // When set, shows a ✕ to unlink this prerequisite.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return Card(
      margin: const EdgeInsets.only(bottom: AppDimens.spacingSm),
      child: ListTile(
        title: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatusChip(status: task.status),
            if (onRemove != null)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: s.removePrerequisite,
                onPressed: onRemove,
              ),
          ],
        ),
        onTap: () => Provider.of<NavigationService>(context, listen: false)
            .goTaskDetails(repoId, task.id),
      ),
    );
  }
}

// Scrollable bottom-sheet picker of tasks that can become a prerequisite.
class _PrereqPicker extends StatelessWidget {
  const _PrereqPicker({required this.candidates});
  final List<Task> candidates;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.spacingMd,
              0,
              AppDimens.spacingMd,
              AppDimens.spacingSm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                s.addPrerequisite,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: candidates.length,
              itemBuilder: (ctx, i) {
                final t = candidates[i];
                return ListTile(
                  leading: _StatusChip(status: t.status),
                  title:
                      Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.of(ctx).pop(t.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Small outlined chip for a GitHub issue / PR reference. Tappable (opens the
// GitHub URL) when [onTap] is provided; otherwise a plain, non-interactive chip.
class _RefChip extends StatelessWidget {
  const _RefChip({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final avatar = Icon(icon, size: 16, color: scheme.primary);
    final side = BorderSide(color: scheme.outlineVariant);
    if (onTap == null) {
      return Chip(avatar: avatar, label: Text(label), side: side);
    }
    return ActionChip(
      avatar: avatar,
      label: Text(label),
      side: side,
      onPressed: onTap,
    );
  }
}

// Small uppercase label that heads a section of the task detail view.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
    );
  }
}
