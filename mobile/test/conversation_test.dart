import 'package:flutter_test/flutter_test.dart';
import 'package:uplink/api/models.dart';
import 'package:uplink/state/conversation.dart';

void main() {
  test('uses custom title and pin sort', () {
    final older = RemoteTask(
      id: 'a',
      prompt: '原始标题很长会被截断以前的做法',
      status: 'succeeded',
      createdAt: '2026-09-08T10:00:00Z',
      title: '自定义名',
      pinned: true,
    );
    final newer = RemoteTask(
      id: 'b',
      prompt: '新对话内容',
      status: 'succeeded',
      createdAt: '2026-09-09T10:00:00Z',
    );
    final threads = groupConversations([older, newer]);
    expect(threads.first.id, 'a');
    expect(threads.first.title, '自定义名');
    expect(threads.last.title, '新对话内容');
  });

  test('date labels', () {
    final now = DateTime(2026, 9, 9, 12);
    expect(threadDateLabel(DateTime(2026, 9, 9, 1), now), '今天');
    expect(threadDateLabel(DateTime(2026, 9, 8, 23), now), '昨天');
    expect(threadDateLabel(DateTime(2026, 9, 4), now), '最近 7 天');
  });

  test('task json roundtrip keeps reply text', () {
    final task = RemoteTask(
      id: 't1',
      prompt: '你好',
      status: 'succeeded',
      createdAt: '2026-09-10T01:00:00Z',
      resultText: '世界',
      logs: [LogLine(ts: '1', kind: 'assistant', text: '世界')],
    );
    final again = RemoteTask.fromJson(task.toJson());
    expect(again.resultText, '世界');
    expect(again.logs.single.text, '世界');
    expect(groupConversations([again]).single.title, '你好');
  });
}
