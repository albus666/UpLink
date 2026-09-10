import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uplink/widgets/markdown_text.dart';

void main() {
  test('parses bold and inline code', () {
    final spans = parseMarkdownSpans('改了 `main.py` 里的 **超时** 逻辑');
    expect(spans.map((s) => '${s.kind}:${s.text}').toList(), [
      'text:改了 ',
      'code:main.py',
      'text: 里的 ',
      'bold:超时',
      'text: 逻辑',
    ]);
  });

  test('parses markdown tables', () {
    final spans = parseMarkdownSpans('| 名称 | 状态 |\n| --- | --- |\n| Agent | 黄 |\n| Ask | 绿 |');
    final table = spans.singleWhere((s) => s.kind == 'table');
    expect(table.text.contains('Agent'), isTrue);
    expect(table.text.contains('Ask'), isTrue);
    expect(spans.any((s) => s.kind == 'text' && s.text.contains('| Agent |')), isFalse);
  });

  testWidgets('renders markdown tables in a list', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              MarkdownText('| 名称 | 状态 |\n| --- | --- |\n| Agent | 黄 |\n| Ask | 绿 |'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('名称'), findsOneWidget);
    expect(find.textContaining('Agent'), findsOneWidget);
    expect(find.text('| Agent | 黄 |'), findsNothing);
  });

  testWidgets('renders markdown inside table cells', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              MarkdownText('| **名称** | 状态 |\n| --- | --- |\n| `Agent` | **黄** |'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('名称'), findsOneWidget);
    expect(find.text('Agent'), findsOneWidget);
    expect(find.text('黄'), findsOneWidget);
    expect(find.text('**名称**'), findsNothing);
    expect(find.text('`Agent`'), findsNothing);
    expect(find.text('**黄**'), findsNothing);
  });

  test('parses headings and bullet lists', () {
    final spans = parseMarkdownSpans('## 标题\n\n- 第一项\n- 第二项');
    expect(spans.any((s) => s.kind == 'h2' && s.text == '标题'), isTrue);
    final list = spans.singleWhere((s) => s.kind == 'ul');
    expect(list.text.contains('第一项'), isTrue);
    expect(list.text.contains('第二项'), isTrue);
  });

  testWidgets('renders headings and lists', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              MarkdownText('## 学习路径\n\n- Agent 基础\n- 工具调用'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('学习路径'), findsOneWidget);
    expect(find.text('Agent 基础'), findsOneWidget);
    expect(find.text('## 学习路径'), findsNothing);
    expect(find.text('- Agent 基础'), findsNothing);
  });

  test('parses fenced code separately', () {
    final spans = parseMarkdownSpans('见\n```\nprint(1)\n```\n结束');
    expect(spans.where((s) => s.kind == 'fence').single.text, 'print(1)');
    expect(spans.first.kind, 'text');
    expect(spans.last.text.contains('结束'), isTrue);
  });
}
