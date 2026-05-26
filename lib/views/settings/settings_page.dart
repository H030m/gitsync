import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../services/authentication.dart';
import '../../services/navigation.dart';
import '../../services/theme_mode_notifier.dart';

// SettingsPage — theme toggle, backend-mode indicator, Discord webhook
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
          children: [
            const _BackendBanner(),
            SwitchListTile(
              title: const Text('Dark mode'),
              value: theme.mode == ThemeMode.dark,
              onChanged: (v) =>
                  theme.setMode(v ? ThemeMode.dark : ThemeMode.light),
            ),
            const Divider(),
            ListTile(
              title: const Text('Sign out'),
              leading: const Icon(Icons.logout),
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

class _BackendBanner extends StatelessWidget {
  const _BackendBanner();

  @override
  Widget build(BuildContext context) {
    final isFake = AppConfig.useFakeBackend;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: isFake
          ? scheme.tertiaryContainer
          : scheme.primaryContainer,
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
