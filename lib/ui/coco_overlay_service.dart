import 'package:campus_flutter/ui/coco_avatar.dart';
import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

/// Global floating Coco avatar layer, built once above the [Navigator] via
/// [MaterialApp.builder]. Drive [outputAmplitude] / [thinking] from the agent
/// (e.g. ElevenLabs) to keep the head in sync app-wide.
class CocoOverlayService {
  CocoOverlayService._();
  static final CocoOverlayService instance = CocoOverlayService._();

  bool _didInit = false;

  /// When true, shows the floating avatar above route transitions.
  final ValueNotifier<bool> visible = ValueNotifier<bool>(false);

  /// Wire these from your voice session (same as [CocoAvatar] listenables).
  final ValueNotifier<double> outputAmplitude = ValueNotifier<double>(0);
  final ValueNotifier<bool> thinking = ValueNotifier<bool>(false);

  /// Set from the voice client when the agent is outputting audio (TTS).
  final ValueNotifier<bool> agentSpeaking = ValueNotifier<bool>(false);

  /// User tapped the head to "pop" it larger; tuck again by tapping once more.
  final ValueNotifier<bool> overlayExpanded = ValueNotifier<bool>(false);

  /// Visual tuning: tucked corner size vs expanded "pop".
  static const double tuckedSize = 92;
  static const double expandedSize = 148;

  /// Idle (not speaking) vs speaking opacity.
  static const double idleOpacity = 0.8;
  static const double speakingOpacity = 1.0;

  /// Call once from the app [MaterialApp.builder] so the overlay exists for
  /// the whole app lifetime.
  void ensureInitialized() {
    if (_didInit) return;
    _didInit = true;
  }

  void resetOverlayPresentation() {
    agentSpeaking.value = false;
    overlayExpanded.value = false;
    thinking.value = false;
  }

  /// Paints [child] (the router / navigator subtree) under a global overlay [Stack].
  Widget wrapWithOverlay(Widget? child) {
    ensureInitialized();
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        if (child != null) child,
        ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (context, show, _) {
            if (!show) return const SizedBox.shrink();
            return const _CocoFloatingHead();
          },
        ),
      ],
    );
  }
}

class _CocoFloatingHead extends StatelessWidget {
  const _CocoFloatingHead();

  @override
  Widget build(BuildContext context) {
    final s = CocoOverlayService.instance;

    return ValueListenableBuilder<bool>(
      valueListenable: s.agentSpeaking,
      builder: (context, speaking, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: s.overlayExpanded,
          builder: (context, expanded, _) {
            final opacity =
                speaking ? CocoOverlayService.speakingOpacity : CocoOverlayService.idleOpacity;
            final side = expanded
                ? CocoOverlayService.expandedSize
                : CocoOverlayService.tuckedSize;

            return Positioned(
              right: 12,
              bottom: 88,
              child: Material(
                type: MaterialType.transparency,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    s.overlayExpanded.value = !s.overlayExpanded.value;
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    width: side,
                    height: side,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      opacity: opacity,
                      child: CocoAvatar(
                        assetPath: 'assets/rive/554-1038-my-avatar.riv',
                        outputAmplitudeListenable: s.outputAmplitude,
                        thinkingListenable: s.thinking,
                        fit: Fit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
