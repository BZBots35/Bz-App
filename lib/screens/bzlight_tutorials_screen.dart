// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../services/lang_service.dart';
import '../widgets/lang_selector.dart';

class BzLightTutorialsScreen extends StatefulWidget {
  const BzLightTutorialsScreen({super.key});
  @override
  State<BzLightTutorialsScreen> createState() => _BzLightTutorialsScreenState();
}

class _BzLightTutorialsScreenState extends State<BzLightTutorialsScreen> {
  final _lang = LangService();

  @override
  void initState() {
    super.initState();
    _lang.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  Widget build(BuildContext context) {
    final tutorials = [
      {'title': _lang.t('cleaning'),     'desc': '', 'videoId': 'KrNA8CR_x9E', 'cat': _lang.t('maintenance')},
      {'title': _lang.t('deepCleaning'), 'desc': '', 'videoId': 'eARLGuMHqLU', 'cat': _lang.t('maintenance')},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.4),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context)),
        title: Text(_lang.t('tutorials').toUpperCase(),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900,
            letterSpacing: 1.5, fontSize: 13)),
        actions: const [LangSelector(), SizedBox(width: 8)],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: tutorials.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final t = tutorials[i];
          return GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => _VideoPlayerScreen(title: t['title']!, videoId: t['videoId']!))),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0F), borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.08))),
              child: Row(children: [
                ClipRRect(
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                  child: SizedBox(width: 110, height: 80,
                    child: Stack(fit: StackFit.expand, children: [
                      Image.network('https://img.youtube.com/vi/${t['videoId']}/hqdefault.jpg',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(color: Colors.grey[900])),
                      Container(color: Colors.black.withOpacity(0.3)),
                      const Center(child: Icon(Icons.play_circle_filled, color: Colors.white, size: 30)),
                    ])),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAB308).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4)),
                        child: Text(t['cat']!, style: const TextStyle(color: Color(0xFFEAB308),
                          fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1))),
                      const SizedBox(height: 6),
                      Text(t['title']!, style: const TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w700, fontSize: 13)),
                    ]),
                  ),
                ),
                Padding(padding: const EdgeInsets.only(right: 14),
                  child: Icon(Icons.chevron_right, color: Colors.grey[700], size: 20)),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _VideoPlayerScreen extends StatefulWidget {
  final String title, videoId;
  const _VideoPlayerScreen({required this.title, required this.videoId});
  @override
  State<_VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen> {
  late YoutubePlayerController _controller;
  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController(
      initialVideoId: widget.videoId,
      flags: const YoutubePlayerFlags(autoPlay: true, mute: false));
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return YoutubePlayerBuilder(
      player: YoutubePlayer(controller: _controller,
        showVideoProgressIndicator: true,
        progressIndicatorColor: const Color(0xFFEAB308)),
      builder: (context, player) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, elevation: 0,
          leading: IconButton(icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context)),
          title: Text(widget.title, style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.w900, fontSize: 14))),
        body: Column(children: [player])));
  }
}
