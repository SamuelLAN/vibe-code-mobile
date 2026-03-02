import 'dart:async';

import 'package:flutter/material.dart';
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
    // 使用系统默认字体，无需网络下载
    return MultiProvider(
      providers: [
        Provider(create: (_) => SettingsService()),
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProxyProvider<AuthService, ChatService>(
          create: (context) => ChatService(
            authService: context.read<AuthService>(),
            settings: context.read<SettingsService>(),
          ),
          update: (context, auth, previous) =>
              previous ??
              ChatService(
                authService: auth,
                settings: context.read<SettingsService>(),
              ),
        ),
        ChangeNotifierProxyProvider2<SettingsService, AuthService, GitService>(
          create: (context) => GitService(
            settings: context.read<SettingsService>(),
            authService: context.read<AuthService>(),
          ),
          update: (context, settings, auth, previous) =>
              previous ??
              GitService(
                settings: settings,
                authService: auth,
              ),
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

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  bool _authReady = false;
  bool _chatReady = false;
  bool _gitReady = false;
  String _bootstrapStep = 'Preparing startup...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshTokenOnResume());
    }
  }

  Future<void> _refreshTokenOnResume() async {
    final auth = context.read<AuthService>();
    await auth.getValidToken();
  }

  Future<void> _bootstrap() async {
    _logStep('App started, preparing initialization');
    final auth = context.read<AuthService>();
    final chatService = context.read<ChatService>();
    final gitService = context.read<GitService>();
    var authReady = false;
    var chatReady = false;
    var gitReady = false;

    try {
      _setBootstrapStep('Initializing auth service...');
      _logStep('Starting auth service initialization');
      await auth.tryAutoLogin();
      _logStep('Auth service initialized');
      authReady = true;

      _setBootstrapStep('Initializing chat and git services...');
      _logStep('Starting chat and git service initialization');
      await Future.wait([
        chatService.initialize(),
        gitService.initialize(),
      ]);
      _logStep('Chat and git services initialized');
      chatReady = true;
      gitReady = true;

      _setBootstrapStep('Initialization complete');
      _logStep('App initialization complete');
    } catch (e, st) {
      _setBootstrapStep('Initialization failed, please try again later');
      _logStep('Initialization exception: $e');
      debugPrint('[AuthGate] bootstrap stacktrace:\n$st');
    } finally {
      if (!mounted) return;
      setState(() {
        _authReady = authReady;
        _chatReady = chatReady;
        _gitReady = gitReady;
      });
    }
  }

  void _setBootstrapStep(String step) {
    if (!mounted) return;
    setState(() {
      _bootstrapStep = step;
    });
  }

  void _logStep(String message) {
    final now = DateTime.now().toIso8601String();
    debugPrint('[AuthGate][$now] $message');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    // 显示骨架屏直到服务准备就绪
    if (!_authReady || !_chatReady || !_gitReady) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo 或应用图标
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.rocket_launch_rounded,
                  size: 40,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              // 应用名称
              Text(
                'Vibe Coding',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 32),
              // 加载指示器
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _bootstrapStep,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade500,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    if (auth.isAuthenticated) {
      return const ChatScreen();
    }

    return const LoginScreen();
  }
}
