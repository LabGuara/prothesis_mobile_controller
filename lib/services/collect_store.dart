import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/collect.dart';
import '../models/power_feedback.dart';

/// Keeps the collects on the phone and files every run under the collect its feedback
/// names. At most one collect is active at a time.
class CollectStore extends ChangeNotifier {
  CollectStore._(this._prefs, this._collects);

  // Kept from before the rename to collects, so the ones already saved on the phone are still found.
  static const String _storageKey = 'data_collections';

  final SharedPreferencesAsync _prefs;

  /// Newest first.
  final List<Collect> _collects;

  static Future<CollectStore> load() async {
    final prefs = SharedPreferencesAsync();
    final collects = <Collect>[];
    var givenIds = false;
    try {
      final stored = await prefs.getString(_storageKey);
      if (stored != null) {
        for (final item in json.decode(stored) as List<dynamic>) {
          final map = item as Map<String, dynamic>;
          givenIds |= map['id'] == null;
          collects.add(Collect.fromMap(map));
        }
      }
    } catch (e) {
      debugPrint('Failed to load collects: $e');
    }
    final store = CollectStore._(prefs, collects);
    // Collects saved before they had an id were just given one: saved now, so it stays the same.
    if (givenIds) {
      await store._save();
    }
    return store;
  }

  List<Collect> get collects => List.unmodifiable(_collects);

  Collect? get activeCollect => _collects.where((collect) => collect.isActive).firstOrNull;

  CollectRun? get _runInProgress =>
      _collects.expand((collect) => collect.runs).where((run) => run.isInProgress).firstOrNull;

  bool _isKnownRun(String runId) => _collects.any((collect) => collect.runs.any((run) => run.runId == runId));

  void start(Collect collect) {
    if (activeCollect != null) {
      return;
    }
    _collects.insert(0, collect);
    _changed();
  }

  /// A run still in progress stays in the collect and gets its end time when the prosthesis
  /// reports it ended.
  void finish() {
    final collect = activeCollect;
    if (collect == null) {
      return;
    }
    collect.finishedAt = DateTime.now().toUtc();
    _changed();
  }

  void delete(Collect collect) {
    if (collect.isActive) {
      return;
    }
    if (_collects.remove(collect)) {
      _changed();
    }
  }

  /// Opens and closes runs the way the orchestrator does, so their times match the database: a
  /// feedback that leaves the prosthesis on with an unknown run id ends the run in progress and
  /// starts that one, a known run id means the run kept going, and a feedback that leaves the
  /// prosthesis off ends the run in progress. A new run is kept in the collect its feedback
  /// names, the one the command that started it was sent in, if that collect is on this phone.
  void recordFeedback(PowerFeedback feedback) {
    final inProgress = _runInProgress;

    if (!feedback.state.isOn) {
      if (inProgress == null) {
        return;
      }
      inProgress.endedAt = feedback.timestamp;
      _changed();
      return;
    }

    final runId = feedback.runId;
    if (runId == null || _isKnownRun(runId)) {
      return;
    }

    inProgress?.endedAt = feedback.timestamp;
    final collect = _collects.where((collect) => collect.id == feedback.collectId).firstOrNull;
    collect?.runs.add(
      CollectRun(runId: runId, startedAt: feedback.timestamp, gait: feedback.gait, current: feedback.current),
    );
    if (inProgress != null || collect != null) {
      _changed();
    }
  }

  void _changed() {
    notifyListeners();
    unawaited(_save());
  }

  Future<void> _save() async {
    try {
      await _prefs.setString(_storageKey, json.encode([for (final collect in _collects) collect.toMap()]));
    } catch (e) {
      debugPrint('Failed to save collects: $e');
    }
  }
}
