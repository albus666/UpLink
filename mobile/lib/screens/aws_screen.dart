import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../aws/ec2_client.dart';
import '../state/aws_settings.dart';
import '../theme.dart';

class AwsScreen extends StatefulWidget {
  const AwsScreen({super.key});

  @override
  State<AwsScreen> createState() => _AwsScreenState();
}

class _AwsScreenState extends State<AwsScreen> {
  final _access = TextEditingController();
  final _secret = TextEditingController();
  final _region = TextEditingController();
  final _instance = TextEditingController();
  Ec2Instance? _instanceInfo;
  String? _health;
  String? _error;
  bool _busy = false;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final aws = context.read<AwsSettings>();
    for (var i = 0; i < 50 && !aws.ready; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (!mounted) return;
    }
    if (!mounted || _prefilled) return;
    setState(() {
      _access.text = aws.accessKey;
      _secret.text = aws.secretKey;
      _region.text = aws.region;
      _instance.text = aws.instanceId;
      _prefilled = true;
    });
    if (aws.configured) {
      await _refresh();
    }
  }

  @override
  void dispose() {
    _access.dispose();
    _secret.dispose();
    _region.dispose();
    _instance.dispose();
    super.dispose();
  }

  Future<void> _saveKeys() async {
    if (_access.text.trim().isEmpty || _secret.text.trim().isEmpty || _instance.text.trim().isEmpty) {
      setState(() => _error = '请填写 Access Key、Secret 和实例 ID');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AwsSettings>().save(
            accessKey: _access.text,
            secretKey: _secret.text,
            region: _region.text,
            instanceId: _instance.text,
          );
      await _refresh();
    } on AwsException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final aws = context.read<AwsSettings>();
      final info = await aws.client.describe(aws.instanceId);
      String? health;
      if (info.publicIp.isNotEmpty) {
        health = await _pingHealth(info.publicIp);
      }
      if (!mounted) return;
      setState(() {
        _instanceInfo = info;
        _health = health;
      });
    } on AwsException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _pingHealth(String ip) async {
    try {
      final response = await http.get(Uri.parse('http://$ip:8787/api/health')).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200 && response.body.contains('"ok"')) {
        return 'Uplink 可访问';
      }
      return '8787 有响应但不是 health';
    } catch (_) {
      return '8787 连不上（多半是安全组没放行）';
    }
  }

  Future<void> _openPort(int port) async {
    final info = _instanceInfo;
    if (info == null || info.securityGroupIds.isEmpty) {
      setState(() => _error = '还没有安全组信息，先刷新状态');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final aws = context.read<AwsSettings>();
    try {
      final ip = await fetchPublicIp();
      for (final groupId in info.securityGroupIds) {
        await aws.client.openTcpPort(groupId: groupId, port: port, cidr: '$ip/32');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已把 $port 放行给你当前 IP $ip')),
      );
      await _refresh();
    } on AwsException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runInstance(String action, Future<void> Function() fn, String confirm) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认操作'),
        content: Text(confirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn();
      await Future<void>.delayed(const Duration(seconds: 2));
      await _refresh();
    } on AwsException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _instanceInfo;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AWS 服务器'),
        actions: [
          IconButton(onPressed: _busy ? null : _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text(
            '手机直接调 AWS API 管这台 EC2：看状态、开关机、给当前 IP 打开 8787。不经过 Uplink 后端，所以 8787 被挡住时也能用。',
            style: TextStyle(color: PilotColors.muted, height: 1.5),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _access,
            decoration: const InputDecoration(labelText: 'Access Key ID'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _secret,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Secret Access Key'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _region,
            decoration: const InputDecoration(labelText: '区域', hintText: 'ap-northeast-1'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _instance,
            decoration: const InputDecoration(labelText: '实例 ID', hintText: 'i-xxxxxxxx'),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _busy ? null : _saveKeys,
            child: Text(_busy ? '正在连接 AWS…' : '保存并读取实例'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: PilotColors.bad)),
          ],
          if (info != null) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(info.id, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text('状态  ${info.state}'),
                    Text('公网  ${info.publicIp.isEmpty ? '无' : info.publicIp}'),
                    Text('内网  ${info.privateIp.isEmpty ? '无' : info.privateIp}'),
                    if (_health != null) ...[
                      const SizedBox(height: 8),
                      Text(_health!, style: TextStyle(color: _health!.contains('可访问') ? PilotColors.good : PilotColors.accent)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _busy ? null : () => _openPort(8787),
              child: const Text('给当前 IP 打开 8787'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _busy ? null : () => _openPort(22),
              child: const Text('给当前 IP 打开 SSH 22'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () {
                            final aws = context.read<AwsSettings>();
                            _runInstance('开机', () => aws.client.start(aws.instanceId), '确定启动这台 EC2？按量计费会开始产生费用。');
                          },
                    child: const Text('开机'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () {
                            final aws = context.read<AwsSettings>();
                            _runInstance('关机', () => aws.client.stop(aws.instanceId), '确定停止这台 EC2？Uplink 会一起停掉。');
                          },
                    child: const Text('关机'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () {
                      final aws = context.read<AwsSettings>();
                      _runInstance('重启', () => aws.client.reboot(aws.instanceId), '确定重启这台 EC2？进行中的 Agent 任务会中断。');
                    },
              child: const Text('重启'),
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            '在 IAM 建一个只给这台实例用的用户，权限包含：ec2:DescribeInstances、StartInstances、StopInstances、RebootInstances、DescribeSecurityGroups、AuthorizeSecurityGroupIngress。不要把根账号密钥填进手机。',
            style: TextStyle(color: PilotColors.muted, height: 1.5, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
