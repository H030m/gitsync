import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_locale.dart';
import '../../l10n/app_strings.dart';
import '../../services/authentication.dart';
import '../../services/functions_service.dart';
import '../../services/local_notifications.dart';
import '../../services/locale_notifier.dart';
import '../../services/navigation.dart';
import '../../services/theme_mode_notifier.dart';
import '../../theme/app_dimens.dart';
import '../../view_models/auth_vm.dart';
import '../../widgets/section_card.dart';
import '../../widgets/staggered_entry.dart';

// SettingsPage — grouped M3 settings with entrance animations.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.repoId});
  final String repoId;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(s.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppDimens.spacingSm),
        children: [
          StaggeredEntry(
            key: const ValueKey('settings-general'),
            index: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(s.general),
                _GeneralCard(),
              ],
            ),
          ),
          StaggeredEntry(
            key: const ValueKey('settings-notifications'),
            index: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(s.notifications),
                _NotificationsCard(),
              ],
            ),
          ),
          StaggeredEntry(
            key: const ValueKey('settings-github'),
            index: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(s.githubConnection),
                const _GitHubCard(),
              ],
            ),
          ),
          StaggeredEntry(
            key: const ValueKey('settings-account'),
            index: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(s.account),
                const _AccountCard(),
              ],
            ),
          ),
          StaggeredEntry(
            key: const ValueKey('settings-snapshot'),
            index: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(s.snapshotSection),
                _SnapshotCard(repoId: repoId),
              ],
            ),
          ),
          StaggeredEntry(
            key: const ValueKey('settings-danger'),
            index: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(s.dangerZone),
                _DangerZoneCard(repoId: repoId),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.spacingLg),
        ],
      ),
    );
  }
}

// M3-style section header: natural case, onSurfaceVariant, labelLarge.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.spacingMd,
        AppDimens.spacingLg,
        AppDimens.spacingMd,
        AppDimens.spacingSm,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

// Language + Appearance grouped in one card.
class _GeneralCard extends StatelessWidget {
  const _GeneralCard();

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final notifier = context.watch<LocaleNotifier>();
    final themeModeNotifier = context.watch<ThemeModeNotifier>();
    return SectionCard(
      margin: const EdgeInsets.symmetric(horizontal: AppDimens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.language,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppDimens.spacingSm),
          SegmentedButton<AppLocale>(
            segments: const [
              ButtonSegment(value: AppLocale.zhHant, label: Text('中文（繁體）')),
              ButtonSegment(value: AppLocale.en, label: Text('English')),
            ],
            selected: {notifier.locale},
            showSelectedIcon: false,
            onSelectionChanged: (sel) => notifier.setLocale(sel.first),
          ),
          const Divider(height: AppDimens.spacingLg),
          Text(
            s.appearance,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppDimens.spacingSm),
          SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(
                value: ThemeMode.system,
                icon: const Icon(Icons.brightness_auto_outlined),
                label: Text(s.themeSystem),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: const Icon(Icons.light_mode_outlined),
                label: Text(s.themeLight),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: const Icon(Icons.dark_mode_outlined),
                label: Text(s.themeDark),
              ),
            ],
            selected: {themeModeNotifier.mode},
            showSelectedIcon: false,
            onSelectionChanged: (sel) => themeModeNotifier.setMode(sel.first),
          ),
        ],
      ),
    );
  }
}

// Notifications section — single action tile.
class _NotificationsCard extends StatelessWidget {
  const _NotificationsCard();

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return SectionCard(
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.symmetric(horizontal: AppDimens.spacingMd),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        child: ListTile(
          leading: const Icon(Icons.notifications_active_outlined),
          title: Text(s.sendTestNotification),
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              final permitted =
                  await LocalNotificationsService.instance.ensurePermission();
              if (!permitted) {
                messenger.showSnackBar(
                  SnackBar(content: Text(s.notificationsDisabledHint)),
                );
                return;
              }
              await LocalNotificationsService.instance.show(
                title: s.testNotificationTitle,
                body: s.testNotificationBody,
              );
              messenger.showSnackBar(
                SnackBar(content: Text(s.testNotificationSent)),
              );
            } catch (e) {
              messenger.showSnackBar(
                SnackBar(content: Text('${s.notificationFailed}: $e')),
              );
            }
          },
        ),
      ),
    );
  }
}

