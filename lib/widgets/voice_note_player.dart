import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import '../services/storage_service.dart';

class VoiceNotePlayer extends StatefulWidget {
  final String url;
  const VoiceNotePlayer({super.key, required this.url});

  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _ready = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _player.openPlayer();
    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    _player.closePlayer();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (!_ready) return;
    if (_playing) {
      await _player.stopPlayer();
      if (mounted) setState(() => _playing = false);
    } else {
      final signed = await WasabiService.getSignedUrl(widget.url);
      await _player.startPlayer(fromURI: signed, codec: Codec.defaultCodec, whenFinished: () {
        if (mounted) setState(() => _playing = false);
      });
      if (mounted) setState(() => _playing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
            onPressed: _toggle,
          ),
          const Text('Voice note'),
        ],
      ),
    );
  }
}
