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
          create: (context) => ChatService(authService: context.read<AuthService>()),
          update: (context, auth, previous) => previous ?? ChatService(authService: auth),
        ),
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

class _AuthGateState extends State<AuthGate> {
  bool _authReady = false;
  bool _chatReady = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // 并行初始化认证和聊天服务
    final auth = context.read<AuthService>();
    final chatService = context.read<ChatService>();

    // 同时启动两个初始化任务
    await Future.wait([
      auth.tryAutoLogin(),
      chatService.initialize(),
    ]);

    if (!mounted) return;

    setState(() {
      _authReady = true;
      _chatReady = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    // 显示骨架屏直到服务准备就绪
    if (!_authReady || !_chatReady) {
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
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
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
