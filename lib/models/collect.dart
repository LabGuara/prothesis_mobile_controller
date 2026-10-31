import 'package:uuid/uuid.dart';

import 'action_command.dart';

/// One run of the prosthesis, as named by the bridge. The times are the timestamps of the feedbacks
/// that started and ended it, the same ones the orchestrator stores for the run.
class CollectRun {
  final String runId;
  final DateTime startedAt;
  DateTime? endedAt;

  final int? gait;
  final int? current;

  CollectRun({required this.runId, required this.startedAt, this.endedAt, required this.gait, required this.current});

  bool get isInProgress => endedAt == null;

  GaitMode? get gaitMode => GaitMode.fromValue(gait);

  factory CollectRun.fromMap(Map<String, dynamic> map) {
    final endedAt = map['ended_at'] as String?;
    return CollectRun(
      runId: map['run_id'] as String,
      startedAt: DateTime.parse(map['started_at'] as String),
      endedAt: endedAt == null ? null : DateTime.parse(endedAt),
      gait: map['gait'] as int?,
      current: map['current'] as int?,
    );
  }

  Map<String, dynamic> toMap() => {
    'run_id': runId,
    'started_at': startedAt.toIso8601String(),
    'ended_at': endedAt?.toIso8601String(),
    'gait': gait,
    'current': current,
  };
}

/// A session with one volunteer. The app announces it, with the volunteer, when it starts; every
/// command then carries its [id], so the runs it starts are filed under it.
class Collect {
  final String id;
  final String volunteer;
  final DateTime startedAt;
  DateTime? finishedAt;

  final List<CollectRun> runs;

  Collect({required this.id, required this.volunteer, required this.startedAt, this.finishedAt, List<CollectRun>? runs})
    : runs = runs ?? [];

  Collect.create(this.volunteer) : id = const Uuid().v4(), startedAt = DateTime.now().toUtc(), runs = [];

  bool get isActive => finishedAt == null;

  factory Collect.fromMap(Map<String, dynamic> map) {
    final finishedAt = map['finished_at'] as String?;
    return Collect(
      // Collects saved before they had an id get one now; their runs were stored without it.
      id: map['id'] as String? ?? const Uuid().v4(),
      volunteer: map['volunteer'] as String,
      startedAt: DateTime.parse(map['started_at'] as String),
      finishedAt: finishedAt == null ? null : DateTime.parse(finishedAt),
      runs: [for (final run in map['runs'] as List<dynamic>) CollectRun.fromMap(run as Map<String, dynamic>)],
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'volunteer': volunteer,
    'started_at': startedAt.toIso8601String(),
    'finished_at': finishedAt?.toIso8601String(),
    'runs': [for (final run in runs) run.toMap()],
  };
}
