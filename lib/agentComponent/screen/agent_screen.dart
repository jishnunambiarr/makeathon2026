import 'package:campus_flutter/agentComponent/services/agent_backend_service.dart';
import 'package:campus_flutter/agentComponent/tools/agent_client_tools.dart';
import 'package:campus_flutter/agentComponent/utils/agent_output_audio.dart';
import 'package:campus_flutter/main.dart';
import 'package:campus_flutter/ui/coco_avatar.dart';
import 'package:campus_flutter/ui/coco_overlay_service.dart';
import 'package:elevenlabs_agents/elevenlabs_agents.dart';
import 'package:flutter/material.dart';
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

/// Voice agent tab: ElevenLabs Eva via WebRTC (official SDK) + backend-minted token.
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
  bool _lastSpeaking = false;

  String? _error;
  bool _busy = false;

  void _onToolExecutionStart() {
    if (!mounted) return;
    _coco.thinking.value = true;
  }

  void _onClientChanged() {
    final speaking = _client.isSpeaking;
    _coco.agentSpeaking.value = speaking;
    if (speaking && !_lastSpeaking) {
      _coco.thinking.value = false;
    }
    _lastSpeaking = speaking;
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
            _error = message;
          });
        },
        onUnhandledClientToolCall: (toolCall) {
          setState(() {
            _error =
                'Unhandled tool call: ${toolCall.toolName} (${toolCall.toolCallId})';
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
    _coco.resetOverlayPresentation();
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
          _error = 'Microphone permission is required for voice.';
          _busy = false;
        });
        return;
      }

      final token = await AgentBackendService().fetchConversationToken();
      await _client.startSession(
        conversationToken: token,
        userId: AgentBackendService.defaultUserId(),
        overrides: ConversationOverrides(
          tts: TtsOverrides(useSpeakerBoost: true),
        ),
      );
      await _client.setMicMuted(false);
      if (mounted) {
        _coco.overlayExpanded.value = false;
        _coco.voiceSessionActive.value = true;
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    try {
      await _client.endSession();
    } finally {
      if (mounted) {
        _coco.resetOverlayPresentation();
        _smoothedAmp = 0;
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = _connected;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CocoAvatar(
                          assetPath: CocoOverlayService.defaultAvatarRivAsset,
                          outputAmplitudeListenable: _coco.outputAmplitude,
                          thinkingListenable: _coco.thinking,
                          fit: rive.Fit.contain,
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: _StatusCard(
                          connected: connected,
                          statusLabel: _statusLabel(),
                          clientStatus: _client.status.name,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (connected && _client.isMuted) ...[
              const SizedBox(height: 8),
              Text(
                'Microphone is muted — the agent cannot hear you.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
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
                label: const Text('Unmute microphone'),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_busy || connected) ? null : _connect,
                    icon: const Icon(Icons.mic),
                    label: Text(_busy ? 'Connecting…' : 'Connect'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_busy || !connected) ? null : _disconnect,
                    icon: const Icon(Icons.stop),
                    label: const Text('Disconnect'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Backend: ${AgentBackendService.baseUrl}\n'
              'Set ELEVEN_AGENT_ID on the server (Eva agent). '
              'Flutter: --dart-define=AGENT_BACKEND_URL=…',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel() {
    if (_client.status == ConversationStatus.disconnected) {
      return 'Disconnected';
    }
    if (_client.status == ConversationStatus.connecting) {
      return 'Connecting…';
    }
    if (_client.isSpeaking) return 'Eva is speaking';
    return 'Listening…';
  }
}

class _StatusCard extends StatelessWidget {
  final bool connected;
  final String statusLabel;
  final String clientStatus;

  const _StatusCard({
    required this.connected,
    required this.statusLabel,
    required this.clientStatus,
  });

  @override
  Widget build(BuildContext context) {
    final dotColor = connected ? Colors.green : Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  statusLabel,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            clientStatus,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
