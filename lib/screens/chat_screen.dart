import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import '../providers/audio_provider.dart';
import '../providers/chat_provider.dart';
import '../services/audio_playback_service.dart';
import '../services/audio_service.dart';
import '../providers/platform_providers.dart';
import '../models/botapi_event.dart';
import '../models/message.dart';
import '../widgets/attachment_panel.dart';
import '../widgets/account_drawer.dart';
import 'chat/app_bar.dart';
import 'chat/input_bar.dart';
import 'chat/voice_overlay.dart';
import 'chat/scroll_thumb.dart';
import 'chat/date_divider.dart';
import 'chat/slash_suggestion.dart';
import 'chat/bubbles/text_bubble.dart';
import 'chat/bubbles/image_bubble.dart';
import 'chat/bubbles/voice_bubble.dart';
import 'chat/bubbles/file_bubble.dart';
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

    return Scaffold(
      resizeToAvoidBottomInset: true,
      drawer: const AccountDrawer(),
      backgroundColor:
          isDark ? const Color(0xFF0F0F0F) : const Color(0xFFFAFAFB),
      appBar: ChatAppBar(
        connected: conn,
        isDark: isDark,
        error: _state.errorMessage,
        accountName: _state.currentAccountName,
        streaming: _state.streamingText?.isNotEmpty == true,
        reconnecting: _state.connectionState == ConnState.reconnecting,
        autoPlay: _state.autoPlayVoice,
        onToggleAutoPlay: () => ref
            .read(chatProvider.notifier)
            .setAutoPlayVoice(!_state.autoPlayVoice),
      ),
      body: Column(children: [
        Expanded(
            child: n == 0
                ? const Center(
                    child: Text('发送消息开始聊天',
                        style: TextStyle(
                            color: Color(0xFF999999), fontSize: 14)))
                : Stack(children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: isDark
                                  ? [
                                      const Color(0xFF151518),
                                      const Color(0xFF0B0B0D)
                                    ]
                                  : [
                                      const Color(0xFFFBFBFD),
                                      const Color(0xFFF3F4F8)
                                    ],
                            ),
                          ),
                        ),
                      ),
                    ),
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
                          physics: const ClampingScrollPhysics(),
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
                                padding: EdgeInsets.only(top: 8)),
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (ctx, i) =>
                                    RepaintBoundary(child: _item(i)),
                                childCount: n,
                              ),
                            ),
                            SliverPadding(
                                padding: EdgeInsets.only(
                                    bottom: 80 + _bottomPad)),
                          ],
                        ),
                      ),
                    ),
                    if (!_atBottom && n > 0)
                      Positioned(
                          right: 12,
                          bottom: 8,
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
          hasText: _inputCtrl.text.isNotEmpty,
          showAttachment: _toggleAttach,
          slashMatches: _slashMatches,
          onPickSlash: _pickSlashCommand,
          onVoiceStart: _startVoice,
          onVoiceMove: _voiceMove,
          onVoiceEnd: _endVoice,
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
    if (i < msgs.length) {
      final m = msgs[i];
      if (m.msgType == 'thinking') {
        return ThinkingBlock(text: m.content ?? '', isDark: _isDark);
      }
      if (m.msgType == 'tool_status') {
        return ToolStatus(text: m.content ?? '');
      }
      final curDay = _dayKey(m.createdAt);
      final prevDay = i == 0 ? null : _dayKey(msgs[i - 1].createdAt);
      final showDate = prevDay != curDay;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDate)
            DateDivider(
                label: _dateLabel(m.createdAt), isDark: _isDark),
          _BubbleWrapper(m: m, bw: _w - 48, isDark: _isDark),
        ],
      );
    }
    int j = i - msgs.length;
    if (j == 0 && _state.streamingThinking?.isNotEmpty == true) {
      return Consumer(builder: (ctx, ref, _) {
        final t = ref
                .watch(chatProvider
                    .select((s) => s.streamingThinking)) ??
            '';
        return ThinkingBlock(text: t, isDark: _isDark);
      });
    }
    return Consumer(builder: (ctx, ref, _) {
      final st =
          ref.watch(chatProvider.select((s) => s.streamingText)) ?? '';
      return StreamingBubble(text: st, bw: _w - 48, isDark: _isDark);
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
  Future<void> _startVoice() async {
    final ok = await _audioService.hasPermission();
    if (!ok) return;
    await _audioService.startRecording();
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

  Future<void> _endVoice() async {
    _recSub?.cancel();
    final file = await _audioService.stopRecording();
    ref.read(audioProvider.notifier).stopRecording();
    final cancel = _recCancel;
    setState(() {
      _recording = false;
      _recCancel = false;
    });
    if (cancel || file == null) return;

    final notifier = ref.read(chatProvider.notifier);
    final key =
        notifier.createPendingMedia(msgType: 'voice', localPath: file.path);
    final r = await notifier.uploadMedia(file, 'audio/wav',
        onProgress: (s, t) {
      notifier.updateUploadProgress(key, t > 0 ? s / t : 0);
    });
    if (r.fileId != null && mounted) {
      notifier.finalizeMediaSend(key, r.fileId!, 'voice');
    } else if (mounted) {
      notifier.failMediaUpload(key);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r.error ?? '语音发送失败'),
          backgroundColor: Colors.redAccent));
    }
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r.error ?? '图片上传失败'),
          backgroundColor: Colors.redAccent));
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r.error ?? '文件上传失败'),
          backgroundColor: Colors.redAccent));
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

