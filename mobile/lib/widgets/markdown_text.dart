import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme.dart';

class MdSpan {
  const MdSpan(this.kind, this.text);

  final String kind;
  final String text;
}

List<MdSpan> parseMarkdownSpans(String raw) {
  final source = raw.replaceAll('\r\n', '\n');
  final spans = <MdSpan>[];
  final fence = RegExp(r'```[^\n]*\n([\s\S]*?)```');
  var cursor = 0;
  for (final match in fence.allMatches(source)) {
    if (match.start > cursor) {
      spans.addAll(_parseFlow(source.substring(cursor, match.start)));
    }
    spans.add(MdSpan('fence', (match.group(1) ?? '').trimRight()));
    cursor = match.end;
  }
  if (cursor < source.length) {
    spans.addAll(_parseFlow(source.substring(cursor)));
  }
  return spans;
}

List<MdSpan> _parseFlow(String text) {
  final lines = text.split('\n');
  final out = <MdSpan>[];
  var buffer = <String>[];
  var i = 0;

  void flushText() {
    if (buffer.isEmpty) return;
    out.addAll(_parseInline(buffer.join('\n')));
    buffer = [];
  }

  while (i < lines.length) {
    final line = lines[i];
    final header = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(line.trim());
    if (header != null) {
      flushText();
      out.add(MdSpan('h${header.group(1)!.length}', header.group(2)!));
      i++;
      continue;
    }
    if (RegExp(r'^\s*[-*+]\s+').hasMatch(line)) {
      flushText();
      final items = <String>[];
      while (i < lines.length && RegExp(r'^\s*[-*+]\s+').hasMatch(lines[i])) {
        final match = RegExp(r'^\s*[-*+]\s+(.*)$').firstMatch(lines[i]);
        items.add(match?.group(1) ?? '');
        i++;
      }
      out.add(MdSpan('ul', jsonEncode(items)));
      continue;
    }
    if (RegExp(r'^\s*\d+\.\s+').hasMatch(line)) {
      flushText();
      final items = <String>[];
      while (i < lines.length && RegExp(r'^\s*\d+\.\s+').hasMatch(lines[i])) {
        final match = RegExp(r'^\s*\d+\.\s+(.*)$').firstMatch(lines[i]);
        items.add(match?.group(1) ?? '');
        i++;
      }
      out.add(MdSpan('ol', jsonEncode(items)));
      continue;
    }
    if (_isTableLine(lines[i])) {
      final start = i;
      i++;
      while (i < lines.length && (_isTableLine(lines[i]) || _isSepLine(lines[i]))) {
        i++;
      }
      final chunk = lines.sublist(start, i);
      final tableLines = chunk.where(_isTableLine).length;
      if (tableLines >= 2 || (tableLines >= 1 && chunk.any(_isSepLine))) {
        flushText();
        out.add(MdSpan('table', jsonEncode(_tableRows(chunk))));
      } else {
        buffer.addAll(chunk);
      }
    } else {
      buffer.add(lines[i]);
      i++;
    }
  }
  flushText();
  return out;
}

bool _isTableLine(String line) {
  final trimmed = line.trim();
  if (!trimmed.contains('|')) return false;
  if (trimmed.startsWith('|')) return trimmed.length > 1;
  return RegExp(r'^\S.*\|.*\S').hasMatch(trimmed);
}

bool _isSepLine(String line) {
  return RegExp(r'^\s*\|?(\s*:?-{2,}:?\s*\|)+\s*:?-{2,}:?\s*\|?\s*$').hasMatch(line.trim());
}

List<List<String>> _tableRows(List<String> lines) {
  return [
    for (final line in lines)
      if (!_isSepLine(line) && _isTableLine(line)) _splitCells(line),
  ];
}

