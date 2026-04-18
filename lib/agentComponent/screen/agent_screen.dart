import 'package:campus_flutter/agentComponent/model/agent_state.dart';
import 'package:campus_flutter/agentComponent/widgets/orb_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final agentUiStateProvider =
    NotifierProvider<AgentUiController, AgentUiState>(AgentUiController.new);

class AgentUiState {
  final AgentState state;
  final bool connected;
  final double input;
  final double output;

  const AgentUiState({
    required this.state,
    required this.connected,
    required this.input,
    required this.output,
  });

  AgentUiState copyWith({
    AgentState? state,
    bool? connected,
    double? input,
    double? output,
  }) {
    return AgentUiState(
      state: state ?? this.state,
      connected: connected ?? this.connected,
      input: input ?? this.input,
      output: output ?? this.output,
    );
  }
}

class AgentUiController extends Notifier<AgentUiState> {
  @override
  AgentUiState build() {
    return const AgentUiState(
      state: AgentState.idle,
      connected: false,
      input: 0,
      output: 0.3,
    );
  }

  void connect() {
    // TODO: Replace with ElevenLabs realtime session init via backend token.
    state = state.copyWith(connected: true, state: AgentState.listening);
  }

  void disconnect() {
    // TODO: Tear down ElevenLabs session.
    state = state.copyWith(connected: false, state: AgentState.idle);
  }

  void setState(AgentState s) => state = state.copyWith(state: s);

  void setVolumes({double? input, double? output}) {
    state = state.copyWith(
      input: input != null ? input.clamp(0.0, 1.0) : null,
      output: output != null ? output.clamp(0.0, 1.0) : null,
    );
  }

  // Demo-only: fake a speaking pulse.
  void demoSpeak() {
    if (!state.connected) return;
    setState(AgentState.thinking);
    Future.delayed(const Duration(milliseconds: 600), () {
      setState(AgentState.talking);
      setVolumes(
        input: 0.2,
        output: 0.75,
      );
      Future.delayed(const Duration(seconds: 2), () {
        setState(AgentState.listening);
        setVolumes(input: 0.0, output: 0.35);
      });
    });
  }
}

class AgentScreen extends ConsumerWidget {
  const AgentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(agentUiStateProvider);
    final n = ref.read(agentUiStateProvider.notifier);

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
                          state: s.state,
                          input: s.input,
                          output: s.output,
                          color1: const Color(0xFFCADCFC),
                          color2: const Color(0xFFA0B9D1),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: _StatusCard(
                          connected: s.connected,
                          state: s.state,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: s.connected ? null : n.connect,
                    icon: const Icon(Icons.mic),
                    label: const Text("Connect"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: s.connected ? n.disconnect : null,
                    icon: const Icon(Icons.stop),
                    label: const Text("Disconnect"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: s.connected ? n.demoSpeak : null,
                    icon: const Icon(Icons.record_voice_over),
                    label: const Text("Demo: Speak"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "This tab will connect to your AWS backend, which mints an ephemeral ElevenLabs session token and exposes read-only tools.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final bool connected;
  final AgentState state;

  const _StatusCard({required this.connected, required this.state});

  @override
  Widget build(BuildContext context) {
    final label = connected ? _labelFor(state) : "Disconnected";
    final dotColor = connected
        ? switch (state) {
            AgentState.idle => Colors.grey,
            AgentState.thinking => Colors.amber,
            AgentState.listening => Colors.lightBlue,
            AgentState.talking => Colors.green,
          }
        : Colors.redAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
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
      ),
    );
  }

  String _labelFor(AgentState s) {
    switch (s) {
      case AgentState.idle:
        return "Idle";
      case AgentState.thinking:
        return "Thinking";
      case AgentState.listening:
        return "Listening";
      case AgentState.talking:
        return "Talking";
    }
  }
}

