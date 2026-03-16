// Minimal OSC message and socket utilities.
// Implements just enough of OSC encoding for this app.

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

class OSCMessage {
  final String address;
  final List<Object> arguments;

  OSCMessage(this.address, {List<Object> arguments = const []})
    : arguments = List<Object>.from(arguments);

  List<int> _stringBytes(String s) {
    final bytes = utf8.encode(s);
    final padded =
        BytesBuilder()
          ..add(bytes)
          ..addByte(0);
    final pad = (4 - (bytes.length + 1) % 4) % 4;
    if (pad > 0) padded.add(List.filled(pad, 0));
    return padded.toBytes();
  }

  List<int> toBytes() {
    final builder = BytesBuilder();
    builder.add(_stringBytes(address));

    final typeTags = StringBuffer(',');
    for (final arg in arguments) {
      if (arg is BigInt) {
        typeTags.write('h');
      } else if (arg is int) {
        if (arg < -2147483648 || arg > 2147483647) {
          typeTags.write('h');
        } else {
          typeTags.write('i');
        }
      } else if (arg is double) {
        typeTags.write('d');
      } else if (arg is String) {
        typeTags.write('s');
      } else {
        throw ArgumentError(
          'Unsupported OSC argument type: ${arg.runtimeType}',
        );
      }
    }
    builder.add(_stringBytes(typeTags.toString()));

    for (final arg in arguments) {
      if (arg is BigInt) {
        final b = ByteData(8)..setInt64(0, arg.toInt(), Endian.big);
        builder.add(b.buffer.asUint8List());
      } else if (arg is int) {
        if (arg < -2147483648 || arg > 2147483647) {
          final b = ByteData(8)..setInt64(0, arg, Endian.big);
          builder.add(b.buffer.asUint8List());
        } else {
          final b = ByteData(4)..setInt32(0, arg, Endian.big);
          builder.add(b.buffer.asUint8List());
        }
      } else if (arg is double) {
        final b = ByteData(8)..setFloat64(0, arg, Endian.big);
        builder.add(b.buffer.asUint8List());
      } else if (arg is String) {
        builder.add(_stringBytes(arg));
      } else {
        throw ArgumentError(
          'Unsupported OSC argument type: ${arg.runtimeType}',
        );
      }
    }

    return builder.toBytes();
  }
}

class OSCSocket {
  final InternetAddress serverAddress;
  final int serverPort;
  final InternetAddress destination;
  final int destinationPort;
  RawDatagramSocket? _socket;

  OSCSocket({
    required this.serverAddress,
    required this.serverPort,
    required this.destination,
    required this.destinationPort,
  });

  Future<void> _ensureSocket() async {
    _socket ??= await RawDatagramSocket.bind(
      serverAddress,
      serverPort,
      reuseAddress: true,
      reusePort: true,
    );
  }

  Future<void> bind() async {
    await _ensureSocket();
  }

  Future<void> close() async {
    _socket?.close();
    _socket = null;
  }

  Future<int> send(OSCMessage msg) async {
    await _ensureSocket();
    return _socket!.send(msg.toBytes(), destination, destinationPort);
  }

  Future<int> sendTo(
    OSCMessage msg, {
    required InternetAddress dest,
    required int port,
  }) async {
    await _ensureSocket();
    return _socket!.send(msg.toBytes(), dest, port);
  }

  RawDatagramSocket? get rawSocket => _socket;
}
