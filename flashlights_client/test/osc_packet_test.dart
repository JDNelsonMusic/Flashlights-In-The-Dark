import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flashlights_client/network/osc_packet.dart';

String _extractTypeTags(List<int> bytes) {
  final addressEnd = bytes.indexOf(0);
  expect(addressEnd, greaterThan(0));
  var index = (addressEnd + 4) & ~3;
  final tagEnd = bytes.indexOf(0, index);
  expect(tagEnd, greaterThan(index));
  return utf8.decode(bytes.sublist(index, tagEnd));
}

void main() {
  test('OSC encoder preserves 64-bit integers for large timestamps', () {
    const timestampMs = 1_763_000_123_456;
    final message = OSCMessage(
      '/sync',
      arguments: <Object>['reply', timestampMs],
    );
    final bytes = message.toBytes();

    expect(_extractTypeTags(bytes), ',sh');
  });

  test('OSC encoder writes doubles as 64-bit floats', () {
    final message = OSCMessage(
      '/event/trigger',
      arguments: <Object>[5, 12345.6789],
    );
    final bytes = message.toBytes();

    expect(_extractTypeTags(bytes), ',id');
  });
}
