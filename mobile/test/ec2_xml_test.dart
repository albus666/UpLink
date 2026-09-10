import 'package:flutter_test/flutter_test.dart';
import 'package:uplink/aws/ec2_client.dart';
import 'package:uplink/aws/ec2_xml.dart';

void main() {
  test('parses inbound security group rules', () {
    const xml = '''
<DescribeSecurityGroupsResponse>
  <securityGroupInfo>
    <item>
      <groupId>sg-aaa</groupId>
      <groupName>web</groupName>
      <groupDescription>demo</groupDescription>
      <ipPermissions>
        <item>
          <ipProtocol>tcp</ipProtocol>
          <fromPort>8787</fromPort>
          <toPort>8787</toPort>
          <ipRanges>
            <item>
              <cidrIp>203.0.113.10/32</cidrIp>
              <description>uplink-app</description>
            </item>
          </ipRanges>
        </item>
        <item>
          <ipProtocol>tcp</ipProtocol>
          <fromPort>22</fromPort>
          <toPort>22</toPort>
          <ipRanges>
            <item>
              <cidrIp>0.0.0.0/0</cidrIp>
            </item>
          </ipRanges>
        </item>
      </ipPermissions>
    </item>
  </securityGroupInfo>
</DescribeSecurityGroupsResponse>
''';
    final groups = parseSecurityGroups(xml);
    expect(groups.single.id, 'sg-aaa');
    expect(groups.single.inbound.map((r) => '${r.portLabel}:${r.cidr}').toList(), [
      '8787:203.0.113.10/32',
      '22:0.0.0.0/0',
    ]);
    expect(xmlDirectItems(xmlInner(xml, 'ipPermissions')!).length, 2);
  });
}
