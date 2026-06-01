import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/repo.dart';
import '../../services/authentication.dart';
import '../../services/navigation.dart';
import '../../view_models/repo_list_vm.dart';

// RepoListPage — lists every repo the signed-in user is a member of.
// TODO: implement final UI per prototype `RepoList.tsx`.
class RepoListPage extends StatelessWidget {
  const RepoListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthenticationService>(context, listen: false);
    final uid = auth.currentUid;
    if (uid == null) {
      // ShellRoute is supposed to keep us off this page when signed out;
      // fall through to a sign-in prompt just in case.
      return const Scaffold(
        body: Center(child: Text('Not signed in')),
      );
    }

    return ChangeNotifierProvider(
      create: (_) => RepoListViewModel(userId: uid),
      child: Scaffold(
        appBar: AppBar(title: const Text('Your repos')),
        floatingActionButton: FloatingActionButton(
          onPressed: () => Provider.of<NavigationService>(context, listen: false)
              .goAddRepo(),
          child: const Icon(Icons.add),
        ),
        body: Consumer<RepoListViewModel>(
          builder: (ctx, vm, _) {
            if (vm.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (vm.repos.isEmpty) {
              return const Center(child: Text('No repos yet — add one'));
            }
            return ListView.separated(
              itemCount: vm.repos.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final repo = vm.repos[i];
                final removing = vm.isRemoving(repo.id);
                return ListTile(
                  title: Text(repo.name),
                  subtitle: Text(repo.url),
                  onTap: removing
                      ? null
                      : () => Provider.of<NavigationService>(ctx, listen: false)
                          .goTasks(repo.id),
                  trailing: removing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Remove repo',
                          onPressed: () => _confirmRemove(ctx, vm, repo),
                        ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    RepoListViewModel vm,
    Repo repo,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Remove repo?'),
        content: Text(
          'Remove ${repo.name}? This deletes the repo and all its '
          'tasks/data. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(
              'Remove',
              style: TextStyle(
                color: Theme.of(dialogCtx).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    final ok = await vm.removeRepo(repo.id);
    if (ok) return;
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(vm.lastError ?? 'Failed to remove repo'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}
