import 'dart:async';

import 'package:audio_buffering_demo/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

typedef AudioErrorWidgetBuilder = Widget Function(
  BuildContext context,
  Object error,
  StackTrace? stackTrace,
);

class AudioTrackPlayerWidget2 extends StatefulWidget {
  final String url;
  final String fileName;
  final int index;
  final AudioErrorWidgetBuilder errorBuilder;

  const AudioTrackPlayerWidget2({
    Key? key,
    required this.index,
    required this.fileName,
    required this.url,
    required this.errorBuilder,
  }) : super(key: key);

  @override
  State<AudioTrackPlayerWidget2> createState() =>
      _AudioTrackPlayerWidget2State();
}

class _AudioTrackPlayerWidget2State extends State<AudioTrackPlayerWidget2> {
  late final _logger = Logger(_AudioTrackPlayerWidget2State);

  String get url => widget.url;

  final player = AudioPlayer();

  bool isRequest = true;

  Future<void> _loadDuration() async {
    var response = await http.get(Uri.parse(widget.url));
    if (response.statusCode > 200 || response.statusCode < 299) {
      final bytes = response.bodyBytes;
      final contentType = response.headers['content-type'];

      var source = ByteAudioSource(bytes, contentType);
      player.setAudioSource(source);

      setState(() {
        isRequest = false;
      });
    } else {
      throw Exception('Failed to load audio');
    }
  }


  @override
  void initState() {
    super.initState();
    Future.microtask(() => _loadDuration());
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isRequest) {
      return const Center(child: CircularProgressIndicator());
    }
    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          _logger.log(snapshot.error);
          return widget.errorBuilder(context, snapshot.error!, snapshot.stackTrace);
        } else {
          final playerState = snapshot.data;
          final processingState = playerState?.processingState;
          if (processingState == ProcessingState.ready ||
              processingState == ProcessingState.completed ||
              processingState == ProcessingState.buffering) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Audio Player
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Duration Position Builder (time elapsed)
                      _buildDuration(
                        player.positionStream,
                        maxDuration: player.duration,
                      ),

                      // Slider to view & change Duration Position
                      _buildPositionBar(
                        player.positionStream,
                        maxDuration: player.duration,
                        onChanged: (value) =>
                            player.seek(Duration(seconds: value.toInt())),
                      ),

                      // Total Duration
                      Text(audioPosition(player.duration)),
                    ],
                  ),
                ),

                // Audio Player Controls
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Play/Pause Button
                    _buildPlayButton(
                      player.playingStream,
                      play: player.play,
                      pause: player.pause,
                      restart: () => player.seek(Duration.zero),
                      completed: processingState == ProcessingState.completed,
                    ),

                    // Mute/UnMute button
                    _buildVolumeButton(
                      player.volumeStream,
                      mute: () => player.setVolume(0),
                      unmute: () => player.setVolume(1),
                    ),
                  ],
                ),
              ],
            );
          } else if (processingState == ProcessingState.idle) {
            // Error in Loading AudioSource
            return widget.errorBuilder(
              context,
              ErrorDescription('${player.audioSource} Loading Error'),
              snapshot.stackTrace,
            );
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        }
      },
    );
  }

  StreamBuilder<bool> _buildPlayButton(
    Stream<bool> stream, {
    VoidCallback? play,
    VoidCallback? pause,
    VoidCallback? restart,
    required bool completed,
  }) {
    return StreamBuilder<bool>(
      stream: stream,
      builder: (context, snapshot) {
        final playing = snapshot.data;
        if (playing != true) {
          return IconButton(
            icon: const Icon(Icons.play_arrow),
            onPressed: play,
          );
        } else if (completed) {
          return IconButton(
            icon: const Icon(Icons.replay),
            onPressed: restart,
          );
        } else {
          return IconButton(
            icon: const Icon(Icons.pause),
            onPressed: pause,
          );
        }
      },
    );
  }

  StreamBuilder<Duration> _buildDuration(
    Stream<Duration> stream, {
    Duration? maxDuration,
  }) {
    return StreamBuilder<Duration>(
      stream: stream,
      builder: (context, snapshot) {
        final position = snapshot.data;
        return Text(
          audioPosition(position),
        );
      },
    );
  }

  StreamBuilder<Duration> _buildPositionBar(
    Stream<Duration> stream, {
    Duration? maxDuration,
    ValueChanged<double>? onChanged,
  }) {
    return StreamBuilder<Duration>(
      stream: stream,
      builder: (context, snapshot) {
        return Flexible(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackShape: const RectangularSliderTrackShape(),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
            ),
            child: Slider(
              value: snapshot.data?.inSeconds.toDouble() ?? 0,
              max: maxDuration?.inSeconds.toDouble() ?? 0,
              onChanged: onChanged,
            ),
          ),
        );
      },
    );
  }

  StreamBuilder<double> _buildVolumeButton(Stream<double> stream,
      {VoidCallback? mute, VoidCallback? unmute}) {
    return StreamBuilder<double>(
      stream: stream,
      builder: (context, snapshot) {
        return snapshot.data == 0
            ? IconButton(icon: const Icon(Icons.volume_off), onPressed: unmute)
            : IconButton(icon: const Icon(Icons.volume_up), onPressed: mute);
      },
    );
  }
}

class ByteAudioSource extends StreamAudioSource {
  final List<int> bytes;
  final String? contentType;

  ByteAudioSource(this.bytes, this.contentType);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= bytes.length;
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(bytes.sublist(start, end)),
      contentType: contentType ?? 'audio/mp3',
    );
  }
}

String audioPosition(Duration? duration) {
  if (duration == null) return "";
  var min = duration.inMinutes;
  var secs = duration.inSeconds.remainder(60);
  var secondsPadding = secs < 10 ? "0" : "";
  return "$min:$secondsPadding$secs";
}