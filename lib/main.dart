import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/config_service.dart';
import 'services/botapi_http.dart';
import 'services/cache_service.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'config/app_config.dart';
import 'design/theme.dart';
import 'screens/chat_screen.dart';
import 'screens/setup_screen.dart';
import 'providers/config_provider.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) {
  return ref.read(configServiceProvider).themeMode;
});

final ThemeData _lightTheme = buildAppTheme(Brightness.light);
final ThemeData _darkTheme = buildAppTheme(Brightness.dark);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 沉浸式：内容绘制到状态栏/导航栏下方，由 AppBar / SafeArea 让位。否则
  // 状态栏区域是窗口底色（黑），浅色主题下深色状态栏图标看不见。
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));
  // Android only: sqflite uses native factory, no FFI init needed.
  final config = ConfigService();
  await config.init();
  try {
    await CacheService().wipeIfFlagged(config.prefs);
  } catch (_) {}
  runApp(ProviderScope(overrides: [
    configServiceProvider.overrideWithValue(config),
  ], child: const AstrBotApp()));
  Future.microtask(() async {
    try {
      await BotApiHttp.cleanOldCache();
    } catch (_) {}
  });
}

class AstrBotApp extends ConsumerWidget {
  const AstrBotApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncConfig = ref.watch(configInitializedProvider);
    final themeMode = ref.watch(themeModeProvider);

    ErrorWidget.builder = (details) => Container(
        color: const Color(0xFF17171E),
        child: SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: SelectableText('${details.exception}',
                    style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 14,
                        fontFamily: 'monospace')))));

    final app = MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: themeMode,
      home: asyncConfig.when(
        data: (isConfigured) =>
            isConfigured ? const ChatScreen() : const SetupScreen(),
        loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator())),
        error: (_, __) => const SetupScreen(),
      ),
    );
    return WithForegroundTask(child: app);
  }
}
