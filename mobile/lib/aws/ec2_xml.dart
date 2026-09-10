class XmlItem {
  const XmlItem(this.body);
  final String body;

  String? tag(String name) => xmlTag(body, name);

  List<XmlItem> children(String parentTag) {
    final inner = xmlInner(body, parentTag);
    if (inner == null) return const [];
    return xmlDirectItems(inner);
  }
}

String? xmlTag(String xml, String name) =>
    RegExp('<$name>([^<]*)</$name>').firstMatch(xml)?.group(1);

String? xmlInner(String xml, String name) {
  final start = xml.indexOf('<$name>');
  if (start < 0) return null;
  final openEnd = start + name.length + 2;
  final close = xml.indexOf('</$name>', openEnd);
  if (close < 0) return null;
  return xml.substring(openEnd, close);
}

List<XmlItem> xmlDirectItems(String xml) {
  final items = <XmlItem>[];
  var i = 0;
  while (true) {
    final start = xml.indexOf('<item>', i);
    if (start < 0) break;
    var depth = 1;
    var pos = start + 6;
    while (depth > 0) {
      final nextOpen = xml.indexOf('<item>', pos);
      final nextClose = xml.indexOf('</item>', pos);
      if (nextClose < 0) break;
      if (nextOpen >= 0 && nextOpen < nextClose) {
        depth++;
        pos = nextOpen + 6;
      } else {
        depth--;
        if (depth == 0) {
          items.add(XmlItem(xml.substring(start + 6, nextClose)));
          i = nextClose + 7;
        }
        pos = nextClose + 7;
      }
    }
    if (depth != 0) break;
  }
  return items;
}

List<XmlItem> xmlNamedItems(String xml, String parentTag) {
  final inner = xmlInner(xml, parentTag);
  if (inner == null) return const [];
  return xmlDirectItems(inner);
}
