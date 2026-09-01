import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:teledepannage_shared/mjpeg/mjpeg_relay_bridge.dart';
import 'package:teledepannage_shared/teledepannage_shared.dart';
import 'package:teledepannage_ui/teledepannage_ui.dart';

/// Écran de télédépannage côté mobile : affiche le flux de la Pi en local,
/// le relaie vers la WebApp de supervision, et affiche les annotations
/// dessinées par l'opérateur par-dessus l'image.
///
/// Rien à modifier ici pour un premier test, à part éventuellement
/// [_piMjpegUrl] si l'IP de votre Raspberry Pi est différente.
class TeledepannageCameraScreen extends StatefulWidget {
  const TeledepannageCameraScreen({super.key});

  @override
  State<TeledepannageCameraScreen> createState() =>
      _TeledepannageCameraScreenState();
}

class _TeledepannageCameraScreenState
    extends State<TeledepannageCameraScreen> {
  // Adresse du relais déployé sur Render (celui qui est déjà en ligne).
  static const _relayServerUrl = 'wss://teledepannagebzbots.onrender.com';

  // Flux MJPEG de la Pi. Changez l'IP si la vôtre est différente.
  static const _piMjpegUrl = 'http://192.168.5.12:5002/video/live';

  // Identifiant de l'intervention. Pour un premier test, une valeur fixe
  // suffit — mobile et WebApp doivent utiliser exactement la même valeur
  // pour se retrouver dans la même "salle".
  static const _sessionId = 'intervention-test';

  late final ReconnectingRelayClient _relayClient;
  late final MjpegRelayBridge _bridge;
  final _board = StrokeBoard();

  Uint8List? _lastFrame;
  bool _connected = false;

  @override
  void initState() {
    super.initState();

    _relayClient = ReconnectingRelayClient(
      serverUri: Uri.parse(_relayServerUrl),
      sessionId: _sessionId,
      role: ClientRole.mobile,
    )..connect();

    _relayClient.connectionState.listen((connected) {
      setState(() => _connected = connected);
    });

    // Annotations dessinées par l'opérateur sur la WebApp : affichées ici.
    _relayClient.envelopes.listen(_board.applyEnvelope);

    _bridge = MjpegRelayBridge(
      mjpegStreamUri: Uri.parse(_piMjpegUrl),
      relayClient: _relayClient,
      onFrame: (frame) => setState(() => _lastFrame = frame),
    );
    _bridge.start();
  }

  @override
  void dispose() {
    _bridge.stop();
    _relayClient.close();
    _board.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Télédépannage — terrain'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Icon(
                _connected ? Icons.wifi : Icons.wifi_off,
                color: _connected ? Colors.greenAccent : Colors.redAccent,
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: TelestrationOverlay(
          board: _board, // lecture seule : pas de `onDraw` côté mobile
          child: _lastFrame == null
              ? const Text(
                  'En attente du flux vidéo de la Pi...',
                  style: TextStyle(color: Colors.white70),
                )
              : Image.memory(_lastFrame!, gaplessPlayback: true),
        ),
      ),
    );
  }
}
