import 'package:http/http.dart' as http;

import 'ec2_xml.dart';
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
    this.name = '',
    this.type = '',
  });

  final String id;
  final String state;
  final String publicIp;
  final String privateIp;
  final List<String> securityGroupIds;
  final String name;
  final String type;

  bool get running => state == 'running';
  bool get stopped => state == 'stopped';
}

class SgRule {
  const SgRule({
    required this.groupId,
    required this.groupName,
    required this.protocol,
    required this.cidr,
    this.fromPort,
    this.toPort,
    this.description = '',
  });

  final String groupId;
  final String groupName;
  final String protocol;
  final String cidr;
  final int? fromPort;
  final int? toPort;
  final String description;

  String get portLabel {
    if (protocol == '-1' || protocol == 'all') return '全部';
    if (fromPort == null && toPort == null) return '';
    if (fromPort != null && (toPort == null || toPort == fromPort)) return '$fromPort';
    return '$fromPort-$toPort';
  }

  String get protocolLabel {
    return switch (protocol) {
      '-1' || 'all' => '全部',
      'tcp' => 'TCP',
      'udp' => 'UDP',
      'icmp' => 'ICMP',
      _ => protocol.toUpperCase(),
    };
  }

  String get sourceLabel {
    if (cidr == '0.0.0.0/0') return '任意 IPv4';
    if (cidr == '::/0') return '任意 IPv6';
    if (cidr.endsWith('/32')) return cidr.substring(0, cidr.length - 3);
    return cidr;
  }
}

class SecurityGroupInfo {
  const SecurityGroupInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.inbound,
  });

  final String id;
  final String name;
  final String description;
  final List<SgRule> inbound;
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
    final reservations = xmlNamedItems(xml, 'reservationSet');
    final reservation = reservations.isEmpty ? null : reservations.first;
    final instances = reservation?.children('instancesSet') ?? xmlNamedItems(xml, 'instancesSet');
    final instance = instances.isEmpty ? null : instances.first;
    final body = instance?.body ?? xml;
    final id = xmlTag(body, 'instanceId');
    if (id == null) {
      throw AwsException(_awsMessage(xml) ?? '找不到这台实例');
    }
    final state = RegExp(r'<name>([^<]*)</name>').firstMatch(xmlInner(body, 'instanceState') ?? '')?.group(1) ??
        xmlTag(body, 'name') ??
        'unknown';
    var name = '';
    for (final tag in XmlItem(body).children('tagSet')) {
      if (tag.tag('key') == 'Name') {
        name = tag.tag('value') ?? '';
        break;
      }
    }
    return Ec2Instance(
      id: id,
      state: state,
      publicIp: xmlTag(body, 'ipAddress') ?? xmlTag(body, 'publicIpAddress') ?? '',
      privateIp: xmlTag(body, 'privateIpAddress') ?? '',
      securityGroupIds: XmlItem(body).children('groupSet').map((item) => item.tag('groupId') ?? '').where((id) => id.isNotEmpty).toList(),
      name: name,
      type: xmlTag(body, 'instanceType') ?? '',
    );
  }

  Future<List<SecurityGroupInfo>> describeSecurityGroups(List<String> groupIds) async {
    if (groupIds.isEmpty) return const [];
    final params = <String, String>{
      'Action': 'DescribeSecurityGroups',
      'Version': '2016-11-15',
    };
    for (var i = 0; i < groupIds.length; i++) {
      params['GroupId.${i + 1}'] = groupIds[i];
    }
    final xml = await _call(params);
    return parseSecurityGroups(xml);
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

  Future<void> authorizeIngress({
    required String groupId,
    required String protocol,
    required String cidr,
    int? fromPort,
    int? toPort,
    String description = 'uplink-app',
  }) async {
    try {
      await _call(_ingressParams(
        action: 'AuthorizeSecurityGroupIngress',
        groupId: groupId,
        protocol: protocol,
        cidr: cidr,
        fromPort: fromPort,
        toPort: toPort,
        description: description,
      ));
    } on AwsException catch (error) {
      final text = error.message.toLowerCase();
      if (text.contains('duplicate')) return;
      rethrow;
    }
  }

  Future<void> revokeIngress({
    required String groupId,
    required String protocol,
    required String cidr,
    int? fromPort,
    int? toPort,
  }) async {
    await _call(_ingressParams(
      action: 'RevokeSecurityGroupIngress',
      groupId: groupId,
      protocol: protocol,
      cidr: cidr,
      fromPort: fromPort,
      toPort: toPort,
    ));
  }

  Map<String, String> _ingressParams({
    required String action,
    required String groupId,
    required String protocol,
    required String cidr,
    int? fromPort,
    int? toPort,
    String? description,
  }) {
    final params = <String, String>{
      'Action': action,
      'Version': '2016-11-15',
      'GroupId': groupId,
      'IpPermissions.1.IpProtocol': protocol,
      'IpPermissions.1.IpRanges.1.CidrIp': cidr,
    };
    if (protocol != '-1') {
      params['IpPermissions.1.FromPort'] = '${fromPort ?? toPort ?? 0}';
      params['IpPermissions.1.ToPort'] = '${toPort ?? fromPort ?? 0}';
    }
    if (description != null && description.isNotEmpty) {
      params['IpPermissions.1.IpRanges.1.Description'] = description;
    }
    return params;
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
      final code = xmlTag(response.body, 'Code');
      if (code != null && code != 'Success') {
        throw AwsException(_awsMessage(response.body) ?? code);
      }
    }
    return response.body;
  }

  String _enc(String value) => Uri.encodeQueryComponent(value).replaceAll('+', '%20');

  String? _awsMessage(String xml) => xmlTag(xml, 'Message') ?? xmlTag(xml, 'Code');
}

List<SecurityGroupInfo> parseSecurityGroups(String xml) {
  final groups = <SecurityGroupInfo>[];
  for (final group in xmlNamedItems(xml, 'securityGroupInfo')) {
    final id = group.tag('groupId') ?? '';
    final name = group.tag('groupName') ?? id;
    if (id.isEmpty) continue;
    final inbound = <SgRule>[];
    for (final perm in group.children('ipPermissions')) {
      final protocol = perm.tag('ipProtocol') ?? 'tcp';
      final fromPort = int.tryParse(perm.tag('fromPort') ?? '');
      final toPort = int.tryParse(perm.tag('toPort') ?? '');
      final cidrs = perm.children('ipRanges');
      if (cidrs.isEmpty) {
        inbound.add(SgRule(
          groupId: id,
          groupName: name,
          protocol: protocol,
          fromPort: fromPort,
          toPort: toPort,
          cidr: perm.children('groups').map((item) => item.tag('groupId') ?? '').where((v) => v.isNotEmpty).join(', '),
          description: perm.tag('description') ?? '',
        ));
        continue;
      }
      for (final range in cidrs) {
        final cidr = range.tag('cidrIp') ?? '';
        if (cidr.isEmpty) continue;
        inbound.add(SgRule(
          groupId: id,
          groupName: name,
          protocol: protocol,
          fromPort: fromPort,
          toPort: toPort,
          cidr: cidr,
          description: range.tag('description') ?? '',
        ));
      }
    }
    groups.add(SecurityGroupInfo(
      id: id,
      name: name,
      description: group.tag('groupDescription') ?? '',
      inbound: inbound,
    ));
  }
  return groups;
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
