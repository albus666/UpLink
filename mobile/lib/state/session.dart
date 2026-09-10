import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import 'conversation_cache.dart';

class ServerLink {
  ServerLink({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.token,
  });

  final String id;
  String name;
  String baseUrl;
  String token;

  String get hostLabel {
    try {
      return Uri.parse(baseUrl).host;
    } catch (_) {
      return baseUrl;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'token': token,
      };

  factory ServerLink.fromJson(Map<String, dynamic> json) {
    return ServerLink(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ?? '',
      token: json['token'] as String? ?? '',
    );
  }
}

class SessionController extends ChangeNotifier {
  static const _linksKey = 'uplink.links';
  static const _activeKey = 'uplink.activeLink';
  static const _legacyUrlKey = 'uplink.baseUrl';
  static const _legacyTokenKey = 'uplink.token';
  static const _modeKey = 'uplink.chatMode';

  List<ServerLink> links = [];
  String? activeId;
  String? lastThreadId;
  String chatMode = 'agent';
  bool ready = false;

  ServerLink? get active {
    if (links.isEmpty) return null;
    final match = links.where((item) => item.id == activeId);
    if (match.isNotEmpty) return match.first;
    return links.first;
  }

  bool get hasLink => active != null;
  String get baseUrl => active?.baseUrl ?? '';
  String get token => active?.token ?? '';
  bool get isLoggedIn => hasLink;

  ApiClient get client {
    final link = active;
    if (link == null) {
      throw ApiException('还没有连接');
    }
    return ApiClient(baseUrl: link.baseUrl, token: link.token);
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_linksKey);
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        links = decoded
            .whereType<Map>()
            .map((item) => ServerLink.fromJson(Map<String, dynamic>.from(item)))
            .where((item) => item.id.isNotEmpty)
            .toList();
      }
    }

    final legacyUrl = prefs.getString(_legacyUrlKey) ?? '';
    final legacyToken = prefs.getString(_legacyTokenKey) ?? '';
    if (links.isEmpty && legacyUrl.isNotEmpty && legacyToken.isNotEmpty) {
      final migrated = ServerLink(
        id: _newId(),
        name: _defaultName(legacyUrl),
        baseUrl: legacyUrl,
        token: legacyToken,
      );
      links = [migrated];
      activeId = migrated.id;
      await _persist(prefs);
      await prefs.remove(_legacyUrlKey);
      await prefs.remove(_legacyTokenKey);
    } else {
      activeId = prefs.getString(_activeKey);
      if (active == null && links.isNotEmpty) {
        activeId = links.first.id;
        await prefs.setString(_activeKey, activeId!);
      }
    }

    ready = true;
    await _loadThread(prefs);
    chatMode = prefs.getString(_modeKey) == 'ask' ? 'ask' : 'agent';
    notifyListeners();
  }

  Future<ServerLink> saveLink({
    String? id,
    required String name,
    required String url,
    required String token,
  }) async {
    final cleanedUrl = url.trim().replaceAll(RegExp(r'/$'), '');
    final cleanedToken = token.trim();
    final cleanedName = name.trim().isEmpty ? _defaultName(cleanedUrl) : name.trim();
    if (cleanedUrl.isEmpty || cleanedToken.isEmpty) {
      throw ApiException('请填写服务器地址和口令');
    }
    if (!cleanedUrl.startsWith('http://') && !cleanedUrl.startsWith('https://')) {
      throw ApiException('地址需要以 http:// 或 https:// 开头');
    }
    await ApiClient.login(cleanedUrl, cleanedToken);

    final existingIndex = id == null ? -1 : links.indexWhere((item) => item.id == id);
    late final ServerLink link;
    if (existingIndex >= 0) {
      link = links[existingIndex]
        ..name = cleanedName
        ..baseUrl = cleanedUrl
        ..token = cleanedToken;
    } else {
      link = ServerLink(id: _newId(), name: cleanedName, baseUrl: cleanedUrl, token: cleanedToken);
      links = [...links, link];
    }
    activeId = link.id;
    final prefs = await SharedPreferences.getInstance();
    await _persist(prefs);
    await _loadThread(prefs);
    notifyListeners();
    return link;
  }

  Future<void> selectLink(String id) async {
    if (links.every((item) => item.id != id)) return;
    activeId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeKey, id);
    await _loadThread(prefs);
    notifyListeners();
  }

  Future<void> deleteLink(String id) async {
    links = links.where((item) => item.id != id).toList();
    if (activeId == id) {
      activeId = links.isEmpty ? null : links.first.id;
    }
    final prefs = await SharedPreferences.getInstance();
    await _persist(prefs);
    await _loadThread(prefs);
    await ConversationCache.clear(id);
    notifyListeners();
  }

  Future<void> setChatMode(String mode) async {
    chatMode = mode == 'ask' ? 'ask' : 'agent';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, chatMode);
    notifyListeners();
  }

  Future<void> rememberThread(String? threadId) async {
    lastThreadId = threadId;
    final prefs = await SharedPreferences.getInstance();
    final link = active;
    if (link == null) return;
    final key = _threadKey(link.id);
    if (threadId == null || threadId.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, threadId);
    }
  }

  Future<void> _loadThread(SharedPreferences prefs) async {
    final link = active;
    lastThreadId = link == null ? null : prefs.getString(_threadKey(link.id));
  }

  String _threadKey(String linkId) => 'uplink.lastThread.$linkId';

  Future<void> _persist(SharedPreferences prefs) async {
    await prefs.setString(_linksKey, jsonEncode(links.map((item) => item.toJson()).toList()));
    if (activeId == null) {
      await prefs.remove(_activeKey);
    } else {
      await prefs.setString(_activeKey, activeId!);
    }
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  String _defaultName(String url) {
    try {
      final host = Uri.parse(url).host;
      return host.isEmpty ? '未命名连接' : host;
    } catch (_) {
      return '未命名连接';
    }
  }
}
