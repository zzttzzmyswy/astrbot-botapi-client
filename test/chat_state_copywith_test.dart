// test/chat_state_copywith_test.dart
//
// 验证 ChatState.copyWith 对 streamingText/streamingThinking/errorMessage 的
// 「不传=保留 / 传 null=清空 / 传值=设置」语义。旧实现不传即清空,导致:
// - isToolStatus 的 copyWith(messages: ...) 清空 streamingText → 工具调用间
//   文本段丢失,final 只剩末段;
// - isStreamingText 的 copyWith(streamingText: ...) 清空 streamingThinking →
//   final 时 thinking 为 null 不落库。
import 'package:flutter_test/flutter_test.dart';
import 'package:astrbot_app/providers/chat_provider.dart';
import 'package:astrbot_app/models/chat_session.dart';
import 'package:astrbot_app/models/message.dart';

void main() {
  ChatState base() => ChatState(
        messages: const [],
        streamingText: '段一',
        streamingThinking: '思考一',
        errorMessage: '旧错误',
      );

  group('streamingText', () {
    test('不传 → 保留旧值', () {
      final s = base().copyWith(messages: [LocalMessage(msgType: 'text', isFromMe: true, createdAt: 1)]);
      expect(s.streamingText, '段一');
    });
    test('传 null → 清空', () {
      final s = base().copyWith(streamingText: null);
      expect(s.streamingText, isNull);
    });
    test('传值 → 覆盖', () {
      final s = base().copyWith(streamingText: '段一+段二');
      expect(s.streamingText, '段一+段二');
    });
  });

  group('streamingThinking', () {
    test('不传 → 保留旧值', () {
      final s = base().copyWith(streamingText: '段二');
      expect(s.streamingThinking, '思考一');
    });
    test('传 null → 清空', () {
      final s = base().copyWith(streamingThinking: null);
      expect(s.streamingThinking, isNull);
    });
  });

  group('errorMessage', () {
    test('不传 → 保留旧值', () {
      final s = base().copyWith(streamingText: '段二');
      expect(s.errorMessage, '旧错误');
    });
    test('传 null → 清空', () {
      final s = base().copyWith(errorMessage: null);
      expect(s.errorMessage, isNull);
    });
  });

  group('工具调用间文本段不清空(核心场景)', () {
    test('isToolStatus: copyWith(messages:+msg) 不清空 streamingText/streamingThinking',
        () {
      // 模拟 _handleEvent isToolStatus 分支:已累积段一文本与思考,工具调用事件落库。
      final before = base(); // streamingText='段一', streamingThinking='思考一'
      final toolMsg = LocalMessage(
          msgType: 'tool_status', isFromMe: false, status: MessageStatus.sent, createdAt: 2);
      final after = before.copyWith(messages: [...before.messages, toolMsg]);
      expect(after.streamingText, '段一', reason: '工具调用不应清空已累积文本段');
      expect(after.streamingThinking, '思考一', reason: '工具调用不应清空思考');
      expect(after.messages.length, 1);
    });

    test('isStreamingText: 追加文本段不清空 thinking', () {
      // 模拟段二 delta 到达:streamingText 追加,streamingThinking 必须保留到 final 落库。
      final before = base(); // streamingText='段一', streamingThinking='思考一'
      final after = before.copyWith(streamingText: '段一段二');
      expect(after.streamingText, '段一段二');
      expect(after.streamingThinking, '思考一', reason: '文本流式期间思考须保留,final 才能落库');
    });

    test('isThinking: 追加思考不清空已累积文本段', () {
      final before = base(); // streamingText='段一'
      final after = before.copyWith(streamingThinking: '思考一思考二');
      expect(after.streamingThinking, '思考一思考二');
      expect(after.streamingText, '段一');
    });
  });

  test('connect 重置: 显式传 null 清空三者', () {
    // 模拟 connect() 起始重置:errorMessage/streamingText/streamingThinking 全清空。
    final s = base().copyWith(
      errorMessage: null,
      streamingText: null,
      streamingThinking: null,
    );
    expect(s.errorMessage, isNull);
    expect(s.streamingText, isNull);
    expect(s.streamingThinking, isNull);
  });

  group('currentSessionName', () {
    test('匹配会话列表中的名称', () {
      final s = ChatState(
        sessions: const [
          ChatSession(id: 'default', name: '默认会话'),
          ChatSession(id: 'abc', name: '工作'),
        ],
        currentSessionId: 'abc',
      );
      expect(s.currentSessionName, '工作');
    });
    test('currentSessionId 不在列表 → 回退默认会话', () {
      final s = ChatState(
        sessions: const [ChatSession(id: 'abc', name: '工作')],
        currentSessionId: 'nope',
      );
      expect(s.currentSessionName, '默认会话');
    });
    test('降级态（空 sessions）→ 默认会话', () {
      final s = ChatState(currentSessionId: 'default');
      expect(s.currentSessionName, '默认会话');
    });
    test('默认会话被服务端改名后显示自定义名(按 id 匹配)', () {
      final s = ChatState(
        sessions: const [ChatSession(id: 'default', name: '自定义默认')],
        currentSessionId: 'default',
      );
      expect(s.currentSessionName, '自定义默认');
    });
  });
}
