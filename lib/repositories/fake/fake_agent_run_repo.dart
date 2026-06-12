import '../../config/app_config.dart';
import '../../models/agent_run.dart';
import '../agent_run_repo.dart';

/// Fake agent-trace stream for offline demo mode. There is no real Firestore in
/// fake mode, so this emits a canned sequence of steps — one every
/// [AppConfig.simulatedLatency] — then finishes with `status: 'done'`, so the
/// chat sheet shows the trace lines appearing live before the canned answer
/// resolves (the fake `askRepo` delay is tuned to outlast this stream).
class FakeAgentRunRepository implements AgentRunRepository {
  /// The canned progress the demo agent "performs".
  static const _cannedSteps = <String>[
    'Reading .trellis planning docs…',
    'Searching commit history…',
    'Searching Discord…',
    'Composing answer…',
  ];

  @override
  Stream<AgentRun?> watch(String repoId, String runId) async* {
    // Doc doesn't exist yet.
    yield null;

    final steps = <AgentStep>[];
    for (final label in _cannedSteps) {
      await Future.delayed(AppConfig.simulatedLatency);
      steps.add(AgentStep(label: label, at: DateTime.now().toIso8601String()));
      yield AgentRun(
        flow: 'askRepo',
        status: 'running',
        steps: List.unmodifiable(steps),
      );
    }
    yield AgentRun(
      flow: 'askRepo',
      status: 'done',
      steps: List.unmodifiable(steps),
    );
  }
}
