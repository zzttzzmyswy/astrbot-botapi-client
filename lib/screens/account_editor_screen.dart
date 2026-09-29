// lib/screens/account_editor_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';
import '../util/key_mask.dart';
import '../design/tokens.dart';
import '../widgets/account_form.dart';

/// 添加 / 编辑账户。add 模式 editId=null；edit 模式传已有账户字段。
class AccountEditorScreen extends ConsumerStatefulWidget {
  final String? editId;
  final String? initialLabel;
  final String? initialServerUrl;
  final String? initialToken;
  const AccountEditorScreen({
    super.key,
    this.editId,
    this.initialLabel,
    this.initialServerUrl,
    this.initialToken,
  });
  @override
  ConsumerState<AccountEditorScreen> createState() => _AccountEditorScreenState();
}

class _AccountEditorScreenState extends ConsumerState<AccountEditorScreen> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _serverCtrl;
  late final TextEditingController _tokenCtrl;
  bool _revealed = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.initialLabel ?? '');
    _serverCtrl = TextEditingController(text: widget.initialServerUrl ?? '');
    _tokenCtrl = TextEditingController(text: widget.initialToken ?? '');
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _serverCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.editId != null;

  Future<void> _save() async {
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
    final notifier = ref.read(chatProvider.notifier);
    if (_isEdit) {
      await notifier.updateAccountCredentials(widget.editId!,
          serverUrl: server, token: token);
      await notifier.renameAccount(widget.editId!, _labelCtrl.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } else {
      final ok = await notifier.addAccount(
          serverUrl: server, token: token, label: _labelCtrl.text.trim());
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _saving = false;
          _error = '添加失败（已达账户上限 25?）';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final tokenPreview = (_isEdit && !_revealed && _tokenCtrl.text.isNotEmpty)
        ? maskKey(_tokenCtrl.text)
        : null;
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? '编辑账户' : '添加账户')),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_isEdit ? '修改连接信息后会自动重连' : '添加一个新的 BotAPI 连接',
                  style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
              const SizedBox(height: 16),
              AccountFormFields(
                labelCtrl: _labelCtrl,
                serverCtrl: _serverCtrl,
                tokenCtrl: _tokenCtrl,
                revealed: _revealed,
                onToggleReveal: () => setState(() => _revealed = !_revealed),
                onSubmit: _saving ? null : _save,
              ),
              if (tokenPreview != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 4),
                  child: Text('当前：$tokenPreview',
                      style: TextStyle(fontSize: 12, color: c.textTertiary),
                      overflow: TextOverflow.ellipsis),
                ),
              if (_error != null) FormErrorText(_error!),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_isEdit ? '保存' : '添加'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
