// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BzVisionCameraScreen extends StatefulWidget {
  const BzVisionCameraScreen({super.key});
  @override
  State<BzVisionCameraScreen> createState() => _BzVisionCameraScreenState();
}

class _BzVisionCameraScreenState extends State<BzVisionCameraScreen> {
  final _ipCtrl   = TextEditingController(text: 'http://192.168.1.');
  bool  _connected = false;
  bool  _connecting = false;
  String? _streamUrl;
  String? _error;

  // Présets d'URL courants pour Raspberry Pi
  final _presets = [
    {'label': 'Pi HTTP :8080',    'url': 'http://192.168.1.100:8080/?action=stream'},
    {'label': 'Pi HTTP :5000',    'url': 'http://192.168.1.100:5000/video_feed'},
    {'label': 'Pi MJPEG :8081',   'url': 'http://192.168.1.100:8081/stream.mjpg'},
  ];

  Future<void> _connect(String url) async {
    setState(() { _connecting = true; _error = null; });
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      setState(() {
        _streamUrl = url;
        _connected = true;
        _connecting = false;
      });
    }
  }

  void _disconnect() {
    setState(() { _connected = false; _streamUrl = null; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context)),
        title: Row(children: [
          Container(width: 8, height: 8,
            decoration: BoxDecoration(
              color: _connected ? Colors.green : Colors.red,
              shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(_connected ? 'CONNECTÉ' : 'BZVISION — CAMÉRA LIVE',
            style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1)),
        ]),
        actions: [
          if (_connected)
            TextButton.icon(
              onPressed: _disconnect,
              icon: const Icon(Icons.stop_circle_outlined, color: Colors.red, size: 18),
              label: const Text('Déconnecter',
                style: TextStyle(color: Colors.red, fontSize: 11))),
        ],
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      body: _connected ? _buildStream() : _buildConnect(),
    );
  }

  Widget _buildStream() {
    return Stack(children: [
      // Zone vidéo — placeholder (intégrer flutter_vlc_player ou webview pour vrai stream)
      Container(
        color: Colors.black,
        child: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.videocam, color: Colors.white24, size: 64),
            const SizedBox(height: 16),
            Text('Flux connecté', style: TextStyle(color: Colors.grey[600],
              fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_streamUrl ?? '', style: TextStyle(color: Colors.grey[800],
              fontSize: 10), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.green.withOpacity(0.3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.fiber_manual_record, color: Colors.green, size: 10),
                const SizedBox(width: 6),
                const Text('LIVE', style: TextStyle(color: Colors.green,
                  fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 2)),
              ])),
          ]),
        ),
      ),
      // Contrôles bas de page
      Positioned(bottom: 0, left: 0, right: 0,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter, end: Alignment.topCenter,
              colors: [Colors.black, Colors.transparent])),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _controlBtn(Icons.screenshot_monitor, 'Capture', Colors.white,
              () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Capture sauvegardée'),
                behavior: SnackBarBehavior.floating))),
            const SizedBox(width: 20),
            _controlBtn(Icons.zoom_in, 'Zoom +', Colors.white, () {}),
            const SizedBox(width: 20),
            _controlBtn(Icons.zoom_out, 'Zoom -', Colors.white, () {}),
          ]),
        )),
    ]);
  }

  Widget _controlBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.3))),
          child: Icon(icon, color: color, size: 22)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: color.withOpacity(0.7),
          fontSize: 10, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildConnect() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 20),
        // Icône
        Center(child: Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF22D3EE).withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF22D3EE).withOpacity(0.3))),
          child: const Icon(Icons.videocam_outlined,
            color: Color(0xFF22D3EE), size: 36))),
        const SizedBox(height: 20),
        const Center(child: Text('Connexion caméra Wi-Fi',
          style: TextStyle(color: Colors.white,
            fontWeight: FontWeight.w900, fontSize: 18))),
        Center(child: Text('Raspberry Pi • HTTP/MJPEG',
          style: TextStyle(color: Colors.grey[600], fontSize: 12))),

        const SizedBox(height: 32),

        // URL manuelle
        Text('URL DU FLUX', style: TextStyle(color: Colors.grey[400], fontSize: 10,
          fontWeight: FontWeight.w900, letterSpacing: 2)),
        const SizedBox(height: 10),
        TextField(
          controller: _ipCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 13,
            fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: 'http://192.168.1.100:8080/?action=stream',
            hintStyle: TextStyle(color: Colors.grey[700], fontSize: 11),
            prefixIcon: const Icon(Icons.link, color: Color(0xFF22D3EE), size: 18),
            filled: true, fillColor: const Color(0xFF0A0A0F),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: const Color(0xFF22D3EE).withOpacity(0.3))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: const Color(0xFF22D3EE).withOpacity(0.3))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF22D3EE), width: 1.5))),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity, height: 50,
          child: ElevatedButton.icon(
            onPressed: _connecting ? null : () => _connect(_ipCtrl.text.trim()),
            icon: _connecting
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Icon(Icons.wifi, size: 20),
            label: Text(_connecting ? 'Connexion...' : 'SE CONNECTER',
              style: const TextStyle(fontWeight: FontWeight.w900,
                fontSize: 13, letterSpacing: 1.5)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22D3EE), foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ),

        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withOpacity(0.3))),
            child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12))),
        ],

        const SizedBox(height: 32),

        // Présets rapides
        Text('ACCÈS RAPIDE', style: TextStyle(color: Colors.grey[400], fontSize: 10,
          fontWeight: FontWeight.w900, letterSpacing: 2)),
        const SizedBox(height: 10),
        ..._presets.map((p) =>
          GestureDetector(
            onTap: () {
              _ipCtrl.text = p['url']!;
              _connect(p['url']!);
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0F),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.07))),
              child: Row(children: [
                const Icon(Icons.play_circle_outline,
                  color: Color(0xFF22D3EE), size: 18),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p['label']!, style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w700, fontSize: 12)),
                  Text(p['url']!, style: TextStyle(color: Colors.grey[700],
                    fontSize: 10, fontFamily: 'monospace')),
                ]),
              ]),
            ),
          )
        ),

        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withOpacity(0.2))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, color: Colors.orange, size: 16),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'Assurez-vous que votre téléphone et le Raspberry Pi sont connectés au même réseau Wi-Fi. '
              'Le flux MJPEG est recommandé pour une faible latence.',
              style: TextStyle(color: Colors.orange[200], fontSize: 11, height: 1.5))),
          ]),
        ),
        const SizedBox(height: 30),
      ]),
    );
  }
}
