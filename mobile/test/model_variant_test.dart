import 'package:flutter_test/flutter_test.dart';
import 'package:uplink/api/models.dart';
import 'package:uplink/state/model_variant.dart';

void main() {
  final grokCatalog = [
    AgentModelOption(id: 'cursor-grok-4.6-high', label: 'Grok'),
    AgentModelOption(id: 'cursor-grok-4.6-high-fast', label: 'Grok Fast'),
  ];

  test('splits grok effort and fast', () {
    final variant = parseModelVariant('cursor-grok-4.6-high-fast', grokCatalog);
    expect(variant.family, 'cursor-grok-4.6');
    expect(variant.effort, 'high');
    expect(variant.fast, isTrue);
    expect(variant.canFast, isTrue);
    expect(variant.efforts, containsAll(['low', 'medium', 'high', 'xhigh']));
    expect(variant.label, 'High Fast');
  });

  test('resolves fast off and effort change', () {
    expect(
      resolveVariantId(currentId: 'cursor-grok-4.6-high-fast', catalog: grokCatalog, effort: 'high', fast: false),
      'cursor-grok-4.6-high',
    );
    expect(
      resolveVariantId(currentId: 'cursor-grok-4.6-high', catalog: grokCatalog, effort: 'low', fast: true),
      'cursor-grok-4.6-low-fast',
    );
  });

  test('composer only toggles fast', () {
    final catalog = [
      AgentModelOption(id: 'composer-2.5', label: 'Composer'),
      AgentModelOption(id: 'composer-2.5-fast', label: 'Composer Fast'),
    ];
    final variant = parseModelVariant('composer-2.5', catalog);
    expect(variant.effort, isNull);
    expect(variant.canFast, isTrue);
    expect(variant.efforts, isEmpty);
    expect(resolveVariantId(currentId: 'composer-2.5', catalog: catalog, fast: true), 'composer-2.5-fast');
  });
}
