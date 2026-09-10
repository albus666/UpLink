import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  Ec2Instance? _info;
  List<SecurityGroupInfo> _groups = const [];
  String? _health;
  String? _error;
  String? _myIp;
  bool _busy = false;
  bool _prefilled = false;
  bool _editKeys = true;

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
      _editKeys = !aws.configured;
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
      if (mounted) setState(() => _editKeys = false);
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
      List<SecurityGroupInfo> groups = const [];
      try {
        groups = await aws.client.describeSecurityGroups(info.securityGroupIds);
      } on AwsException catch (error) {
        _error = '实例已读到，安全组失败：${error.message}';
      }
      String? health;
      if (info.publicIp.isNotEmpty) {
        health = await _pingHealth(info.publicIp);
      }
      try {
        _myIp = await fetchPublicIp();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _info = info;
        _groups = groups;
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
      return '8787 有响应';
    } catch (_) {
      return '8787 不通';
    }
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已复制$label')));
  }

  Future<void> _run(String action, Future<void> Function() fn, String confirm) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(action),
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

  Future<void> _addRule() async {
    if (_groups.isEmpty) {
      setState(() => _error = '还没有安全组');
      return;
    }
    final added = await showModalBottomSheet<_RuleDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PilotColors.surface,
      builder: (context) => _AddRuleSheet(groups: _groups, myIp: _myIp),
    );
    if (added == null || !mounted) return;
    if (added.cidr == '0.0.0.0/0') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('对整个互联网开放？'),
          content: Text('将把 ${added.protocolLabel} ${added.portLabel} 放行给 0.0.0.0/0。任何人都连得上。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('仍然添加')),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AwsSettings>().client.authorizeIngress(
            groupId: added.groupId,
            protocol: added.protocol,
            cidr: added.cidr,
            fromPort: added.fromPort,
            toPort: added.toPort,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已添加入站规则')));
      }
      await _refresh();
    } on AwsException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteRule(SgRule rule) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除规则'),
        content: Text('删除 ${rule.protocolLabel} ${rule.portLabel} ← ${rule.sourceLabel}？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: PilotColors.bad, foregroundColor: Colors.white),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AwsSettings>().client.revokeIngress(
            groupId: rule.groupId,
            protocol: rule.protocol,
            cidr: rule.cidr,
            fromPort: rule.fromPort,
            toPort: rule.toPort,
          );
      await _refresh();
    } on AwsException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AWS 服务器'),
        actions: [
          IconButton(tooltip: '刷新', onPressed: _busy ? null : _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _keysCard(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: PilotColors.bad, height: 1.4)),
          ],
          if (info != null) ...[
            const SizedBox(height: 16),
            _instanceCard(info),
            const SizedBox(height: 14),
            _powerRow(info),
            const SizedBox(height: 20),
            Row(
              children: [
                const Text('安全组入站', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _busy ? null : _addRule,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加规则'),
                ),
              ],
            ),
            if (_myIp != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('当前公网 IP  $_myIp', style: const TextStyle(color: PilotColors.muted, fontSize: 12)),
              ),
            if (_groups.isEmpty)
              const Text('没有读到入站规则', style: TextStyle(color: PilotColors.muted))
            else
              for (final group in _groups) _groupCard(group),
          ],
        ],
      ),
    );
  }

  Widget _keysCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('AWS 凭证', style: TextStyle(fontWeight: FontWeight.w700)),
              trailing: Icon(_editKeys ? Icons.expand_less : Icons.expand_more),
              onTap: () => setState(() => _editKeys = !_editKeys),
            ),
            if (_editKeys) ...[
              TextField(controller: _access, decoration: const InputDecoration(labelText: 'Access Key ID')),
              const SizedBox(height: 10),
              TextField(
                controller: _secret,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Secret Access Key'),
              ),
              const SizedBox(height: 10),
              TextField(controller: _region, decoration: const InputDecoration(labelText: '区域', hintText: 'ap-northeast-1')),
              const SizedBox(height: 10),
              TextField(controller: _instance, decoration: const InputDecoration(labelText: '实例 ID', hintText: 'i-xxxxxxxx')),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _saveKeys,
                  child: Text(_busy ? '正在连接 AWS…' : '保存并读取实例'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _instanceCard(Ec2Instance info) {
    final title = info.name.isEmpty ? info.id : info.name;
    final running = info.running;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: running ? PilotColors.goodDim : PilotColors.card,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _stateLabel(info.state),
                    style: TextStyle(color: running ? PilotColors.good : PilotColors.muted, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (info.name.isNotEmpty) _kv('实例', info.id),
            if (info.type.isNotEmpty) _kv('规格', info.type),
            _copyRow('公网', info.publicIp.isEmpty ? '无' : info.publicIp, info.publicIp),
            _kv('内网', info.privateIp.isEmpty ? '无' : info.privateIp),
            if (_health != null) ...[
              const SizedBox(height: 6),
              Text(
                _health!,
                style: TextStyle(color: _health!.contains('可访问') ? PilotColors.good : PilotColors.muted, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text('$label  $value', style: const TextStyle(color: PilotColors.muted, height: 1.4)),
    );
  }

  Widget _copyRow(String label, String display, String copyValue) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Expanded(child: Text('$label  $display', style: const TextStyle(color: PilotColors.muted, height: 1.4))),
          if (copyValue.isNotEmpty)
            IconButton(
              tooltip: '复制',
              visualDensity: VisualDensity.compact,
              onPressed: () => _copy(copyValue, label),
              icon: const Icon(Icons.copy, size: 16, color: PilotColors.muted),
            ),
        ],
      ),
    );
  }

  Widget _powerRow(Ec2Instance info) {
    final aws = context.read<AwsSettings>();
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: _busy || info.running
                ? null
                : () => _run('开机', () => aws.client.start(aws.instanceId), '确定开机？'),
            child: const Text('开机'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: _busy || info.stopped
                ? null
                : () => _run('关机', () => aws.client.stop(aws.instanceId), '确定关机？'),
            child: const Text('关机'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: _busy || !info.running
                ? null
                : () => _run('重启', () => aws.client.reboot(aws.instanceId), '确定重启？'),
            child: const Text('重启'),
          ),
        ),
      ],
    );
  }

  Widget _groupCard(SecurityGroupInfo group) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(group.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(group.id, style: const TextStyle(color: PilotColors.muted, fontSize: 12)),
            const SizedBox(height: 8),
            if (group.inbound.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('没有入站规则', style: TextStyle(color: PilotColors.muted)),
              )
            else
              for (final rule in group.inbound)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${rule.protocolLabel}  ${rule.portLabel}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    [
                      rule.sourceLabel,
                      if (rule.description.isNotEmpty) rule.description,
                    ].join(' · '),
                    style: const TextStyle(color: PilotColors.muted, fontSize: 12),
                  ),
                  trailing: rule.cidr.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '删除',
                          onPressed: _busy ? null : () => _deleteRule(rule),
                          icon: const Icon(Icons.delete_outline, color: PilotColors.bad, size: 20),
                        ),
                ),
          ],
        ),
      ),
    );
  }

  String _stateLabel(String state) {
    return switch (state) {
      'running' => '运行中',
      'stopped' => '已停止',
      'pending' => '启动中',
      'stopping' => '关机中',
      'shutting-down' => '终止中',
      'terminated' => '已终止',
      _ => state,
    };
  }
}

