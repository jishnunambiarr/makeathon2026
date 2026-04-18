import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

/// Avatar driven by a Rive state machine.
///
/// **Rive 0.14** uses [File.asset] + [RiveWidgetController], not `RiveAnimation.asset`
/// or `StateMachineController`. Ensure your `.riv` defines a state machine named
/// [stateMachineName] (default `MainState`) with number input `audioLevel` and
/// boolean input `thinking`.
///
/// Call [CocoAvatarState.updateAmplitude] / [CocoAvatarState.setThinking] via a
/// [GlobalKey]:
/// ```dart
/// final _cocoKey = GlobalKey<CocoAvatarState>();
/// CocoAvatar(key: _cocoKey, assetPath: 'assets/rive/your_file_name.riv');
/// _cocoKey.currentState?.updateAmplitude(0.7);
/// ```
class CocoAvatar extends StatefulWidget {
  const CocoAvatar({
    super.key,
    required this.assetPath,
    this.stateMachineName = 'MainState',
    this.fit = Fit.contain,
    this.alignment = Alignment.center,
    this.outputAmplitudeListenable,
    this.thinkingListenable,
  });

  /// Bundle path, e.g. `assets/rive/coco.riv`.
  final String assetPath;

  /// Must match the state machine name in the Rive editor.
  final String stateMachineName;

  final Fit fit;
  final Alignment alignment;

  /// Real-time agent output level (0.0–1.0), e.g. from ElevenLabs [ConversationCallbacks.onAudio].
  final ValueListenable<double>? outputAmplitudeListenable;

  /// When true, drives the Rive `thinking` boolean input.
  final ValueListenable<bool>? thinkingListenable;

  @override
  State<CocoAvatar> createState() => CocoAvatarState();
}

class CocoAvatarState extends State<CocoAvatar> {
  /// How aggressively each [updateAmplitude] step moves toward the target (0–1).
  /// Higher = snappier; lower = smoother, less flicker.
  static const double _kAmplitudeSmoothing = 0.22;

  File? _file;
  RiveWidgetController? _riveController;
  NumberInput? _audioLevelInput;
  BooleanInput? _thinkingInput;
  Object? _loadError;

  /// Low-pass filtered level applied to Rive (updated via lerp in [updateAmplitude]).
  double _smoothedAmplitude = 0;

  void _onAmplitudeListenable() {
    final v = widget.outputAmplitudeListenable?.value ?? 0.0;
    updateAmplitude(v);
  }

  void _onThinkingListenable() {
    setThinking(widget.thinkingListenable?.value ?? false);
  }

  void _attachListenables() {
    widget.outputAmplitudeListenable?.removeListener(_onAmplitudeListenable);
    widget.thinkingListenable?.removeListener(_onThinkingListenable);
    widget.outputAmplitudeListenable?.addListener(_onAmplitudeListenable);
    widget.thinkingListenable?.addListener(_onThinkingListenable);
    _onAmplitudeListenable();
    _onThinkingListenable();
  }

  void _detachListenables() {
    widget.outputAmplitudeListenable?.removeListener(_onAmplitudeListenable);
    widget.thinkingListenable?.removeListener(_onThinkingListenable);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CocoAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.outputAmplitudeListenable != widget.outputAmplitudeListenable ||
        oldWidget.thinkingListenable != widget.thinkingListenable) {
      oldWidget.outputAmplitudeListenable?.removeListener(_onAmplitudeListenable);
      oldWidget.thinkingListenable?.removeListener(_onThinkingListenable);
      if (_riveController != null) {
        _attachListenables();
      }
    }
  }

  Future<void> _load() async {
    try {
      final file = await File.asset(
        widget.assetPath,
        riveFactory: Factory.rive,
      );
      if (file == null) {
        throw StateError('Failed to load Rive asset: ${widget.assetPath}');
      }

      final controller = RiveWidgetController(
        file,
        stateMachineSelector: StateMachineNamed(widget.stateMachineName),
      );

      // ignore: deprecated_member_use — state machine inputs; Data Binding optional upgrade later
      _audioLevelInput = controller.stateMachine.number('audioLevel');
      // ignore: deprecated_member_use
      _thinkingInput = controller.stateMachine.boolean('thinking');

      if (!mounted) {
        controller.dispose();
        file.dispose();
        return;
      }
      setState(() {
        _file = file;
        _riveController = controller;
        _loadError = null;
      });
      _attachListenables();
    } catch (e, st) {
      debugPrint('CocoAvatar load failed: $e\n$st');
      if (!mounted) return;
      setState(() => _loadError = e);
    }
  }

  /// Maps [volume] in `0.0`–`1.0` to the Rive number input `audioLevel`.
  ///
  /// Applies linear interpolation toward the new target each call so the mouth
  /// meter does not jump on every chunk.
  void updateAmplitude(double volume) {
    final target = volume.clamp(0.0, 1.0);
    final next = lerpDouble(
          _smoothedAmplitude,
          target,
          _kAmplitudeSmoothing,
        ) ??
        target;
    _smoothedAmplitude = next;

    final input = _audioLevelInput;
    if (input != null) {
      input.value = _smoothedAmplitude;
    }
  }

  /// Drives the Rive boolean input `thinking` (e.g. alternate animation while processing).
  void setThinking(bool thinking) {
    final input = _thinkingInput;
    if (input != null) {
      input.value = thinking;
    }
  }

  @override
  void dispose() {
    _detachListenables();
    _audioLevelInput?.dispose();
    _thinkingInput?.dispose();
    _riveController?.dispose();
    _file?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: Theme.of(context).colorScheme.error,
        ),
      );
    }
    final controller = _riveController;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return RiveWidget(
      controller: controller,
      fit: widget.fit,
      alignment: widget.alignment,
    );
  }
}
