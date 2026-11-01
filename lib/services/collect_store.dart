import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/collect.dart';
import '../models/power_feedback.dart';

class CollectStore extends ChangeNotifier {
  CollectStore._(this._prefs, this._collects);

  static const String _storageKey = 'data_collections';

  final SharedPreferencesAsync _prefs;

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
