import 'package:http/http.dart' as http;

import 'sigv4.dart';

class AwsException implements Exception {
  AwsException(this.message);
  final String message;

  @override
  String toString() => message;
}

class Ec2Instance {
  const Ec2Instance({
    required this.id,
    required this.state,
    required this.publicIp,
    required this.privateIp,
    required this.securityGroupIds,
  });

  final String id;
  final String state;
  final String publicIp;
  final String privateIp;
  final List<String> securityGroupIds;

  bool get running => state == 'running';
}

class Ec2Client {
  Ec2Client({
    required this.accessKey,
    required this.secretKey,
    required this.region,
    this.sessionToken,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String accessKey;
  final String secretKey;
  final String region;
  final String? sessionToken;
  final http.Client _http;

  Future<Ec2Instance> describe(String instanceId) async {
    final xml = await _call({
      'Action': 'DescribeInstances',
      'Version': '2016-11-15',
      'InstanceId.1': instanceId,
    });
    final id = _firstTag(xml, 'instanceId');
    if (id == null) {
      throw AwsException(_awsMessage(xml) ?? '找不到这台实例');
    }
    final state = RegExp(r'<instanceState>\s*<code>[^<]*</code>\s*<name>([^<]*)</name>')
            .firstMatch(xml)
            ?.group(1) ??
        'unknown';
    return Ec2Instance(
      id: id,
      state: state,
      publicIp: _firstTag(xml, 'ipAddress') ?? _firstTag(xml, 'publicIpAddress') ?? '',
      privateIp: _firstTag(xml, 'privateIpAddress') ?? '',
      securityGroupIds: _allTags(xml, 'groupId'),
    );
  }

  Future<void> start(String instanceId) async {
    await _call({
      'Action': 'StartInstances',
      'Version': '2016-11-15',
      'InstanceId.1': instanceId,
    });
  }

  Future<void> stop(String instanceId) async {
    await _call({
      'Action': 'StopInstances',
      'Version': '2016-11-15',
      'InstanceId.1': instanceId,
    });
  }

  Future<void> reboot(String instanceId) async {
    await _call({
      'Action': 'RebootInstances',
      'Version': '2016-11-15',
      'InstanceId.1': instanceId,
    });
  }

  Future<void> openTcpPort({
    required String groupId,
    required int port,
    required String cidr,
  }) async {
    try {
      await _call({
        'Action': 'AuthorizeSecurityGroupIngress',
        'Version': '2016-11-15',
        'GroupId': groupId,
        'IpPermissions.1.IpProtocol': 'tcp',
        'IpPermissions.1.FromPort': '$port',
        'IpPermissions.1.ToPort': '$port',
        'IpPermissions.1.IpRanges.1.CidrIp': cidr,
        'IpPermissions.1.IpRanges.1.Description': 'uplink-app',
      });
    } on AwsException catch (error) {
      final text = error.message.toLowerCase();
      if (text.contains('duplicate')) return;
      rethrow;
    }
  }

  Future<String> _call(Map<String, String> params) async {
    final body = params.entries.map((e) => '${_enc(e.key)}=${_enc(e.value)}').join('&');
    final uri = Uri.parse('https://ec2.$region.amazonaws.com/');
    final signer = AwsSigV4(
      accessKey: accessKey,
      secretKey: secretKey,
      region: region,
      service: 'ec2',
      sessionToken: sessionToken,
    );
    final headers = signer.headers(method: 'POST', uri: uri, body: body, now: DateTime.now());
    final response = await _http.post(uri, headers: headers, body: body);
    if (response.statusCode >= 400) {
      throw AwsException(_awsMessage(response.body) ?? 'AWS 返回 ${response.statusCode}');
    }
    if (response.body.contains('<Code>')) {
      final code = _firstTag(response.body, 'Code');
      if (code != null && code != 'Success') {
        throw AwsException(_awsMessage(response.body) ?? code);
      }
    }
    return response.body;
  }

  String _enc(String value) => Uri.encodeQueryComponent(value).replaceAll('+', '%20');

  String? _firstTag(String xml, String name) =>
      RegExp('<$name>([^<]*)</$name>').firstMatch(xml)?.group(1);

  List<String> _allTags(String xml, String name) =>
      RegExp('<$name>([^<]*)</$name>').allMatches(xml).map((m) => m.group(1)!).toSet().toList();

  String? _awsMessage(String xml) => _firstTag(xml, 'Message') ?? _firstTag(xml, 'Code');
}

Future<String> fetchPublicIp() async {
  final response = await http.get(Uri.parse('https://checkip.amazonaws.com'));
  if (response.statusCode != 200) {
    throw AwsException('无法获取当前公网 IP');
  }
  final ip = response.body.trim();
  if (ip.isEmpty) throw AwsException('无法获取当前公网 IP');
  return ip;
}
