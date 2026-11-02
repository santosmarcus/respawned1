// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

// Full-screen local-file video preview — lets someone actually watch a
// video before submitting it, instead of the report form's play-icon
// thumbnail (which never played anything; tapping it just re-opened the
// file picker to replace that slot).
class RescueVideoPreviewPage extends StatefulWidget {
  final File file;
  const RescueVideoPreviewPage({super.key, required this.file});

  @override
  State<RescueVideoPreviewPage> createState() => _VideoPreviewPageState();
}

class _VideoPreviewPageState extends State<RescueVideoPreviewPage> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize()
          .then((_) {
            if (!mounted) return;
            setState(() => _ready = true);
            _controller.play();
          })
          .catchError((_) {
            if (!mounted) return;
            setState(() => _failed = true);
          });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _failed
            ? const Text(
                'Could not play this video.',
                style: TextStyle(color: Colors.white),
              )
            : !_ready
            ? const CircularProgressIndicator(color: Colors.white)
            : AspectRatio(
                aspectRatio: _controller.value.aspectRatio == 0
                    ? 16 / 9
                    : _controller.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(_controller),
                    GestureDetector(
                      onTap: () => setState(() {
                        _controller.value.isPlaying
                            ? _controller.pause()
                            : _controller.play();
                      }),
                      child: AnimatedOpacity(
                        opacity: _controller.value.isPlaying ? 0 : 1,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.play_circle_fill,
                          size: 64,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
