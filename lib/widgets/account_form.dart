// lib/widgets/account_form.dart
//
// 账户表单三字段（名称 / 服务器地址 / Token），首启页与账户编辑页共用，
// 保证两处的外观、键盘类型与回车跳转一致。
import 'package:flutter/material.dart';

import '../design/tokens.dart';

class AccountFormFields extends StatelessWidget {
  final TextEditingController labelCtrl;
  final TextEditingController serverCtrl;
  final TextEditingController tokenCtrl;
  final bool revealed;
  final VoidCallback onToggleReveal;
  final VoidCallback? onSubmit;

  const AccountFormFields({
    super.key,
    required this.labelCtrl,
    required this.serverCtrl,
    required this.tokenCtrl,
    required this.revealed,
    required this.onToggleReveal,
    this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: labelCtrl,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '名称（可选）',
              hintText: '如：家里的 AstrBot',
              prefixIcon: Icon(Icons.badge_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: serverCtrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '服务器地址',
              hintText: 'https://your-host',
              prefixIcon: Icon(Icons.dns_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: tokenCtrl,
            obscureText: !revealed,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit?.call(),
            decoration: InputDecoration(
              labelText: 'Token',
              prefixIcon: const Icon(Icons.key_rounded, size: 20),
              suffixIcon: IconButton(
                tooltip: revealed ? '隐藏' : '显示',
                icon: Icon(
                    revealed
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20),
                onPressed: onToggleReveal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 表单下方的错误提示行。
class FormErrorText extends StatelessWidget {
  final String message;
  const FormErrorText(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, left: 4),
      child: Row(children: [
        Icon(Icons.error_outline_rounded, size: 16, color: c.error),
        const SizedBox(width: 6),
        Expanded(
            child: Text(message,
                style: TextStyle(color: c.error, fontSize: 13))),
      ]),
    );
  }
}
