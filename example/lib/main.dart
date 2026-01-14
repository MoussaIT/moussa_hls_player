import 'package:flutter/material.dart';
import 'package:moussa_hls_player/moussa_hls_player.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: PlayerTestPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class PlayerTestPage extends StatefulWidget {
  const PlayerTestPage({super.key});

  @override
  State<PlayerTestPage> createState() => _PlayerTestPageState();
}

class _PlayerTestPageState extends State<PlayerTestPage> {
  MoussaHlsPlayerController? controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Moussa HLS Player Test')),
      body: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: MoussaHlsPlayerView(
            onCreated: (c) async {
              controller = c;

              await controller!.setSource(
                qualities: const [
                  MoussaHlsQuality(label: 'Auto', url: 'https://example.com/master.m3u8'),
                  MoussaHlsQuality(label: '720p', url: 'https://example.com/720.m3u8'),
                  MoussaHlsQuality(label: '360p', url: 'https://example.com/360.m3u8'),
                ],
                initialQuality: 'Auto',
                autoPlay: true,
              );
            },
          ),
        ),
      ),
    );
  }
}
