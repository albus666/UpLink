import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../api/models.dart';
import 'conversation.dart';

class CachedConversations {
  const CachedConversations({
    required this.threads,
    required this.details,
  });

  final List<ConversationThread> threads;
  final Map<String, RemoteTask> details;
}

class ConversationCache {
  static Future<File> _file(String linkId) async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory(p.join(root.path, 'conversation_cache'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final safe = linkId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return File(p.join(dir.path, '$safe.json'));
  }

  static Future<CachedConversations?> load(String linkId) async {
    if (linkId.isEmpty) return null;
    try {
      final file = await _file(linkId);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final rawTasks = decoded['tasks'];
      if (rawTasks is! List) return null;
      final tasks = rawTasks
          .whereType<Map>()
          .map((item) => RemoteTask.fromJson(Map<String, dynamic>.from(item)))
          .where((task) => task.id.isNotEmpty)
          .toList();
      if (tasks.isEmpty) return null;
      final threads = groupConversations(tasks);
      final details = <String, RemoteTask>{
        for (final task in tasks)
          if (task.logs.isNotEmpty || (task.resultText ?? '').trim().isNotEmpty) task.id: task,
      };
      return CachedConversations(threads: threads, details: details);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save({
    required String linkId,
    required List<ConversationThread> threads,
    Map<String, RemoteTask> details = const {},
  }) async {
    if (linkId.isEmpty) return;
    try {
      final byId = <String, RemoteTask>{};
      for (final thread in threads) {
        for (final turn in thread.turns) {
          final richer = details[turn.id] ?? turn;
          final existing = byId[turn.id];
          byId[turn.id] = _preferRicher(existing, richer);
        }
      }
      for (final entry in details.entries) {
        byId[entry.key] = _preferRicher(byId[entry.key], entry.value);
      }
      final tasks = byId.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final file = await _file(linkId);
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'saved_at': DateTime.now().toUtc().toIso8601String(),
          'tasks': tasks.map((task) => task.toJson()).toList(),
        }),
      );
    } catch (_) {
      // ignore cache write failures
    }
  }

  static Future<void> clear(String linkId) async {
    if (linkId.isEmpty) return;
    try {
      final file = await _file(linkId);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static RemoteTask _preferRicher(RemoteTask? a, RemoteTask b) {
    if (a == null) return b;
    final aScore = a.logs.length + ((a.resultText ?? '').trim().isEmpty ? 0 : 1000);
    final bScore = b.logs.length + ((b.resultText ?? '').trim().isEmpty ? 0 : 1000);
    if (bScore > aScore) return b;
    if (aScore > bScore) return a;
    return b;
  }
}
