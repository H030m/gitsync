import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/navigation.dart';

// NotifyScreen — landing page when the user taps an FCM notification.
// TODO: parse the payload and forward to the matching task / daily route.
class NotifyScreen extends StatelessWidget {
  const NotifyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notification')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.notifications, size: 64),
            const SizedBox(height: 16),
            const Text('Opened from a push notification.'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () =>
                  Provider.of<NavigationService>(context, listen: false)
                      .goRepos(),
              child: const Text('Back to repos'),
            ),
          ],
        ),
      ),
    );
  }
}
