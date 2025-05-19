import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'network/osc_listener.dart';
import 'dart:io';
import 'dart:convert';
import 'model/client_state.dart';

/// Native bootstrap that must finish **before** the widget tree is built.
Future<void> _bootstrapNative() async {
  if (Platform.isIOS || Platform.isAndroid) {
    // 1. Ask for runtime permissions (camera + microphone).
    await [
      Permission.camera,
      Permission.microphone,
    ].request();
  }

  // 2. On Android, spin up the foreground service so we survive backgrounding.
  if (Platform.isAndroid) {
    const MethodChannel ch = MethodChannel('ai.keex.flashlights/client');
    try {
      await ch.invokeMethod('startService');
    } on PlatformException catch (e) {
      debugPrint('[KeepAliveService] start failed: $e');
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _bootstrapNative();
  runApp(const FlashlightsApp());
}

class FlashlightsApp extends StatelessWidget {
  const FlashlightsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flashlights Client',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const Bootstrap(),
    );
  }
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  final bool _connected = false;

  @override
  void initState() {
    super.initState();
    OscListener.instance.start();
    _broadcastDiscovery();
  }
  
  /// Broadcast presence (slot and optional name) for auto-discovery.
  Future<void> _broadcastDiscovery() async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final msg = {
        'slot': client.myIndex.value,
        'name': '', // optional: provide user-defined name if desired
      };
      final data = utf8.encode(jsonEncode(msg));
      socket.send(data, InternetAddress('255.255.255.255'), 9001);
      socket.close();
    } catch (e) {
      debugPrint('[Discovery] Failed to broadcast: $e');
    }
  }

  @override
  void dispose() {
    OscListener.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _connected ? 'Waiting for cues…' : 'Connecting…';
    return Scaffold(
      body: Center(
        child: ValueListenableBuilder<int>(
          valueListenable: client.myIndex,
          builder: (context, myIndex, _) {
            return Text(
              'Singer #$myIndex\n$status',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20),
            );
          },
        ),
      ),
    );
  }
}
