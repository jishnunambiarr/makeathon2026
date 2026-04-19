import 'package:flutter/material.dart';

/// Shared listenables for the Agent tab [CocoAvatar] (lip-sync + thinking).
///
/// Previously also hosted a global floating head; that layer was removed.
class CocoOverlayService {
  CocoOverlayService._();
  static final CocoOverlayService instance = CocoOverlayService._();

  /// Default Rive bundle for the voice avatar; must stay in sync with `pubspec.yaml`
  /// and [CocoAvatar] (default artboard state machine; inputs `audioLevel` / `thinking`).
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
