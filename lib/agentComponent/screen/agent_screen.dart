import 'dart:async';

import 'package:campus_flutter/agentComponent/services/agent_backend_service.dart';
import 'package:campus_flutter/agentComponent/tools/agent_client_tools.dart';
import 'package:campus_flutter/agentComponent/utils/agent_output_audio.dart';
import 'package:campus_flutter/main.dart';
import 'package:campus_flutter/ui/coco_avatar.dart';
import 'package:campus_flutter/ui/coco_overlay_service.dart';
import 'package:elevenlabs_agents/elevenlabs_agents.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:livekit_client/src/support/native_audio.dart' as lk_native;
// ignore: implementation_imports
import 'package:livekit_client/src/track/audio_management.dart' as lk_audio;
import 'package:rive/rive.dart' as rive;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tool names that should **not** flip the avatar into "thinking" (e.g. fast greeting fetch).
const _toolsWithoutThinkingIndicator = <String>{
  'get_user_status',
};

/// Wraps a client tool to fire [onStart] when the agent invokes it (before execution).
class _ThinkingHookTool implements ClientTool {
  _ThinkingHookTool({required this.delegate, required this.onStart});

  final ClientTool delegate;
  final VoidCallback onStart;

  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    onStart();
    return delegate.execute(parameters);
  }
}

Map<String, ClientTool> _wrapToolsForThinkingHook({
  required Map<String, ClientTool> tools,
  required VoidCallback onToolStart,
  Set<String> skipToolNames = _toolsWithoutThinkingIndicator,
}) {
  return {
    for (final e in tools.entries)
      e.key: skipToolNames.contains(e.key)
          ? e.value
          : _ThinkingHookTool(delegate: e.value, onStart: onToolStart),
  };
}

String _friendlyConnectError(Object e) {
  if (e is TimeoutException) {
    return 'Could not connect in time. Check your network and try again.';
  }
  final s = e.toString();
  if (s.contains('SocketException') || s.contains('Failed host lookup')) {
    return 'No connection to the server. Check your network and try again.';
  }
  if (s.contains('ClientException') || s.contains('Connection refused')) {
    return 'Could not reach the voice service. Please try again later.';
  }
  return 'Could not start the voice session. Please try again.';
}

String _friendlyAgentRuntimeError(String message, [String? ctx]) {
  final combined = ctx != null && ctx.isNotEmpty ? '$message $ctx' : message;
  final lower = combined.toLowerCase();
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return 'The connection timed out. Please try again.';
  }
  if (lower.contains('network') || lower.contains('socket')) {
    return 'A network error occurred. Please try again.';
  }
  if (combined.length > 140 ||
      combined.contains('\n') ||
      combined.contains('http://') ||
      combined.contains('https://') ||
      RegExp(r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}').hasMatch(combined)) {
    return 'Something went wrong. Please try again.';
  }
  return message;
}

/// Voice agent tab (Coco): ElevenLabs via WebRTC (official SDK) + backend-minted token.
class AgentScreen extends ConsumerStatefulWidget {
  const AgentScreen({super.key});

  @override
  ConsumerState<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends ConsumerState<AgentScreen> {
  late final ConversationClient _client;
  late final Map<String, ClientTool> _clientTools;

  CocoOverlayService get _coco => getIt<CocoOverlayService>();

  double _smoothedAmp = 0;

  String? _error;
  bool _busy = false;

  void _onToolExecutionStart() {
    if (!mounted) return;
    _coco.thinking.value = true;
  }

  void _onClientChanged() {
    final speaking = _client.isSpeaking;
    if (speaking) {
      _coco.thinking.value = false;
    }
    if (!speaking) {
      _smoothedAmp *= 0.88;
      if (_smoothedAmp < 0.015) {
        _smoothedAmp = 0;
      }
      _coco.outputAmplitude.value = _smoothedAmp;
    }
  }

  void _onAgentAudioChunk(String base64Chunk) {
    final instant = amplitudeFromAgentAudioBase64(base64Chunk);
    _smoothedAmp = _smoothedAmp * 0.78 + instant * 0.22;
    _coco.outputAmplitude.value = _smoothedAmp;
  }

  @override
  void initState() {
    super.initState();
    _clientTools = _wrapToolsForThinkingHook(
      tools: AgentClientTools.build(ref: ref),
      onToolStart: _onToolExecutionStart,
    );
    _client = ConversationClient(
      clientTools: _clientTools,
      callbacks: ConversationCallbacks(
        onConnect: ({required conversationId}) {
          setState(() {
            _error = null;
          });
        },
        onDisconnect: (details) {
          setState(() {});
        },
        onError: (message, [ctx]) {
          setState(() {
            _error = _friendlyAgentRuntimeError(message, ctx);
          });
        },
        onUnhandledClientToolCall: (toolCall) {
          setState(() {
            _error = 'That action is not available yet.';
          });
        },
        onModeChange: ({required mode}) {
          setState(() {});
        },
        onAudio: _onAgentAudioChunk,
      ),
    )..addListener(_onClientChanged);
  }

  @override
  void dispose() {
    _client.removeListener(_onClientChanged);
    _client.dispose();
    _coco.resetAvatarState();
    super.dispose();
  }

  bool get _connected =>
      _client.status == ConversationStatus.connected ||
      _client.status == ConversationStatus.connecting;

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        setState(() {
          _error = 'Microphone access is needed for voice.';
          _busy = false;
        });
        return;
      }

