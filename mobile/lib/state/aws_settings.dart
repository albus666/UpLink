import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../aws/ec2_client.dart';

class AwsSettings extends ChangeNotifier {
  static const _accessKeyName = 'uplink.aws.accessKey';
  static const _secretKeyName = 'uplink.aws.secretKey';
  static const _regionName = 'uplink.aws.region';
  static const _instanceName = 'uplink.aws.instanceId';
  static const _tokenName = 'uplink.aws.sessionToken';

  String accessKey = '';
  String secretKey = '';
  String region = 'ap-northeast-1';
  String instanceId = 'i-05758e197265e3131';
  String sessionToken = '';
  bool ready = false;

  bool get configured => accessKey.isNotEmpty && secretKey.isNotEmpty && instanceId.isNotEmpty && region.isNotEmpty;

  Ec2Client get client {
    if (!configured) {
      throw AwsException('还没有填写 AWS 密钥');
    }
    return Ec2Client(
      accessKey: accessKey,
      secretKey: secretKey,
      region: region,
      sessionToken: sessionToken.isEmpty ? null : sessionToken,
    );
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    accessKey = prefs.getString(_accessKeyName) ?? '';
    secretKey = prefs.getString(_secretKeyName) ?? '';
    region = prefs.getString(_regionName) ?? 'ap-northeast-1';
    instanceId = prefs.getString(_instanceName) ?? 'i-05758e197265e3131';
    sessionToken = prefs.getString(_tokenName) ?? '';
    ready = true;
    notifyListeners();
  }

  Future<void> save({
    required String accessKey,
    required String secretKey,
    required String region,
    required String instanceId,
    String sessionToken = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    this.accessKey = accessKey.trim();
    this.secretKey = secretKey.trim();
    this.region = region.trim();
    this.instanceId = instanceId.trim();
    this.sessionToken = sessionToken.trim();
    await prefs.setString(_accessKeyName, this.accessKey);
    await prefs.setString(_secretKeyName, this.secretKey);
    await prefs.setString(_regionName, this.region);
    await prefs.setString(_instanceName, this.instanceId);
    await prefs.setString(_tokenName, this.sessionToken);
    notifyListeners();
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKeyName);
    await prefs.remove(_secretKeyName);
    await prefs.remove(_regionName);
    await prefs.remove(_instanceName);
    await prefs.remove(_tokenName);
    accessKey = '';
    secretKey = '';
    region = 'ap-northeast-1';
    instanceId = 'i-05758e197265e3131';
    sessionToken = '';
    notifyListeners();
  }
}
