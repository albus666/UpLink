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

  Future<WorkspaceInfo> workspace() async {
    final response = await http.get(_uri('/api/workspace'), headers: _headers);
    return WorkspaceInfo.fromJson(_decode(response) as Map<String, dynamic>);
  }

  Future<List<RemoteTask>> tasks() async {
    final response = await http.get(_uri('/api/tasks'), headers: _headers);
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
  }) async {
    final response = await http.post(
      _uri('/api/tasks'),
      headers: _headers,
      body: jsonEncode({
        'prompt': prompt,
        'upload_ids': uploadIds,
        'resume': resume,
      }),
    );
    return RemoteTask.fromJson(_decode(response) as Map<String, dynamic>);
  }

  Future<RemoteTask> task(String id) async {
    final response = await http.get(_uri('/api/tasks/$id'), headers: _headers);
    return RemoteTask.fromJson(_decode(response) as Map<String, dynamic>);
  }

  Future<void> cancel(String id) async {
    final response = await http.post(_uri('/api/tasks/$id/cancel'), headers: _headers);
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