      final token = await AgentBackendService().fetchConversationToken();
      const sessionTimeout = Duration(seconds: 75);
      // Make sure iOS routes playback to the loud speaker (not the earpiece)
      // BEFORE LiveKit initializes the audio unit. Reconfiguring after the
      // session starts causes AURemoteIO `StartIO failed (-66637)` races.
      _installForceSpeakerOutputOverride();

      await _client
          .startSession(
            conversationToken: token,
            userId: AgentBackendService.defaultUserId(),
            overrides: ConversationOverrides(
              tts: TtsOverrides(useSpeakerBoost: true),
            ),
          )
          .timeout(sessionTimeout);
      await _client.setMicMuted(false);
    } catch (e) {
      setState(() {
        _error = _friendlyConnectError(e);
      });
      try {
        await _client.endSession();
      } catch (_) {
        // Clears stuck "connecting" after timeout or partial failure.
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  /// Patches LiveKit's `onConfigureNativeAudio` so every generated
  /// `playAndRecord` configuration routes to the iPhone loud speaker.
  ///
  /// We can't just call `Hardware.instance.setSpeakerphoneOn(true,
  /// forceSpeakerOutput: true)` after `startSession` — that reconfigures the
  /// AVAudioSession mid-stream and triggers `AUIOClient_StartIO failed
  /// (-66637)`. Installing the override *before* the SDK initializes the
  /// audio unit avoids the race.
  void _installForceSpeakerOutputOverride() {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    lk_audio.onConfigureNativeAudio = (state) async {
      final base = await lk_audio.defaultNativeAudioConfigurationFunc(state);
      if (base.appleAudioCategory != lk_native.AppleAudioCategory.playAndRecord) {
        return base;
      }
      return base.copyWith(
        appleAudioCategoryOptions: {
          ...?base.appleAudioCategoryOptions,
          lk_native.AppleAudioCategoryOption.defaultToSpeaker,
        },
        preferSpeakerOutput: true,
      );
    };
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    try {
      await _client.endSession();
    } finally {
      if (mounted) {
        _coco.resetAvatarState();
        _smoothedAmp = 0;
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = _connected;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: scheme.surfaceContainerHighest,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                child: Column(
                  children: [
                    Center(
                      child: ClipOval(
                        child: ColoredBox(
                          color: scheme.surface,
                          child: SizedBox(
                            width: 168,
                            height: 168,
                            child: CocoAvatar(
                              assetPath: CocoOverlayService.defaultAvatarRivAsset,
                              outputAmplitudeListenable: _coco.outputAmplitude,
                              thinkingListenable: _coco.thinking,
                              fit: rive.Fit.contain,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _StatusRow(
                      connected: connected,
                      label: _statusLabel(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                          height: 1.35,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (connected && _client.isMuted) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Microphone is muted — Coco cannot hear you.',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                setState(() => _busy = true);
                                try {
                                  await _client.setMicMuted(false);
                                } finally {
                                  if (mounted) setState(() => _busy = false);
                                }
                              },
                        icon: const Icon(Icons.mic, size: 18),
                        label: const Text('Unmute'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: (_busy || connected) ? null : _connect,
                            icon: const Icon(Icons.mic, size: 20),
                            label: Text(_busy ? 'Connecting…' : 'Start voice'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: (_busy || !connected) ? null : _disconnect,
                            icon: const Icon(Icons.stop_circle_outlined, size: 20),
                            label: const Text('Stop'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'What you can ask',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Examples — say it in your own words.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                children: const [
                  _CapabilityCard(
                    icon: Icons.description_outlined,
                    text:
                        'Send a homework sheet from Moodle to a messenger for you.',
                  ),
                  SizedBox(height: 10),
                  _CapabilityCard(
                    icon: Icons.event_note_outlined,
                    text:
                        'Check your calendar and the Mensa menu and summarize what matters.',
                  ),
                  SizedBox(height: 10),
                  _CapabilityCard(
                    icon: Icons.edit_calendar_outlined,
                    text: 'Add or update entries in your calendar.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel() {
    if (_client.status == ConversationStatus.disconnected) {
      return 'Ready to connect';
    }
    if (_client.status == ConversationStatus.connecting) {
      return 'Connecting…';
    }
    if (_client.isSpeaking) return 'Coco is speaking';
    return 'Listening for you';
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.connected,
    required this.label,
  });

  final bool connected;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dotColor = connected ? const Color(0xFF2E7D32) : scheme.outline;

    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
            boxShadow: connected
                ? [
                    BoxShadow(
                      color: dotColor.withValues(alpha: 0.45),
                      blurRadius: 6,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 26,
              color: scheme.primary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.4,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