class _RuleDraft {
  const _RuleDraft({
    required this.groupId,
    required this.protocol,
    required this.cidr,
    this.fromPort,
    this.toPort,
  });

  final String groupId;
  final String protocol;
  final String cidr;
  final int? fromPort;
  final int? toPort;

  String get protocolLabel => protocol == '-1' ? '全部协议' : protocol.toUpperCase();
  String get portLabel {
    if (protocol == '-1') return '全部端口';
    if (fromPort == null) return '';
    if (toPort == null || toPort == fromPort) return '$fromPort';
    return '$fromPort-$toPort';
  }
}

class _AddRuleSheet extends StatefulWidget {
  const _AddRuleSheet({required this.groups, required this.myIp});

  final List<SecurityGroupInfo> groups;
  final String? myIp;

  @override
  State<_AddRuleSheet> createState() => _AddRuleSheetState();
}

class _AddRuleSheetState extends State<_AddRuleSheet> {
  late String _groupId = widget.groups.first.id;
  String _protocol = 'tcp';
  String _source = 'me';
  final _port = TextEditingController(text: '8787');
  final _cidr = TextEditingController();

  @override
  void dispose() {
    _port.dispose();
    _cidr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.myIp == null ? null : '${widget.myIp}/32';
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: PilotColors.line, borderRadius: BorderRadius.circular(99)))),
          const SizedBox(height: 12),
          const Text('添加入站规则', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(labelText: '安全组', isDense: true),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _groupId,
                isExpanded: true,
                items: [
                  for (final group in widget.groups)
                    DropdownMenuItem(value: group.id, child: Text('${group.name}  (${group.id})', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _groupId = value);
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final item in const [('tcp', 'TCP'), ('udp', 'UDP'), ('-1', '全部')])
                ChoiceChip(
                  label: Text(item.$2),
                  selected: _protocol == item.$1,
                  onSelected: (_) => setState(() => _protocol = item.$1),
                ),
            ],
          ),
          if (_protocol != '-1') ...[
            const SizedBox(height: 10),
            TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '端口', hintText: '22 或 8000-8010', isDense: true),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final item in const [('22', 'SSH 22'), ('80', 'HTTP 80'), ('443', 'HTTPS 443'), ('8787', 'Uplink 8787')])
                  ActionChip(label: Text(item.$2), onPressed: () => setState(() => _port.text = item.$1)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          const Text('来源', style: TextStyle(color: PilotColors.muted, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text(widget.myIp == null ? '当前 IP' : '当前 IP ${widget.myIp}'),
                selected: _source == 'me',
                onSelected: widget.myIp == null ? null : (_) => setState(() => _source = 'me'),
              ),
              ChoiceChip(label: const Text('任意 IPv4'), selected: _source == 'any', onSelected: (_) => setState(() => _source = 'any')),
              ChoiceChip(label: const Text('自定义'), selected: _source == 'custom', onSelected: (_) => setState(() => _source = 'custom')),
            ],
          ),
          if (_source == 'custom') ...[
            const SizedBox(height: 10),
            TextField(
              controller: _cidr,
              decoration: const InputDecoration(labelText: 'CIDR', hintText: '203.0.113.10/32', isDense: true),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              final cidr = switch (_source) {
                'me' => me,
                'any' => '0.0.0.0/0',
                _ => _cidr.text.trim(),
              };
              if (cidr == null || cidr.isEmpty) return;
              int? fromPort;
              int? toPort;
              if (_protocol != '-1') {
                final raw = _port.text.trim();
                if (raw.contains('-')) {
                  final parts = raw.split('-');
                  fromPort = int.tryParse(parts[0].trim());
                  toPort = int.tryParse(parts[1].trim());
                } else {
                  fromPort = int.tryParse(raw);
                  toPort = fromPort;
                }
                if (fromPort == null) return;
              }
              Navigator.pop(
                context,
                _RuleDraft(groupId: _groupId, protocol: _protocol, cidr: cidr, fromPort: fromPort, toPort: toPort),
              );
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }
}
