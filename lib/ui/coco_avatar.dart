import 'dart:async' show Completer;

import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:rive/rive.dart' as rive;

/// Avoid overlapping [rive.File.decode] calls — a second parallel load on iOS
/// can fail while the Agent tab’s avatar succeeds.
Future<void> _decodeSerial = Future<void>.value();

Future<T> _serializedRiveDecode<T>(Future<T> Function() work) async {
  final previous = _decodeSerial;
  final done = Completer<void>();
  _decodeSerial = done.future;
  await previous;
  try {
    return await work();
  } finally {
    if (!done.isCompleted) done.complete();
  }
}

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
    this.fit = rive.Fit.contain,
    this.alignment = Alignment.center,
    this.outputAmplitudeListenable,
    this.thinkingListenable,
  });

  /// Bundle path, e.g. `assets/rive/coco.riv`.
  final String assetPath;

  /// Must match the state machine name in the Rive editor.
  final String stateMachineName;

  final rive.Fit fit;
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

  rive.File? _file;
  rive.RiveWidgetController? _riveController;
  rive.NumberInput? _audioLevelInput;
  rive.BooleanInput? _thinkingInput;
  Object? _loadError;
  int _loadAttempts = 0;

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
    // Wait for inherited [DefaultAssetBundle]; parallel [initState] loads can
    // race on some devices when using [rive.File.asset] from a cold start.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startLoad();
    });
  }

  void _startLoad() {
    if (!mounted) return;
    final bundle = DefaultAssetBundle.of(context);
    _load(bundle: bundle);
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

  Future<void> _load({required AssetBundle bundle}) async {
    try {
      final file = await _serializedRiveDecode(() async {
        final f = await rive.File.asset(
          widget.assetPath,
          riveFactory: rive.Factory.rive,
          bundle: bundle,
        );
        if (f == null) {
          throw StateError('Failed to load Rive asset: ${widget.assetPath}');
        }
        return f;
      });

      final controller = rive.RiveWidgetController(
        file,
        stateMachineSelector: rive.StateMachineNamed(widget.stateMachineName),
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
      if (_loadAttempts < 1) {
        _loadAttempts++;
        await Future<void>.delayed(const Duration(milliseconds: 180));
        if (!mounted) return;
        await _load(bundle: rootBundle);
        return;
      }
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
      final cs = Theme.of(context).colorScheme;
      return Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() {
              _loadError = null;
              _loadAttempts = 0;
            });
            _startLoad();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.refresh_rounded,
                size: 28,
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap to load avatar',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    final controller = _riveController;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return rive.RiveWidget(
      controller: controller,
      fit: widget.fit,
      alignment: widget.alignment,
    );
  }
}
