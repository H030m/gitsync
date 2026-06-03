import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../services/authentication.dart';
import '../../services/navigation.dart';
import '../../services/theme_mode_notifier.dart';
import '../../theme/app_dimens.dart';

/// SettingsPage — dark-mode toggle, Discord webhook link, sign-out.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.repoId});
  final String repoId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.spacingMd,
          vertical: AppDimens.spacingMd,
        ),
        children: [
          const _BackendBanner(),
          const SizedBox(height: AppDimens.spacingMd),

          // Section: 一般
          const _SectionLabel('一般'),

          // General settings card
          _SettingsCard(
            children: [
              const _DarkModeRow(),
              const _IndentedDivider(),
              const _DiscordRow(),
            ],
          ),
          const SizedBox(height: AppDimens.spacingSm),

          // Section: 帳號
          const _SectionLabel('帳號'),

          // Sign-out card
          const _SettingsCard(
            children: [
              _SignOutRow(),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section label — muted, small, with tracking
// ---------------------------------------------------------------------------
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.spacingSm,
        AppDimens.spacingSm,
        AppDimens.spacingSm,
        AppDimens.spacingXs,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rounded card container for settings rows
// ---------------------------------------------------------------------------
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: brightness == Brightness.dark
            ? const Color(0xFF222630)
            : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        boxShadow: [
          BoxShadow(
            color: brightness == Brightness.dark
                ? Colors.black.withValues(alpha: 0.3)
                : const Color(0xFF1565C0).withValues(alpha: 0.10),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

// ---------------------------------------------------------------------------
// Tonal icon avatar (40x40 circle)
// ---------------------------------------------------------------------------
class _TonalIcon extends StatelessWidget {
  const _TonalIcon({
    required this.icon,
    required this.iconColor,
    this.backgroundColor,
  });

  final IconData icon;
  final Color iconColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: backgroundColor ?? scheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 18, color: iconColor),
    );
  }
}

// ---------------------------------------------------------------------------
// Row: 暗色模式 with Switch.adaptive
// ---------------------------------------------------------------------------
class _DarkModeRow extends StatelessWidget {
  const _DarkModeRow();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = context.watch<ThemeModeNotifier>();
    final isDark = theme.mode == ThemeMode.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          _TonalIcon(icon: Icons.palette, iconColor: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '暗色模式',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface,
                  ),
            ),
          ),
          Switch.adaptive(
            value: isDark,
            activeTrackColor: scheme.primary,
            onChanged: (_) => theme.toggle(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Indented divider
// ---------------------------------------------------------------------------
class _IndentedDivider extends StatelessWidget {
  const _IndentedDivider();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Divider(height: 1, thickness: 0.5, color: scheme.outlineVariant),
    );
  }
}

// ---------------------------------------------------------------------------
// Row: 連結 DC 群組
// ---------------------------------------------------------------------------
class _DiscordRow extends StatelessWidget {
  const _DiscordRow();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () {
        // TODO: implement DC webhook config
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            _TonalIcon(
              icon: Icons.message_outlined,
              iconColor: scheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '連結 DC 群組',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface,
                    ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Row: 登出
// ---------------------------------------------------------------------------
class _SignOutRow extends StatelessWidget {
  const _SignOutRow();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () async {
        await Provider.of<AuthenticationService>(context, listen: false)
            .logOut();
        if (!context.mounted) return;
        Provider.of<NavigationService>(context, listen: false).goSignIn();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            _TonalIcon(
              icon: Icons.logout,
              iconColor: scheme.error,
              backgroundColor: scheme.errorContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '登出',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.error,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Backend banner (dev tool — kept as-is)
// ---------------------------------------------------------------------------
class _BackendBanner extends StatelessWidget {
  const _BackendBanner();

  @override
  Widget build(BuildContext context) {
    final isFake = AppConfig.useFakeBackend;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
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
