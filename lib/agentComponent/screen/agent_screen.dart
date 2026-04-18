import 'package:campus_flutter/agentComponent/model/agent_state.dart';
import 'package:campus_flutter/agentComponent/services/agent_backend_service.dart';
import 'package:campus_flutter/agentComponent/tools/agent_client_tools.dart';
import 'package:campus_flutter/agentComponent/widgets/orb_widget.dart';
import 'package:elevenlabs_agents/elevenlabs_agents.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Voice agent tab: ElevenLabs Eva via WebRTC (official SDK) + backend-minted token.
class AgentScreen extends ConsumerStatefulWidget {
  const AgentScreen({super.key});

  @override
  ConsumerState<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends ConsumerState<AgentScreen> {
  late final ConversationClient _client;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _client = ConversationClient(
      clientTools: AgentClientTools.build(ref: ref),
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
      ),
    )..addListener(() {
        setState(() {});
      });
  }

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }

  AgentState get _orbState {
    switch (_client.status) {
      case ConversationStatus.disconnected:
      case ConversationStatus.disconnecting:
        return AgentState.idle;
      case ConversationStatus.connecting:
        return AgentState.thinking;
      case ConversationStatus.connected:
        if (_client.isSpeaking) return AgentState.talking;
        return AgentState.listening;
    }
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
      );
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
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _orbState;
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
                        child: OrbWidget(
                          state: s,
                          input: connected && !s.isTalking ? 0.35 : 0.1,
                          output: _client.isSpeaking ? 0.85 : 0.35,
                          color1: const Color(0xFFCADCFC),
                          color2: const Color(0xFFA0B9D1),
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

extension on AgentState {
  bool get isTalking => this == AgentState.talking;
}