// ====== FAB ======
class _FAB extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;
  const _FAB({required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: isDark ? const Color(0xFF3A3A3C) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        elevation: 4,
        child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Container(
                padding: const EdgeInsets.all(10),
                child: Icon(Icons.keyboard_arrow_down_rounded,
                    color: isDark ? Colors.white : Colors.black,
                    size: 22))),
      );
}

// ====== BUBBLE WRAPPER ======
class _BubbleWrapper extends ConsumerWidget {
  final LocalMessage m;
  final double bw;
  final bool isDark;
  const _BubbleWrapper(
      {required this.m, required this.bw, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMe = m.isFromMe;
    final type = m.msgType;
    final text = m.content ?? '';
    final bg = isMe
        ? (isDark ? const Color(0xFF7661D8) : const Color(0xFF5B4BD6))
        : (isDark ? const Color(0xFF212121) : const Color(0xFFE8E8EC));
    final fg = isMe
        ? Colors.white
        : (isDark ? Colors.white : Colors.black);

    Widget body;
    switch (type) {
      case 'image':
        body = ImageBubble(m: m, bw: bw, isMe: isMe);
        break;
      case 'voice':
      case 'record':
      case 'audio':
        body = VoiceBubble(m: m, fg: fg, isMe: isMe);
        break;
      case 'file':
        body = FileBubble(m: m, fg: fg, isMe: isMe);
        break;
      default:
        final errored = (m.status as MessageStatus?) == MessageStatus.error;
        body = errored
            ? TextBodyError(
                content: text,
                onRetry: () {
                  ref.read(chatProvider.notifier)
                      .retryTextSend((m.createdAt as int?) ?? 0);
                })
            : mdText(text, fg, isDark);
    }

    final createdAt = (m.createdAt as int?) ?? 0;
    final time = createdAt > 0 ? _hhmm(createdAt) : null;
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 3),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment:
                isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: bw),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: isMe
                      ? const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(2))
                      : const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                          bottomLeft: Radius.circular(2),
                          bottomRight: Radius.circular(16)),
                ),
                child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: body),
              ),
            ),
          ),
          if (time != null)
            Padding(
              padding: const EdgeInsets.only(
                  top: 2, left: 4, right: 4, bottom: 6),
              child: Text(time,
                  style: TextStyle(
                      fontSize: 10,
                      color: isDark
                          ? const Color(0xFF8E8E93)
                          : const Color(0xFF9E9E9E))),
            ),
        ],
      ),
    );
  }

  static String _hhmm(int ms) {
    final d =
        DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
