import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../services/authentication.dart';
import '../../services/navigation.dart';
import '../../services/theme_mode_notifier.dart';
import '../../theme/app_dimens.dart';

// SettingsPage — theme selector, backend-mode indicator, Discord webhook
// config, sign-out.
// TODO: implement Discord webhook form per prototype `Settings.tsx`.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.repoId});
  final String repoId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Consumer<ThemeModeNotifier>(
        builder: (ctx, theme, _) => ListView(
          padding: const EdgeInsets.symmetric(vertical: AppDimens.spacingSm),
          children: [
            const _BackendBanner(),
            const _SectionLabel('Appearance'),
            const _ThemeSelector(),
            const SizedBox(height: AppDimens.spacingSm),
            const _SectionLabel('Account'),
            ListTile(
              title: const Text('Sign out'),
              leading: Icon(Icons.logout, color: Theme.of(ctx).colorScheme.error),
              textColor: Theme.of(ctx).colorScheme.error,
              iconColor: Theme.of(ctx).colorScheme.error,
              onTap: () async {
                await Provider.of<AuthenticationService>(ctx, listen: false)
                    .logOut();
                if (!ctx.mounted) return;
                Provider.of<NavigationService>(ctx, listen: false).goSignIn();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// Small uppercase section header used to group settings rows.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.spacingMd,
        AppDimens.spacingMd,
        AppDimens.spacingMd,
        AppDimens.spacingSm,
      ),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}

// Three-way System / Light / Dark selector. Showing "System" explicitly is what
// fixes the old mismatch: a binary switch read `mode == dark`, which was false
// under ThemeMode.system, so a dark-browser user saw a dark UI but an "off"
// switch. The segmented control has no such ambiguity.
class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeModeNotifier>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.spacingMd),
      child: SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(
            value: ThemeMode.system,
            icon: Icon(Icons.brightness_auto_outlined),
            label: Text('System'),
          ),
          ButtonSegment(
            value: ThemeMode.light,
            icon: Icon(Icons.light_mode_outlined),
            label: Text('Light'),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            icon: Icon(Icons.dark_mode_outlined),
            label: Text('Dark'),
          ),
        ],
        selected: {theme.mode},
        showSelectedIcon: false,
        onSelectionChanged: (sel) => theme.setMode(sel.first),
      ),
    );
  }
}

class _BackendBanner extends StatelessWidget {
  const _BackendBanner();

  @override
  Widget build(BuildContext context) {
    final isFake = AppConfig.useFakeBackend;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppDimens.spacingMd,
        AppDimens.spacingSm,
        AppDimens.spacingMd,
        0,
      ),
      padding: const EdgeInsets.all(AppDimens.spacingMd),
      decoration: BoxDecoration(
        color: isFake ? scheme.tertiaryContainer : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isFake ? Icons.bug_report : Icons.cloud_done,
                color: isFake
                    ? scheme.onTertiaryContainer
                    : scheme.onPrimaryContainer,
              ),
              const SizedBox(width: 8),
              Text(
                isFake
                    ? 'Backend: FAKE (dummy data)'
                    : 'Backend: LIVE (Firebase)',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: isFake
                          ? scheme.onTertiaryContainer
                          : scheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isFake
                ? 'No real Firebase / OpenAI / GitHub calls. Mutations live '
                    'in memory and reset on restart. To switch: stop the '
                    'app and re-run with `--dart-define=BACKEND=live` (or '
                    'flip AppConfig.defaultBackend).'
                : 'Hitting real Firebase project. Be careful with '
                    'destructive actions.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isFake
                      ? scheme.onTertiaryContainer
                      : scheme.onPrimaryContainer,
                ),
          ),
        ],
      ),
    );
  }
}
