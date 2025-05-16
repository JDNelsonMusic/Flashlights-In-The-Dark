import 'package:flutter/material.dart';
import 'network/osc_listener.dart';
import 'model/client_state.dart';

void main() => runApp(const FlashlightsApp());

class FlashlightsApp extends StatelessWidget {
  const FlashlightsApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Bootstrap(),
  );
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});
  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  @override
  void initState() {
    super.initState();
    OscListener.instance.start(client.myIndex);
  }

  @override
  void dispose() {
    OscListener.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Text(
        'Singer #${client.myIndex}\nWaiting for cues…',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 20),
      ),
    ),
  );
}