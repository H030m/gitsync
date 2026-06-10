import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/navigation.dart';
import '../../theme/app_dimens.dart';
import '../../view_models/auth_vm.dart';

// SignInPage — GitHub OAuth sign-in entry point.
// TODO: implement final UI per prototype `references/GitSync/src/app/pages/SignIn.tsx`.
class SignInPage extends StatelessWidget {
  const SignInPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Consumer<AuthViewModel>(
          builder: (ctx, vm, _) {
            final theme = Theme.of(ctx);
            final scheme = theme.colorScheme;
            return ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.all(AppDimens.spacingLg),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                      ),
                      child: Icon(
                        Icons.sync_alt,
                        size: 44,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: AppDimens.spacingLg),
                    Text(
                      'GitSync',
                      style: theme.textTheme.displaySmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppDimens.spacingSm),
                    Text(
                      'Your team\'s repos, tasks, and daily activity in one place.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: AppDimens.spacingLg + AppDimens.spacingSm),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: vm.isSigningIn
                            ? null
                            : () async {
                                final ok = await vm.signInWithGitHub();
                                if (!ctx.mounted) return;
                                if (ok) {
                                  Provider.of<NavigationService>(ctx,
                                          listen: false)
                                      .goRepos();
                                }
                              },
                        icon: vm.isSigningIn
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.code),
                        label: Text(vm.isSigningIn
                            ? 'Signing in…'
                            : 'Sign in with GitHub'),
                      ),
                    ),
                    if (vm.lastError != null) ...[
                      const SizedBox(height: AppDimens.spacingMd),
                      Text(
                        vm.lastError!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.error),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
