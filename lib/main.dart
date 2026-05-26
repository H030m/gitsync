import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'services/authentication.dart';
import 'services/functions_service.dart';
import 'services/navigation.dart';
import 'services/push_messaging.dart';
import 'services/theme_mode_notifier.dart';
import 'theme/app_theme.dart';
import 'view_models/auth_vm.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const GitSyncApp());
}

class GitSyncApp extends StatelessWidget {
  const GitSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Services (singletons; do not need ChangeNotifier).
        Provider<AuthenticationService>(create: (_) => AuthenticationService()),
        Provider<NavigationService>(create: (_) => NavigationService()),
        Provider<FunctionsService>(create: (_) => FunctionsService()),
        Provider<PushMessagingService>(
          create: (_) => PushMessagingService(),
        ),
        // Global ChangeNotifiers.
        ChangeNotifierProvider<ThemeModeNotifier>(
          create: (_) => ThemeModeNotifier(),
        ),
        ChangeNotifierProvider<AuthViewModel>(create: (_) => AuthViewModel()),
      ],
      child: Consumer<ThemeModeNotifier>(
        builder: (ctx, themeMode, _) {
          final nav = Provider.of<NavigationService>(ctx, listen: false);
          return MaterialApp.router(
            title: 'GitSync',
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: themeMode.mode,
            routerConfig: nav.router,
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}
