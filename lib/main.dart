import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'screens/chat_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/chat_service.dart';
import 'services/git_service.dart';
import 'services/settings_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VibeCodingApp());
}

class VibeCodingApp extends StatelessWidget {
  const VibeCodingApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTextTheme = GoogleFonts.manropeTextTheme();
    final displayTextTheme = GoogleFonts.soraTextTheme();

    return MultiProvider(
      providers: [
        Provider(create: (_) => SettingsService()),
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => ChatService()),
        ChangeNotifierProxyProvider<SettingsService, GitService>(
          create: (context) => GitService(settings: context.read<SettingsService>()),
          update: (context, settings, previous) => previous ?? GitService(settings: settings),
        ),
      ],
      child: MaterialApp(
        title: 'Vibe Coding',
        themeMode: ThemeMode.system,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF1F3A5F),
            secondary: Color(0xFF4B8BBE),
            surface: Color(0xFFF6F7FB),
            onSurface: Color(0xFF0F172A),
            error: Color(0xFFB42318),
          ),
          textTheme: baseTextTheme.merge(displayTextTheme),
          scaffoldBackgroundColor: const Color(0xFFF6F7FB),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFF6F7FB),
            elevation: 0,
            centerTitle: true,
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF89B4FA),
            secondary: Color(0xFF74C7EC),
            surface: Color(0xFF0F172A),
            onSurface: Color(0xFFE2E8F0),
            error: Color(0xFFF97066),
          ),
          textTheme: baseTextTheme.merge(displayTextTheme).apply(
                bodyColor: const Color(0xFFE2E8F0),
                displayColor: const Color(0xFFE2E8F0),
              ),
          scaffoldBackgroundColor: const Color(0xFF0B1120),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0B1120),
            elevation: 0,
            centerTitle: true,
          ),
        ),
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthService>();
    await auth.tryAutoLogin();
    if (!mounted) return;
    setState(() {
      _ready = true;
    });
    await context.read<ChatService>().initialize();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (auth.isAuthenticated) {
      return const ChatScreen();
    }

    return const LoginScreen();
  }
}
