import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/authentication.dart';
import '../../services/navigation.dart';
import '../../services/theme_mode_notifier.dart';

// SettingsPage — theme toggle, Discord webhook config, sign-out.
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
