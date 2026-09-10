import '../api/models.dart';

const effortSuffixes = <String>[
  'thinking-max',
  'thinking-xhigh',
  'thinking-high',
  'thinking-medium',
  'thinking-low',
  'xhigh',
  'max',
  'medium',
  'high',
  'low',
  'none',
];

const effortLabels = <String, String>{
  'none': 'None',
  'low': 'Low',
  'medium': 'Medium',
  'high': 'High',
  'xhigh': 'Extra High',
  'max': 'Max',
  'thinking-low': 'Low Thinking',
  'thinking-medium': 'Medium Thinking',
  'thinking-high': 'Thinking',
  'thinking-xhigh': 'Extra High Thinking',
  'thinking-max': 'Max Thinking',
};

class ModelVariant {
  const ModelVariant({
    required this.id,
    required this.family,
    required this.effort,
    required this.fast,
    required this.efforts,
    required this.canFast,
  });

  final String id;
  final String family;
  final String? effort;
  final bool fast;
  final List<String> efforts;
  final bool canFast;

  String get label {
    final parts = <String>[
      if (effort != null) effortLabels[effort] ?? effort!,
      if (fast) 'Fast',
    ];
    return parts.isEmpty ? '默认' : parts.join(' ');
  }

  String? idFor({String? effort, required bool fast}) {
    final chosen = effort ?? this.effort;
    final base = chosen == null || chosen.isEmpty ? family : '$family-$chosen';
    if (fast) return '$base-fast';
    return base;
  }
}

bool _familyAllowsFast(String family) {
  final lower = family.toLowerCase();
  return lower.contains('composer') || lower.contains('grok') || lower.contains('gpt') || lower.contains('codex');
}

List<String> defaultEffortsFor(String family) {
  final lower = family.toLowerCase();
  if (lower.contains('grok')) {
    return ['low', 'medium', 'high', 'xhigh'];
  }
  if (lower.contains('claude') || lower.contains('sonnet') || lower.contains('opus')) {
    return ['thinking-low', 'thinking-medium', 'thinking-high'];
  }
  if (lower.contains('gpt') || lower.contains('codex')) {
    return ['low', 'medium', 'high'];
  }
  return [];
}

({String family, String? effort, bool fast}) splitModelId(String id) {
  var rest = id.trim();
  var fast = false;
  if (rest.endsWith('-fast')) {
    fast = true;
    rest = rest.substring(0, rest.length - 5);
  }
  for (final suffix in effortSuffixes) {
    final token = '-$suffix';
    if (rest == suffix) {
      return (family: rest, effort: null, fast: fast);
    }
    if (rest.endsWith(token)) {
      return (family: rest.substring(0, rest.length - token.length), effort: suffix, fast: fast);
    }
  }
  return (family: rest, effort: null, fast: fast);
}

ModelVariant parseModelVariant(String id, List<AgentModelOption> catalog) {
  final current = splitModelId(id);
  final family = current.family.isEmpty ? id : current.family;
  final efforts = <String>{};
  var canFast = false;
  for (final item in catalog) {
    final parsed = splitModelId(item.id);
    if (parsed.family != family) continue;
    if (parsed.fast) canFast = true;
    if (parsed.effort != null) efforts.add(parsed.effort!);
  }
  if (current.fast) canFast = true;
  if (current.effort != null) efforts.add(current.effort!);
  for (final extra in defaultEffortsFor(family)) {
    efforts.add(extra);
  }
  if (_familyAllowsFast(family)) canFast = true;
  final ordered = [
    for (final suffix in effortSuffixes)
      if (efforts.contains(suffix)) suffix,
  ];
  return ModelVariant(
    id: id,
    family: family,
    effort: current.effort,
    fast: current.fast,
    efforts: ordered,
    canFast: canFast,
  );
}

String? resolveVariantId({
  required String currentId,
  required List<AgentModelOption> catalog,
  String? effort,
  required bool fast,
}) {
  final variant = parseModelVariant(currentId, catalog);
  final wanted = variant.idFor(effort: effort, fast: fast);
  if (wanted == null) return null;
  final ids = catalog.map((item) => item.id).toSet();
  if (ids.contains(wanted)) return wanted;
  final withoutFast = variant.idFor(effort: effort, fast: false);
  if (withoutFast != null && ids.contains(withoutFast)) return withoutFast;
  final withFast = variant.idFor(effort: effort, fast: true);
  if (withFast != null && ids.contains(withFast)) return withFast;
  return wanted;
}
