// lib/screens/setup_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';
import 'chat_screen.dart';
import '../design/tokens.dart';
import '../widgets/account_form.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});
  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _labelCtrl = TextEditingController();
  final _serverCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  bool _revealed = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _labelCtrl.dispose();
    _serverCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    final server = _serverCtrl.text.trim();
    final token = _tokenCtrl.text.trim();
    if (server.isEmpty || token.isEmpty) {
      setState(() => _error = '服务器地址与 Token 必填');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = await ref.read(chatProvider.notifier).addAccount(
        serverUrl: server, token: token, label: _labelCtrl.text.trim());
    if (!mounted) return;
    if (ok) {
      Navigator.of(context)
          .pushReplacement(MaterialPageRoute(builder: (_) => const ChatScreen()));
    } else {
      setState(() {
        _saving = false;
        _error = '添加失败（已达账户上限 25?）';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Stack(children: [
        // 顶部柔和品牌光晕，给首屏一点氛围而不抢表单注意力。
        Positioned(
          top: -160,
          left: -80,
          right: -80,
          child: IgnorePointer(
            child: Container(
              height: 420,
              decoration: BoxDecoration(
                gradient: RadialGradient(colors: [
                  c.primary.withValues(alpha: isDark ? 0.28 : 0.16),
                  c.primary.withValues(alpha: 0),
                ]),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: c.bubbleMineGradient),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: AppShadows.mine(c.bubbleMineGradient[1]),
                        ),
                        child: const Icon(Icons.smart_toy_rounded,
                            size: 40, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('欢迎使用 Bot助手',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text('连接你的 AstrBot，随时随地对话',
                        style: TextStyle(fontSize: 14, color: c.textSecondary),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 32),
                    AccountFormFields(
                      labelCtrl: _labelCtrl,
                      serverCtrl: _serverCtrl,
                      tokenCtrl: _tokenCtrl,
                      revealed: _revealed,
                      onToggleReveal: () =>
                          setState(() => _revealed = !_revealed),
                      onSubmit: _saving ? null : _onSave,
                    ),
                    if (_error != null) FormErrorText(_error!),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _saving ? null : _onSave,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('开始聊天'),
                    ),
                    const SizedBox(height: 16),
                    Text('需先在 AstrBot 安装 astrbot_plugin_botapi 插件并生成 Token',
                        style: TextStyle(fontSize: 12, color: c.textTertiary),
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
