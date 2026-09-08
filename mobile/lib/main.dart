import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'state/aws_settings.dart';
import 'state/session.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UplinkApp());
}

class UplinkApp extends StatelessWidget {
  const UplinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SessionController()..load()),
        ChangeNotifierProvider(create: (_) => AwsSettings()..load()),
      ],
      child: MaterialApp(
        title: 'Uplink',
        debugShowCheckedModeBanner: false,
        theme: buildPilotTheme(),
        home: const _Gate(),
      ),
    );
  }
}

class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    if (!session.ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return session.isLoggedIn ? const HomeScreen() : const LoginScreen();
  }
}
