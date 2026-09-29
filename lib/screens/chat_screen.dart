import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import '../design/tokens.dart';
import '../providers/audio_provider.dart';
import '../providers/chat_provider.dart';
import '../services/audio_playback_service.dart';
import '../services/audio_service.dart';
import '../providers/platform_providers.dart';
import '../models/botapi_event.dart';
import '../models/message.dart';
import '../util/mime.dart';
import '../widgets/attachment_panel.dart';
import '../widgets/account_drawer.dart';
import '../services/account_store.dart' show kNoAccount;
import 'account_editor_screen.dart';
import 'chat/app_bar.dart';
import 'chat/input_bar.dart';
import 'chat/voice_overlay.dart';
import 'chat/scroll_thumb.dart';
import 'chat/date_divider.dart';
import 'chat/slash_suggestion.dart';
import 'chat/bubbles/message_bubble.dart';
import 'chat/message_grouping.dart';
import 'chat/bubbles/streaming_bubble.dart';
import 'chat/bubbles/thinking_block.dart';
import 'chat/bubbles/tool_status.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scrollCtrl = ScrollController();
  final _inputCtrl = TextEditingController();
  final _focusNode = FocusNode();
  ChatState _state = const ChatState();

  static const List<SlashCommand> _slashCommands = [
    SlashCommand('/provider', '显示、切换后端大模型供应商'),
    SlashCommand('/reset', '清空会话上下文'),
    SlashCommand('/help', '显示详细的帮助指令'),
  ];

  List<SlashCommand> get _slashMatches {
    final t = _inputCtrl.text;
    if (!t.startsWith('/') || t.contains(' ')) return const [];
    return _slashCommands.where((c) => c.cmd.startsWith(t)).toList();
  }

  void _pickSlashCommand(String cmd) {
    _inputCtrl.text = cmd;
    _inputCtrl.selection = TextSelection.collapsed(offset: cmd.length);
    _focusNode.requestFocus();
  }

  double _w = 360;
  int _lastLen = 0;
  ConnState _lastConn = ConnState.disconnected;
  List<LocalMessage> _lastMessages = const [];
  bool _initSync = true;
  bool _atBottom = true;
  bool _showAttach = false;
  bool _pinBottomOnResize = false;
  bool _loadingMore = false;
  bool _noMoreHistory = false;
  bool _firstLoad = true;
  bool _streamingActive = false;
  bool _streamingThinkingActive = false;
  bool _loadingHistory = false;
  double _preLoadPixels = 0;
  double _preLoadMaxExtent = 0;
  bool _scrollBarVisible = false;
  bool _draggingThumb = false;
  double _scrollFraction = 0;
  Timer? _scrollBarHideTimer;
  double _bottomPad = 0;
  bool _isDark = false;

  // Voice recording state
  bool _recording = false;
  double _recAmplitude = 0;
  bool _recCancel = false;
  late final AudioService _audioService;
  StreamSubscription<Amplitude>? _recSub;

  @override
  void initState() {
    super.initState();
    _audioService = AudioService(ref.read(permissionProvider));
    _scrollCtrl.addListener(() {
      if (!_scrollCtrl.hasClients) return;
      final pos = _scrollCtrl.position;
      final at = pos.pixels >= pos.maxScrollExtent - 100;
      if (at != _atBottom) setState(() => _atBottom = at);
      _onUserScroll();
    });
    _inputCtrl.addListener(() => setState(() {}));
    Future.microtask(() {
      ref.read(chatProvider.notifier).connect();
      ref
          .read(chatProvider.notifier)
          .attachPlayback(ref.read(audioPlaybackProvider.notifier));
      () async {
        final ka = ref.read(keepAliveProvider);
        await ka.init();
        await ka.start();
      }();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bottomPad = MediaQuery.of(context).padding.bottom;
    _isDark = Theme.of(context).brightness == Brightness.dark;
  }

  @override
  Widget build(BuildContext context) {
    final viewBottom = MediaQuery.of(context).viewInsets.bottom;
    if (viewBottom > 0 && _atBottom && _scrollCtrl.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients &&
            _scrollCtrl.position.maxScrollExtent > 0) {
          _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
        }
      });
    }

    if (_initSync) {
      _initSync = false;
      final s = ref.read(chatProvider);
      _state = s;
      _lastLen = s.messages.length;
      _lastConn = s.connectionState;
      _lastMessages = s.messages;
      _streamingActive = s.streamingText != null;
      _streamingThinkingActive = s.streamingThinking != null;
    }
    ref.listen(chatProvider, (_, n) {
      final streamingToggled =
          (n.streamingText != null) != _streamingActive;
      final thinkingToggled =
          (n.streamingThinking != null) != _streamingThinkingActive;
      final needsRebuild = n.messages.length != _lastLen ||
          n.connectionState != _lastConn ||
          n.errorMessage != _state.errorMessage ||
          n.autoPlayVoice != _state.autoPlayVoice ||
          n.currentAccountName != _state.currentAccountName ||
          streamingToggled ||
          thinkingToggled ||
          !identical(n.messages, _lastMessages);

      final prevLen = _lastLen;
      _streamingActive = n.streamingText != null;
      _streamingThinkingActive = n.streamingThinking != null;
      _lastConn = n.connectionState;
      _lastMessages = n.messages;
      if (n.messages.length < _lastLen) _noMoreHistory = false;
      _lastLen = n.messages.length;

      if (!needsRebuild) {
        _state = n;
        return;
      }

      final wasAtBottom = _atBottom;
      final isFirst = _firstLoad && n.messages.isNotEmpty;
      final grew = n.messages.length > prevLen;
      final historyLoad = _loadingHistory && grew;
      if (_firstLoad && n.messages.isNotEmpty) _firstLoad = false;
      _state = n;
      setState(() {});
      if (historyLoad) {
        _loadingHistory = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrollCtrl.hasClients) return;
          final maxExtent = _scrollCtrl.position.maxScrollExtent;
          final target = (_preLoadPixels + (maxExtent - _preLoadMaxExtent))
              .clamp(0.0, maxExtent);
          _scrollCtrl.jumpTo(target);
        });
      } else if (isFirst || grew || (wasAtBottom && n.streamingText != null)) {
        if (isFirst) {
          _settleToBottom();
        } else {
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => _scrollToEnd(jump: grew));
        }
      }
    });

    final w = MediaQuery.of(context).size.width;
    _w = w;
    final isDark = _isDark;
    final conn = _state.connectionState == ConnState.connected;
    final n = _itemCount();
    final noAccount = _state.currentAccountId == kNoAccount;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      drawer: const AccountDrawer(),
      backgroundColor: AppColors.forDark(isDark).background,
      appBar: ChatAppBar(
        connected: conn,
        isDark: isDark,
        error: _state.errorMessage,
        accountName: _state.currentAccountName,
        sessionName: _state.currentSessionName,
        streaming: _state.streamingText?.isNotEmpty == true,
        reconnecting: _state.connectionState == ConnState.reconnecting,
        autoPlay: _state.autoPlayVoice,
        onToggleAutoPlay: () => ref
            .read(chatProvider.notifier)
            .setAutoPlayVoice(!_state.autoPlayVoice),
      ),
      body: Column(children: [
        AnimatedSize(
          duration: AppMotion.normal,
          curve: AppMotion.curve,
          child: (_state.connectionState == ConnState.disconnected &&
                  _state.errorMessage != null &&
                  !noAccount)
              ? _ConnBanner(
                  isDark: isDark,
                  message: _state.errorMessage!,
                  onRetry: () => ref.read(chatProvider.notifier).connect())
              : const SizedBox(width: double.infinity),
        ),
        Expanded(
            child: noAccount
                ? _NoAccount(isDark: isDark, onAdd: _addAccount)
                : n == 0
                ? _EmptyChat(
                    isDark: isDark,
                    accountName: _state.currentAccountName,
                    sessionName: _state.currentSessionName,
                    commands: _slashCommands,
                    onPick: _pickSlashCommand)
                : Stack(children: [
                    NotificationListener<ScrollMetricsNotification>(
                      onNotification: (_) {
                        if (_pinBottomOnResize && _scrollCtrl.hasClients) {
                          final pos = _scrollCtrl.position;
                          if (pos.maxScrollExtent > 0) {
                            _scrollCtrl.jumpTo(pos.maxScrollExtent);
                          }
                        }
                        return false;
                      },
                      child: NotificationListener<ScrollEndNotification>(
                        onNotification: (_) {
                          _maybeLoadMore();
                          return false;
                        },
                        child: CustomScrollView(
                          controller: _scrollCtrl,
                          physics: const BouncingScrollPhysics(),
                          slivers: [
                            if (_loadingMore)
                              const SliverToBoxAdapter(
                                  child: SizedBox(
                                      height: 36,
                                      child: Center(
                                          child: SizedBox(
                                              width: 20,
                                              height: 20,
                                              child:
                                                  CircularProgressIndicator(
                                                      strokeWidth: 2))))),
                            const SliverPadding(
                                padding: EdgeInsets.only(top: 12)),
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (ctx, i) =>
                                    RepaintBoundary(child: _item(i)),
                                childCount: n,
                              ),
                            ),
                            SliverPadding(
                                padding: EdgeInsets.only(
                                    bottom: 16 + _bottomPad)),
                          ],
                        ),
                      ),
                    ),
                    if (!_atBottom && n > 0)
                      Positioned(
                          right: 14,
                          bottom: 12,
                          child: _FAB(
                              isDark: isDark,
                              onTap: _jumpToBottom)),
                    if (n > 0 && (_scrollBarVisible || _draggingThumb))
                      ScrollThumbOverlay(
                        fraction: _scrollFraction,
                        isDark: isDark,
                        dateLabel: _dateAtFraction(),
                        showDate: _draggingThumb,
                        onDrag: _onThumbDrag,
                        onDragEnd: _onThumbDragEnd,
                      ),
                  ])),
        if (_recording)
          VoiceOverlay(
              amplitude: _recAmplitude,
              isCancel: _recCancel,
              isDark: isDark),
        AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _showAttach
                ? AttachmentPanel(
                    onClose: () => setState(() => _showAttach = false),
                    onPickImage: _sendImage,
                    onPickFile: _sendFile,
                  )
                : const SizedBox.shrink()),
        ChatInputBar(
          send: _send,
          controller: _inputCtrl,
          focusNode: _focusNode,
          isDark: isDark,
          hasText: _inputCtrl.text.trim().isNotEmpty,
          attachOpen: _showAttach,
          showAttachment: _toggleAttach,
          slashMatches: _slashMatches,
          onPickSlash: _pickSlashCommand,
          onVoiceStart: _startVoice,
          onVoiceMove: _voiceMove,
          onVoiceEnd: _endVoice,
          onVoiceCancel: _cancelVoiceGesture,
        ),
      ]),
    );
  }

  void _scrollToEnd({bool jump = false}) {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.maxScrollExtent <= 0) return;
    if (jump) {
      _scrollCtrl.jumpTo(pos.maxScrollExtent);
    } else {
      _scrollCtrl.animateTo(pos.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut);
    }
  }

  void _jumpToBottom() => _settleToBottom();

  void _settleToBottom() {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _settleStep(0));
  }

  void _settleStep(int n) {
    if (!mounted || !_scrollCtrl.hasClients || n > 8) return;
    final pos = _scrollCtrl.position;
    if (pos.maxScrollExtent <= 0) return;
    final prevExtent = pos.maxScrollExtent;
    _scrollCtrl.jumpTo(pos.maxScrollExtent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      final p = _scrollCtrl.position;
      if (p.maxScrollExtent > prevExtent + 1) _settleStep(n + 1);
    });
  }

  void _toggleAttach() {
    final willShow = !_showAttach;
    final pin = _atBottom;
    setState(() => _showAttach = willShow);
    if (pin) {
      _pinBottomOnResize = true;
      Future.delayed(const Duration(milliseconds: 260), () {
        if (mounted) _pinBottomOnResize = false;
      });
    }
  }

  void _maybeLoadMore() {
    if (_loadingMore || _noMoreHistory || !_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels > pos.minScrollExtent + 2) return;
    _loadingMore = true;
    _loadingHistory = true;
    _preLoadPixels = pos.pixels;
    _preLoadMaxExtent = pos.maxScrollExtent;
    ref.read(chatProvider.notifier).loadMoreHistory().then((added) {
      if (!mounted) return;
      if (!added) _noMoreHistory = true;
      setState(() => _loadingMore = false);
      _loadingHistory = false;
    });
  }

  void _onUserScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    final max = pos.maxScrollExtent <= 0 ? 1.0 : pos.maxScrollExtent;
    _scrollFraction = (pos.pixels / max).clamp(0.0, 1.0);
    if (!_scrollBarVisible) setState(() => _scrollBarVisible = true);
    _scrollBarHideTimer?.cancel();
    _scrollBarHideTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted && !_draggingThumb) {
        setState(() => _scrollBarVisible = false);
      }
    });
  }

  String? _dateAtFraction() {
    final msgs = _state.messages;
    if (msgs.isEmpty) return null;
    final idx = (_scrollFraction * (msgs.length - 1))
        .round()
        .clamp(0, msgs.length - 1);
    return _dateLabel(msgs[idx].createdAt);
  }

  void _onThumbDrag(double frac) {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    final max = pos.maxScrollExtent;
    if (max <= 0) return;
    _scrollFraction = frac;
    _scrollCtrl.jumpTo(frac * max);
    if (!_draggingThumb) setState(() => _draggingThumb = true);
    setState(() {});
  }

  void _onThumbDragEnd() {
    if (_draggingThumb) setState(() => _draggingThumb = false);
    _scrollBarHideTimer?.cancel();
    _scrollBarHideTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _scrollBarVisible = false);
    });
  }

  int _itemCount() => _state.messages.length +
      ((_state.streamingThinking?.isNotEmpty == true) ? 1 : 0) +
      ((_state.streamingText?.isNotEmpty == true) ? 1 : 0);

  Widget _item(int i) {
    final msgs = _state.messages;
    final hasStreamThinking = _state.streamingThinking?.isNotEmpty == true;
    final hasStreamText = _state.streamingText?.isNotEmpty == true;
    if (i < msgs.length) {
      final m = msgs[i];
      final curDay = _dayKey(m.createdAt);
      final prevDay = i == 0 ? null : _dayKey(msgs[i - 1].createdAt);
      final showDate = prevDay != curDay;
      Widget row;
      if (m.msgType == 'thinking') {
        row = ThinkingBlock(text: m.content ?? '', isDark: _isDark);
      } else if (m.msgType == 'tool_status') {
        row = ToolStatus(text: m.content ?? '');
      } else {
        final prevGrouped = i > 0 && !showDate && sameGroup(msgs[i - 1], m);
        // 最后一条对方消息后紧跟流式内容时，视为同组（不显示时间）。
        final nextGrouped = i + 1 < msgs.length
            ? sameGroup(m, msgs[i + 1])
            : (!m.isFromMe && hasStreamText && !hasStreamThinking);
        row = MessageBubble(
          m: m,
          maxWidth: _w - 2 * AppSpacing.md - 20,
          isDark: _isDark,
          groupedWithPrev: prevGrouped,
          groupedWithNext: nextGrouped,
        );
      }
      if (!showDate) return row;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          DateDivider(label: _dateLabel(m.createdAt), isDark: _isDark),
          row,
        ],
      );
    }
    int j = i - msgs.length;
    if (j == 0 && hasStreamThinking) {
      return Consumer(builder: (ctx, ref, _) {
        final s = ref.watch(chatProvider.select((s) => (
              s.streamingThinking ?? '',
              s.streamingText?.isNotEmpty == true
            )));
        // 正文已开始输出 → 思考阶段结束，停止「正在思考」动画。
        return ThinkingBlock(text: s.$1, isDark: _isDark, streaming: !s.$2);
      });
    }
    return Consumer(builder: (ctx, ref, _) {
      final st =
          ref.watch(chatProvider.select((s) => s.streamingText)) ?? '';
      return StreamingBubble(
          text: st, bw: _w - 2 * AppSpacing.md - 20, isDark: _isDark);
    });
  }

  static DateTime _dayKey(int ms) {
    final d =
        DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    return DateTime(d.year, d.month, d.day);
  }

  static String _dateLabel(int ms) {
    final d =
        DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    final today = DateTime.now();
    final day = DateTime(d.year, d.month, d.day);
    final now = DateTime(today.year, today.month, today.day);
    final diff = now.difference(day).inDays;
    if (diff <= 0) return '今天';
    if (diff == 1) return '昨天';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  void _send() {
    final t = _inputCtrl.text.trim();
    if (t.isEmpty) return;
    _inputCtrl.clear();
    _focusNode.requestFocus();
    _showAttach = false;
    ref.read(chatProvider.notifier).sendText(t);
  }

  // --- Voice recording ---
  //
  // 手势与录音是两条异步线：长按开始后 _startVoice 要先 await 权限（首次会弹系统
  // 对话框）与 recorder.start；期间手指可能已松开（onLongPressEnd），或系统对话框
  // 抢走焦点导致手势被取消（onLongPressCancel，此时 End 不会触发）。旧实现不跟踪
  // 手势是否仍按住，start 完成后照样置 _recording=true —— 麦克风常开、录音条
  // 卡在界面上。这里用 [_voiceGesture] 代号串起一次按压：start 完成后若手势已
  // 结束，立即停止并丢弃本次录音。
  int _voiceGesture = 0;
  bool _voiceHeld = false;

  Future<void> _startVoice() async {
    final gesture = ++_voiceGesture;
    _voiceHeld = true;
    final ok = await _audioService.hasPermission();
    if (!ok || !mounted) return;
    if (!_voiceHeld || gesture != _voiceGesture) return; // 授权期间已松手
    await _audioService.startRecording();
    if (!mounted) return;
    if (!_voiceHeld || gesture != _voiceGesture) {
      // recorder.start 期间已松手/取消：停掉并丢弃，不留常开麦克风。
      await _audioService.stopRecording();
      return;
    }
    setState(() {
      _recording = true;
      _recCancel = false;
      _recAmplitude = 0;
    });
    ref.read(audioProvider.notifier).startRecording();
    _recSub = _audioService
        .amplitudeStream(const Duration(milliseconds: 100))
        .listen((amp) {
      if (mounted) {
        setState(() => _recAmplitude =
            ((amp.current + 60) / 60).clamp(0.0, 1.0));
      }
    });
  }

  void _voiceMove(double dy) {
    if (_recording) setState(() => _recCancel = dy < -60);
  }

  /// 手势被系统取消（如权限对话框弹出）：按「取消录音」处理。
  void _cancelVoiceGesture() {
    _voiceHeld = false;
    if (_recording) {
      _recCancel = true;
      _endVoice();
    }
  }

  Future<void> _endVoice() async {
    _voiceHeld = false;
    if (!_recording) return; // 录音尚未真正开始：_startVoice 会自行收尾
    _recSub?.cancel();
    _recSub = null;
    final file = await _audioService.stopRecording();
    ref.read(audioProvider.notifier).stopRecording();
    final cancel = _recCancel;
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recCancel = false;
    });
    if (cancel || file == null) return;

    final notifier = ref.read(chatProvider.notifier);
    final key =
        notifier.createPendingMedia(msgType: 'voice', localPath: file.path);
    // m4a → audio/mp4，服务端按 audio/* 前缀映射为 Record 语音消息
    final r = await notifier.uploadMedia(file, mimeForMediaSend(file.path, 'voice'),
        onProgress: (s, t) {
      notifier.updateUploadProgress(key, t > 0 ? s / t : 0);
    });
    if (r.fileId != null && mounted) {
      notifier.finalizeMediaSend(key, r.fileId!, 'voice');
    } else if (mounted) {
      notifier.failMediaUpload(key);
      _toast(r.error ?? '语音发送失败');
    }
  }

  void _addAccount() {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AccountEditorScreen()));
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _sendImage(File file) async {
    final notifier = ref.read(chatProvider.notifier);
    final key =
        notifier.createPendingMedia(msgType: 'image', localPath: file.path);
    final r = await notifier.uploadMedia(file, 'image/jpeg',
        onProgress: (s, t) {
      notifier.updateUploadProgress(key, t > 0 ? s / t : 0);
    });
    if (r.fileId != null && mounted) {
      notifier.finalizeMediaSend(key, r.fileId!, 'image');
    } else if (mounted) {
      notifier.failMediaUpload(key);
      _toast(r.error ?? '图片上传失败');
    }
  }

  Future<void> _sendFile(File file, String filename, String mime) async {
    final notifier = ref.read(chatProvider.notifier);
    final key = notifier.createPendingMedia(
        msgType: 'file', localPath: file.path, content: filename);
    final r = await notifier.uploadMedia(file, mime,
        onProgress: (s, t) {
      notifier.updateUploadProgress(key, t > 0 ? s / t : 0);
    });
    if (r.fileId != null && mounted) {
      notifier.finalizeMediaSend(key, r.fileId!, 'file');
    } else if (mounted) {
      notifier.failMediaUpload(key);
      _toast(r.error ?? '文件上传失败');
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _inputCtrl.dispose();
    _focusNode.dispose();
    _recSub?.cancel();
    _audioService.dispose();
    _scrollBarHideTimer?.cancel();
    super.dispose();
  }
}

