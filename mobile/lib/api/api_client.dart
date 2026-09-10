import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  Uri _uri(String path) {
    final root = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$root$path');
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  static Future<void> ping(String baseUrl) async {
    final root = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final response = await http.get(Uri.parse('$root/api/health')).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw ApiException('服务器没有正常响应', statusCode: response.statusCode);
    }
  }

  static Future<void> login(String baseUrl, String token) async {
    final root = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final response = await http
        .post(
          Uri.parse('$root/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'token': token}),
        )
        .timeout(const Duration(seconds: 8));
    _throwIfNeeded(response);
  }

  Future<http.Response> _get(String path, {Duration timeout = const Duration(seconds: 12)}) async {
    try {
      return await http.get(_uri(path), headers: _headers).timeout(timeout);
    } on TimeoutException {
      throw ApiException('请求超时');
    }
  }

  Future<http.Response> _post(String path, {Object? body, Duration timeout = const Duration(seconds: 20)}) async {
    try {
      return await http.post(_uri(path), headers: _headers, body: body).timeout(timeout);
    } on TimeoutException {
      throw ApiException('请求超时');
    }
  }

  Future<http.Response> _patch(String path, {Object? body, Duration timeout = const Duration(seconds: 15)}) async {
    try {
      return await http.patch(_uri(path), headers: _headers, body: body).timeout(timeout);
    } on TimeoutException {
      throw ApiException('请求超时');
    }
  }

  Future<http.Response> _put(String path, {Object? body, Duration timeout = const Duration(seconds: 15)}) async {
    try {
      return await http.put(_uri(path), headers: _headers, body: body).timeout(timeout);
    } on TimeoutException {
      throw ApiException('请求超时');
    }
  }

  Future<http.Response> _delete(String path, {Duration timeout = const Duration(seconds: 15)}) async {
    try {
      return await http.delete(_uri(path), headers: _headers).timeout(timeout);
    } on TimeoutException {
      throw ApiException('请求超时');
    }
  }

  Future<WorkspaceInfo> workspace() async {
    final response = await _get('/api/workspace');
    return WorkspaceInfo.fromJson(_decode(response) as Map<String, dynamic>);
  }

  Future<WorkspaceInfo> setModel(String model) async {
    final response = await _put('/api/workspace/model', body: jsonEncode({'model': model}));
    return WorkspaceInfo.fromJson(_decode(response) as Map<String, dynamic>);
  }

  Future<List<RemoteTask>> tasks() async {
    final response = await _get('/api/tasks');
    final data = _decode(response) as Map<String, dynamic>;
    return (data['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RemoteTask.fromJson)
        .toList();
  }

  Future<RemoteTask> createTask({
    required String prompt,
    List<String> uploadIds = const [],
    bool resume = false,
    String? sessionId,
    String? model,
    String mode = 'agent',
  }) async {
    final response = await _post(
      '/api/tasks',
      body: jsonEncode({
        'prompt': prompt,
        'upload_ids': uploadIds,
        'resume': resume,
        'session_id': sessionId,
        if (model != null && model.isNotEmpty) 'model': model,
        'mode': mode,
      }),
    );
    return RemoteTask.fromJson(_decode(response) as Map<String, dynamic>);
  }

  Future<RemoteTask> task(String id) async {
    final response = await _get('/api/tasks/$id');
    return RemoteTask.fromJson(_decode(response) as Map<String, dynamic>);
  }

  Future<void> cancel(String id) async {
    final response = await _post('/api/tasks/$id/cancel', timeout: const Duration(seconds: 8));
    _decode(response);
  }

  Future<RemoteTask> approveTask(String id, {required bool approve}) async {
    final response = await _post(
      '/api/tasks/$id/approval',
      body: jsonEncode({'decision': approve ? 'approve' : 'deny'}),
      timeout: const Duration(seconds: 15),
    );
    return RemoteTask.fromJson(_decode(response) as Map<String, dynamic>);
  }

  Future<void> patchThread(String id, {String? title, bool? pinned}) async {
    final response = await _patch(
      '/api/threads/$id',
      body: jsonEncode({
        'title': ?title,
        'pinned': ?pinned,
      }),
    );
    _decode(response);
  }

  Future<void> deleteThread(String id) async {
    final response = await _delete('/api/threads/$id');
    _decode(response);
  }

  Future<RemoteUpload> upload({
    required String filename,
    required Uint8List bytes,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/api/uploads'));
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    return RemoteUpload.fromJson(_decode(response) as Map<String, dynamic>);
  }

  Future<GitStatus> gitStatus() async {
    final response = await http.get(_uri('/api/git'), headers: _headers);
    return GitStatus.fromJson(_decode(response) as Map<String, dynamic>);
  }

  Future<GitStatus> gitPull() async {
    final response = await http.post(_uri('/api/git/pull'), headers: _headers);
    return GitStatus.fromJson(_decode(response) as Map<String, dynamic>);
  }

  Future<GitStatus> gitCommit(String message) async {
    final response = await http.post(
      _uri('/api/git/commit'),
      headers: _headers,
      body: jsonEncode({'message': message}),
    );
    return GitStatus.fromJson(_decode(response) as Map<String, dynamic>);
  }

  Future<GitStatus> gitPush() async {
    final response = await http.post(_uri('/api/git/push'), headers: _headers);
    return GitStatus.fromJson(_decode(response) as Map<String, dynamic>);
  }

  Future<RemoteFsListing> listFiles({String path = ''}) async {
    final response = await http.get(_uri('/api/files').replace(queryParameters: {'path': path}), headers: _headers);
    return RemoteFsListing.fromJson(_decode(response) as Map<String, dynamic>);
  }

  Future<RemoteFileContent> readFile(String path) async {
    final response = await http.get(_uri('/api/files/content').replace(queryParameters: {'path': path}), headers: _headers);
    return RemoteFileContent.fromJson(_decode(response) as Map<String, dynamic>);
  }

  Future<void> writeFile(String path, String content) async {
    final response = await http.put(
      _uri('/api/files/content'),
      headers: _headers,
      body: jsonEncode({'path': path, 'content': content}),
    );
    _decode(response);
  }

  Future<Uint8List> downloadFile(String path) async {
    final response = await http.get(
      _uri('/api/files/download').replace(queryParameters: {'path': path}),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwIfNeeded(response);
    }
    return response.bodyBytes;
  }

  static dynamic _decode(http.Response response) {
    _throwIfNeeded(response);
    if (response.body.isEmpty) return <String, dynamic>{};
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  static void _throwIfNeeded(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    var message = '请求失败（${response.statusCode}）';
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map && body['detail'] != null) {
        message = body['detail'].toString();
      }
    } catch (_) {}
    throw ApiException(message, statusCode: response.statusCode);
  }
}
