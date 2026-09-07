import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

class SessionController extends ChangeNotifier {
  static const _urlKey = 'uplink.baseUrl';
  static const _tokenKey = 'uplink.token';

  String baseUrl = '';
  String token = '';
  bool ready = false;
  bool get isLoggedIn => baseUrl.isNotEmpty && token.isNotEmpty;

  ApiClient get client {
    if (!isLoggedIn) {
      throw ApiException('尚未登录');
    }
    return ApiClient(baseUrl: baseUrl, token: token);
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString(_urlKey) ?? '';
    token = prefs.getString(_tokenKey) ?? '';
    ready = true;
    notifyListeners();
  }

  Future<void> login(String url, String nextToken) async {
    final cleanedUrl = url.trim().replaceAll(RegExp(r'/$'), '');
    final cleanedToken = nextToken.trim();
    if (cleanedUrl.isEmpty || cleanedToken.isEmpty) {
      throw ApiException('请填写服务器地址和口令');
    }
    if (!cleanedUrl.startsWith('http://') && !cleanedUrl.startsWith('https://')) {
      throw ApiException('地址需要以 http:// 或 https:// 开头');
    }
    await ApiClient.login(cleanedUrl, cleanedToken);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, cleanedUrl);
    await prefs.setString(_tokenKey, cleanedToken);
    baseUrl = cleanedUrl;
    token = cleanedToken;
    notifyListeners();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_urlKey);
    await prefs.remove(_tokenKey);
    baseUrl = '';
    token = '';
    notifyListeners();
  }
}
