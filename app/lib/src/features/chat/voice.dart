import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../l10n/app_localizations.dart';
import '../../app.dart';
import '../../core/media_cache.dart';
import '../../theme/cyberdog.dart';

/// The attachment kind and type of a voice message. A build that predates voice messages shows
/// one as a file and opens it in the system player, so nothing has to be negotiated.
const String kVoiceKind = 'audio';
const String kVoiceMime = 'audio/mp4';

/// Longest voice message the recorder will take, to keep one message a reasonable size.
const Duration kMaxVoiceLength = Duration(minutes: 5);

String _clock(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// The composer while a voice message is being recorded: elapsed time, cancel, send.
///
/// Recording starts when this appears. The audio is written to a file in the app's private temp
/// directory and that file is deleted as soon as it has been read — or straight away on cancel
/// or if the screen goes away — so no plain recording outlives the moment.
class VoiceRecordingBar extends StatefulWidget {
  const VoiceRecordingBar({super.key, required this.onDone, required this.onCancel});

  /// Called with the recorded audio when the user sends it.
  final Future<void> Function(Uint8List audio) onDone;

  /// Called when recording was cancelled, could not start, or produced nothing. [error] says
  /// why when there is something to tell the user.
  final void Function(String? error) onCancel;

  @override
  State<VoiceRecordingBar> createState() => _VoiceRecordingBarState();
}

class _VoiceRecordingBarState extends State<VoiceRecordingBar> {
  final _recorder = AudioRecorder();
  final _watch = Stopwatch();
  Timer? _tick;
  String? _path;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) widget.onCancel(AppLocalizations.of(context)!.voiceNoPermission);
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice-${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 32000,
          sampleRate: 22050,
          numChannels: 1,
        ),
        path: path,
      );
      _path = path;
      if (!mounted) {
        await _discard();
        return;
      }
      _watch.start();
      _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        if (_watch.elapsed >= kMaxVoiceLength) {
          _finish(send: true);
        } else {
          setState(() {});
        }
      });
      setState(() {});
    } catch (e) {
      await _discard();
      if (mounted) widget.onCancel(e.toString());
    }
  }

  /// Stop the recorder and remove whatever it wrote.
  Future<void> _discard() async {
    try {
      await _recorder.stop();
    } catch (_) {}
    final path = _path;
    _path = null;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  Future<void> _finish({required bool send}) async {
    if (_finishing) return;
    _finishing = true;
    _tick?.cancel();
    _watch.stop();
    if (!send || _path == null) {
      await _discard();
      if (mounted) widget.onCancel(null);
      return;
    }
    Uint8List? audio;
    try {
      final path = await _recorder.stop() ?? _path!;
      final file = File(path);
      audio = await file.readAsBytes();
      await file.delete();
      _path = null;
    } catch (_) {
      await _discard();
    }
    if (!mounted) return;
    if (audio == null || audio.isEmpty) {
      widget.onCancel(null);
    } else {
      await widget.onDone(audio);
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    // Leaving mid-recording: nothing is sent and the file must not stay behind.
    unawaited(_discard().whenComplete(_recorder.dispose));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            IconButton(
              key: const ValueKey('voice-cancel'),
              tooltip: l10n.cancel,
              onPressed: () => _finish(send: false),
              icon: const Icon(Icons.delete_outline),
            ),
            const SizedBox(width: 8),
            Icon(Icons.fiber_manual_record, size: 14, color: scheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${l10n.voiceRecording} ${_clock(_watch.elapsed)}',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
            IconButton.filled(
              key: const ValueKey('voice-send'),
              tooltip: l10n.voiceSend,
              onPressed: _path == null ? null : () => _finish(send: true),
              icon: const Icon(Icons.arrow_upward),
            ),
          ],
        ),
      ),
    );
  }
}

/// A voice message in a bubble: play/pause, a seek bar and the time.
///
/// The audio is decrypted to the core's private scratch directory the first time it is played
/// (the same place and lifetime as a video opened from a chat) and played from there.
class VoiceBubble extends StatefulWidget {
  const VoiceBubble({super.key, required this.mediaId, required this.mine});

  final String mediaId;
  final bool mine;

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  final _player = AudioPlayer();
  final _subs = <StreamSubscription<dynamic>>[];
  Duration _position = Duration.zero;
  Duration _length = Duration.zero;
  bool _playing = false;
  bool _loaded = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _subs.add(_player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    }));
    _subs.add(_player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _length = d);
    }));
    _subs.add(_player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    }));
    _subs.add(_player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _position = Duration.zero;
        });
      }
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final core = NightdropScope.of(context);
    try {
      if (_playing) {
        await _player.pause();
        return;
      }
      if (!_loaded) {
        final path = await MediaCache.files.putIfAbsent(
          widget.mediaId,
          () => core.mediaToFile(widget.mediaId, 'm4a'),
        );
        await _player.setSource(DeviceFileSource(path));
        _loaded = true;
      }
      await _player.resume();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final ink = widget.mine ? Colors.white : scheme.onSurface;
    final total = _length.inMilliseconds;
    final at = total == 0 ? 0.0 : (_position.inMilliseconds / total).clamp(0.0, 1.0);
    return SizedBox(
      width: 230,
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('voice-play'),
            tooltip: _playing ? l10n.voicePause : l10n.voicePlay,
            onPressed: _failed ? null : _toggle,
            color: ink,
            icon: Icon(_failed
                ? Icons.error_outline
                : _playing
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill),
            iconSize: 34,
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: widget.mine ? Colors.white : CyberDog.accentLight,
                thumbColor: widget.mine ? Colors.white : CyberDog.accentLight,
                inactiveTrackColor: ink.withValues(alpha: 0.25),
              ),
              child: Slider(
                value: at,
                onChanged: total == 0
                    ? null
                    : (v) => _player.seek(Duration(milliseconds: (v * total).round())),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _clock(_playing || _position > Duration.zero ? _position : _length),
            style: TextStyle(fontSize: 12, color: ink.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }
}