// GitHub connection — runs OAuth flow to obtain/refresh githubAccessToken.
class _GitHubCard extends StatelessWidget {
  const _GitHubCard();

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final auth = context.watch<AuthViewModel>();
    final busy = auth.isConnectingGitHub;
    return SectionCard(
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.symmetric(horizontal: AppDimens.spacingMd),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        child: ListTile(
          leading: const Icon(Icons.link),
          title: Text(s.connectGitHub),
          subtitle: Text(s.connectGitHubSubtitle),
          trailing: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: busy ? null : () => _connect(context),
        ),
      ),
    );
  }

  Future<void> _connect(BuildContext context) async {
    final s = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final auth = Provider.of<AuthViewModel>(context, listen: false);
    final ok = await auth.connectGitHub();
    if (!context.mounted) return;
    if (ok) {
      messenger.showSnackBar(SnackBar(content: Text(s.githubConnected)));
    } else if (auth.lastError == null) {
      messenger.showSnackBar(SnackBar(content: Text(s.githubConnectCancelled)));
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(s.githubConnectFailed(auth.lastError!))),
      );
    }
  }
}

// Account section — sign-out with confirmation.
class _AccountCard extends StatelessWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.symmetric(horizontal: AppDimens.spacingMd),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        child: ListTile(
          leading: Icon(Icons.logout, color: scheme.error),
          title: Text(s.signOut),
          textColor: scheme.error,
          onTap: () => _confirmSignOut(context),
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final s = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.signOutConfirmTitle),
        content: Text(s.signOutConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.signOut),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!context.mounted) return;
    final nav = Provider.of<NavigationService>(context, listen: false);
    Provider.of<LocaleNotifier>(context, listen: false).detachUser();
    await Provider.of<AuthenticationService>(context, listen: false).logOut();
    nav.goSignIn();
  }
}

// Task snapshot — save the board (tasks + member workload/tags) and restore it
// later so a demo can be re-run from a known-good state.
class _SnapshotCard extends StatelessWidget {
  const _SnapshotCard({required this.repoId});
  final String repoId;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.symmetric(horizontal: AppDimens.spacingMd),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        child: Column(
          children: [
            ListTile(
              leading: Icon(Icons.save_outlined, color: scheme.primary),
              title: Text(s.saveSnapshot),
              subtitle: Text(s.saveSnapshotSubtitle),
              onTap: () => _save(context),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.restore, color: scheme.primary),
              title: Text(s.restoreSnapshot),
              subtitle: Text(s.restoreSnapshotSubtitle),
              onTap: () => _confirmRestore(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    final s = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final functions = Provider.of<FunctionsService>(context, listen: false);
    try {
      final r = await functions.saveTaskSnapshot(repoId: repoId);
      messenger.showSnackBar(
        SnackBar(content: Text(s.saveSnapshotDone(r.taskCount))),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('${s.saveSnapshotFailed}: $e')),
      );
    }
  }

  Future<void> _confirmRestore(BuildContext context) async {
    final s = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final functions = Provider.of<FunctionsService>(context, listen: false);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.restoreSnapshotConfirmTitle),
        content: Text(s.restoreSnapshotConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.restoreSnapshot),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final r = await functions.restoreTaskSnapshot(repoId: repoId);
      messenger.showSnackBar(
        SnackBar(content: Text(s.restoreSnapshotDone(r.restoredTasks))),
      );
    } catch (e) {
      final msg = e.toString().contains('not-found')
          ? s.restoreSnapshotNone
          : '${s.restoreSnapshotFailed}: $e';
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

// Danger zone — irreversible destructive actions only.
class _DangerZoneCard extends StatelessWidget {
  const _DangerZoneCard({required this.repoId});
  final String repoId;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      color: scheme.errorContainer,
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.symmetric(horizontal: AppDimens.spacingMd),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        child: ListTile(
          leading:
              Icon(Icons.delete_sweep_outlined, color: scheme.onErrorContainer),
          title: Text(s.deleteAllTasks),
          subtitle: Text(s.deleteAllTasksSubtitle),
          textColor: scheme.onErrorContainer,
          iconColor: scheme.onErrorContainer,
          onTap: () => _confirmDeleteAllTasks(context),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAllTasks(BuildContext context) async {
    final s = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final functions = Provider.of<FunctionsService>(context, listen: false);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteAllTasksConfirmTitle),
        content: Text(s.deleteAllTasksConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final n = await functions.deleteAllTasks(repoId: repoId);
      messenger.showSnackBar(SnackBar(content: Text(s.deleteAllTasksDone(n))));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('${s.deleteAllTasksFailed}: $e')),
      );
    }
  }
}
