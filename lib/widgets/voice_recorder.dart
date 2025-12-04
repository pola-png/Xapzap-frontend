import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

class VoiceRecorder extends StatefulWidget {
  final Function(String? path) onRecorded;

  const VoiceRecorder({super.key, required this.onRecorded});

  @override
  State<VoiceRecorder> createState() => _VoiceRecorderState();
}

class _VoiceRecorderState extends State<VoiceRecorder> {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _initRecorder();
  }

  Future<void> _initRecorder() async {
    await _recorder.openRecorder();
  }

  @override
  void dispose() {
    _recorder.closeRecorder();
    super.dispose();
  }

  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission is required to record voice comments.')),
      );
      return false;
    }
    return true;
  }

  Future<void> _startRecording() async {
    if (!await _ensureMicPermission()) return;
    final tempDir = Directory.systemTemp;
    final path = '${tempDir.path}/voice_comment_${DateTime.now().millisecondsSinceEpoch}.aac';
    await _recorder.startRecorder(toFile: path, codec: Codec.aacADTS);
    setState(() {
      _isRecording = true;
    });
  }

  Future<void> _finishRecording({required bool send}) async {
    if (!_isRecording) return;
    final path = await _recorder.stopRecorder();
    setState(() {
      _isRecording = false;
    });
    // Notify parent: null = cancelled, non-null = send
    widget.onRecorded(send ? path : null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_isRecording) {
      return InkWell(
        onTap: _startRecording,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mic, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Tap to record',
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Recording state: show wave + delete + send.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.16),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          // Simple animated "wave" using an indeterminate progress bar.
          SizedBox(
            width: 120,
            height: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                backgroundColor: theme.colorScheme.primary.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.delete, color: theme.colorScheme.onSurface),
            tooltip: 'Delete recording',
            onPressed: () => _finishRecording(send: false),
          ),
          IconButton(
            icon: Icon(Icons.send, color: theme.colorScheme.primary),
            tooltip: 'Send voice comment',
            onPressed: () => _finishRecording(send: true),
          ),
        ],
      ),
    );
  }
}