// ====== 回到底部 ======
class _FAB extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;
  const _FAB({required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.forDark(isDark);
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: AppShadows.fab(isDark),
      ),
      child: Material(
        color: c.surface,
        shape: CircleBorder(side: BorderSide(color: c.border, width: 0.5)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
              width: 42,
              height: 42,
              child: Icon(Icons.keyboard_arrow_down_rounded,
                  color: c.primary, size: 26)),
        ),
      ),
    );
  }
}

// ====== 空状态 ======
class _EmptyChat extends StatelessWidget {
  final bool isDark;
  final String accountName;
  final String sessionName;
  final List<SlashCommand> commands;
  final ValueChanged<String> onPick;
  const _EmptyChat({
    required this.isDark,
    required this.accountName,
    required this.sessionName,
    required this.commands,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.forDark(isDark);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: c.bubbleMineGradient),
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppShadows.mine(c.bubbleMineGradient[1]),
            ),
            child: const Icon(Icons.smart_toy_rounded,
                color: Colors.white, size: 36),
          ),
          const SizedBox(height: 20),
          Text('有什么可以帮你？',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary)),
          const SizedBox(height: 6),
          Text('$accountName · $sessionName',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.textSecondary)),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final cmd in commands)
                Material(
                  color: c.surface,
                  shape: StadiumBorder(
                      side: BorderSide(color: c.border, width: 0.8)),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => onPick(cmd.cmd),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(cmd.cmd,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
                                color: c.primary)),
                        const SizedBox(width: 6),
                        Text(cmd.desc,
                            style: TextStyle(
                                fontSize: 12.5, color: c.textSecondary)),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ]),
      ),
    );
  }
}

// ====== 无账户 ======
class _NoAccount extends StatelessWidget {
  final bool isDark;
  final VoidCallback onAdd;
  const _NoAccount({required this.isDark, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.forDark(isDark);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: c.primarySoft,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(Icons.link_off_rounded, color: c.primary, size: 34),
          ),
          const SizedBox(height: 20),
          Text('还没有账户',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary)),
          const SizedBox(height: 6),
          Text('添加一个 BotAPI 连接后即可开始对话',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('添加账户'),
          ),
        ]),
      ),
    );
  }
}

// ====== 连接异常横幅 ======
class _ConnBanner extends StatelessWidget {
  final bool isDark;
  final String message;
  final VoidCallback onRetry;
  const _ConnBanner(
      {required this.isDark, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.forDark(isDark);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: c.error.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: c.error.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Row(children: [
        Icon(Icons.cloud_off_rounded, size: 18, color: c.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, height: 1.35, color: c.textPrimary)),
        ),
        TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(
              foregroundColor: c.error,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10)),
          child: const Text('重连'),
        ),
      ]),
    );
  }
}