List<String> _splitCells(String line) {
  var trimmed = line.trim();
  if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
  if (trimmed.endsWith('|') && (trimmed.length < 2 || trimmed[trimmed.length - 2] != '\\')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  final cells = <String>[];
  final buf = StringBuffer();
  var escape = false;
  var inCode = false;
  for (final unit in trimmed.runes) {
    final ch = String.fromCharCode(unit);
    if (escape) {
      buf.write(ch);
      escape = false;
      continue;
    }
    if (ch == '\\') {
      escape = true;
      continue;
    }
    if (ch == '`') {
      inCode = !inCode;
      buf.write(ch);
      continue;
    }
    if (ch == '|' && !inCode) {
      cells.add(buf.toString().trim());
      buf.clear();
      continue;
    }
    buf.write(ch);
  }
  cells.add(buf.toString().trim());
  return cells;
}

final _inlinePattern = RegExp(
  r'`([^`]+)`'
  r'|\[([^\]]+)\]\(([^)\s]+)\)'
  r'|\*\*\*(.+?)\*\*\*'
  r'|\*\*(.+?)\*\*'
  r'|__(.+?)__'
  r'|~~(.+?)~~'
  r'|(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)',
);

List<MdSpan> _parseInline(String text) {
  final source = text.replaceAllMapped(RegExp(r'<br\s*/?>', caseSensitive: false), (_) => '\n');
  final spans = <MdSpan>[];
  var cursor = 0;
  for (final match in _inlinePattern.allMatches(source)) {
    if (match.start > cursor) {
      spans.add(MdSpan('text', source.substring(cursor, match.start)));
    }
    if (match.group(1) != null) {
      spans.add(MdSpan('code', match.group(1)!));
    } else if (match.group(2) != null) {
      spans.add(MdSpan('link', match.group(2)!));
    } else if (match.group(4) != null) {
      spans.add(MdSpan('bolditalic', match.group(4)!));
    } else if (match.group(5) != null || match.group(6) != null) {
      spans.add(MdSpan('bold', match.group(5) ?? match.group(6)!));
    } else if (match.group(7) != null) {
      spans.add(MdSpan('strike', match.group(7)!));
    } else if (match.group(8) != null) {
      spans.add(MdSpan('italic', match.group(8)!));
    }
    cursor = match.end;
  }
  if (cursor < source.length) {
    spans.add(MdSpan('text', source.substring(cursor)));
  }
  return spans;
}

TextSpan _inlineSpan(String text, TextStyle base) {
  return _spansToText(_parseInline(text), base);
}

TextSpan _spansToText(List<MdSpan> spans, TextStyle base) {
  return TextSpan(
    children: [
      for (final span in spans)
        if (span.kind == 'bold')
          TextSpan(text: span.text, style: base.copyWith(fontWeight: FontWeight.w700))
        else if (span.kind == 'italic')
          TextSpan(text: span.text, style: base.copyWith(fontStyle: FontStyle.italic))
        else if (span.kind == 'bolditalic')
          TextSpan(text: span.text, style: base.copyWith(fontWeight: FontWeight.w700, fontStyle: FontStyle.italic))
        else if (span.kind == 'strike')
          TextSpan(text: span.text, style: base.copyWith(decoration: TextDecoration.lineThrough))
        else if (span.kind == 'code')
          TextSpan(
            text: span.text,
            style: base.copyWith(
              fontFamily: 'monospace',
              fontSize: (base.fontSize ?? 15) - 2,
              height: 1.45,
              color: const Color(0xFFB8C7FF),
              backgroundColor: PilotColors.surface,
            ),
          )
        else if (span.kind == 'link')
          TextSpan(
            text: span.text,
            style: base.copyWith(color: PilotColors.info, decoration: TextDecoration.underline),
          )
        else if (span.kind != 'table' && span.kind != 'fence')
          TextSpan(text: span.text, style: base),
    ],
  );
}

class MarkdownText extends StatelessWidget {
  const MarkdownText(this.data, {super.key, this.style});

  final String data;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? const TextStyle(height: 1.6, fontSize: 15, color: PilotColors.text);
    final spans = parseMarkdownSpans(data);
    if (spans.isEmpty) {
      return SelectableText(data, style: base);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final block in _groupBlocks(spans))
          if (block.length == 1 && block.first.kind == 'fence')
            _codeBlock(block.first.text, base)
          else if (block.length == 1 && block.first.kind == 'table')
            _tableBlock(block.first.text, base)
          else if (block.length == 1 && block.first.kind.startsWith('h'))
            _headingBlock(block.first, base)
          else if (block.length == 1 && block.first.kind == 'ul')
            _listBlock(block.first.text, base, ordered: false)
          else if (block.length == 1 && block.first.kind == 'ol')
            _listBlock(block.first.text, base, ordered: true)
          else
            SelectableText.rich(_spansToText(block, base)),
      ],
    );
  }

  Widget _headingBlock(MdSpan span, TextStyle base) {
    final level = int.tryParse(span.kind.substring(1)) ?? 3;
    final sizes = {1: 22.0, 2: 19.0, 3: 17.0, 4: 16.0, 5: 15.0, 6: 14.0};
    return Padding(
      padding: EdgeInsets.only(top: level <= 2 ? 10 : 6, bottom: 4),
      child: SelectableText.rich(
        _inlineSpan(span.text, base.copyWith(
          fontSize: sizes[level] ?? 15,
          fontWeight: FontWeight.w700,
          height: 1.35,
        )),
      ),
    );
  }

  Widget _listBlock(String encoded, TextStyle base, {required bool ordered}) {
    final raw = jsonDecode(encoded);
    if (raw is! List || raw.isEmpty) return const SizedBox.shrink();
    final items = raw.map((item) => item.toString()).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      ordered ? '${i + 1}.' : '•',
                      style: base.copyWith(color: PilotColors.muted, height: 1.5),
                    ),
                  ),
                  Expanded(child: SelectableText.rich(_inlineSpan(items[i], base))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _codeBlock(String text, TextStyle base) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: PilotColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PilotColors.line),
      ),
      child: SelectableText(
        text,
        style: base.copyWith(fontFamily: 'monospace', fontSize: 13, height: 1.45, color: PilotColors.text),
      ),
    );
  }

  Widget _tableBlock(String encoded, TextStyle base) {
    final raw = jsonDecode(encoded);
    if (raw is! List || raw.isEmpty) {
      return const SizedBox.shrink();
    }
    final rows = raw
        .whereType<List>()
        .map((row) => row.map((cell) => cell.toString()).toList())
        .where((row) => row.isNotEmpty)
        .toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    final width = rows.map((row) => row.length).reduce((a, b) => a > b ? a : b);
    final cellStyle = base.copyWith(fontSize: 13, height: 1.35);
    return LayoutBuilder(
      builder: (context, constraints) {
        final table = Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: TableBorder.symmetric(inside: const BorderSide(color: PilotColors.line)),
          children: [
            for (var r = 0; r < rows.length; r++)
              TableRow(
                decoration: BoxDecoration(color: r == 0 ? PilotColors.surface : Colors.transparent),
                children: [
                  for (var c = 0; c < width; c++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: _cellText(
                        c < rows[r].length ? rows[r][c] : '',
                        r == 0 ? cellStyle.copyWith(fontWeight: FontWeight.w700) : cellStyle,
                      ),
                    ),
                ],
              ),
          ],
        );
        final minWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: PilotColors.line),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minWidth),
              child: table,
            ),
          ),
        );
      },
    );
  }

  Widget _cellText(String raw, TextStyle style) {
    final text = raw.trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return SelectableText.rich(_inlineSpan(text, style));
  }
}

List<List<MdSpan>> _groupBlocks(List<MdSpan> spans) {
  final blocks = <List<MdSpan>>[];
  var current = <MdSpan>[];
  for (final span in spans) {
    if (span.kind == 'fence' ||
        span.kind == 'table' ||
        span.kind.startsWith('h') ||
        span.kind == 'ul' ||
        span.kind == 'ol') {
      if (current.isNotEmpty) {
        blocks.add(current);
        current = [];
      }
      blocks.add([span]);
    } else {
      current.add(span);
    }
  }
  if (current.isNotEmpty) blocks.add(current);
  return blocks;
}
