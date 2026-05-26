import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/navigation.dart';
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
          builder: (ctx, vm, _) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('GitSync',
                  style: Theme.of(ctx).textTheme.displaySmall),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: vm.isSigningIn
                    ? null
                    : () async {
                        final ok = await vm.signInWithGitHub();
                        if (!ctx.mounted) return;
                        if (ok) {
                          Provider.of<NavigationService>(ctx, listen: false)
                              .goRepos();
                        }
                      },
                icon: const Icon(Icons.code),
                label: Text(vm.isSigningIn
                    ? 'Signing in…'
                    : 'Sign in with GitHub'),
              ),
              if (vm.lastError != null) ...[
                const SizedBox(height: 16),
                Text(
                  vm.lastError!,
                  style: TextStyle(
                    color: Theme.of(ctx).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
