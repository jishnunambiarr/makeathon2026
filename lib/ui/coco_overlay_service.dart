import 'package:flutter/material.dart';

/// Listenables shared between [AgentScreen] and [CocoAvatar] (output level + thinking).
class CocoOverlayService {
  CocoOverlayService._();
  static final CocoOverlayService instance = CocoOverlayService._();

  /// Default `.riv` for the voice tab; listed in `pubspec.yaml` (state machine inputs `audioLevel`, `thinking`).
  static const String defaultAvatarRivAsset =
      'assets/rive/554-1038-my-avatar.riv';

  /// Wire these from your voice session (same as [CocoAvatar] listenables).
  final ValueNotifier<double> outputAmplitude = ValueNotifier<double>(0);
  final ValueNotifier<bool> thinking = ValueNotifier<bool>(false);

  void resetAvatarState() {
    thinking.value = false;
    outputAmplitude.value = 0;
  }
}
