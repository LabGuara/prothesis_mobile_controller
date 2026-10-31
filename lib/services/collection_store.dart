import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/data_collection.dart';
import '../models/power_feedback.dart';

/// Keeps the data collections on the phone and files every run under the collection its feedback
/// names. At most one collection is active at a time.
class CollectionStore extends ChangeNotifier {
  CollectionStore._(this._prefs, this._collections);

  static const String _storageKey = 'data_collections';

  final SharedPreferencesAsync _prefs;

  /// Newest first.
  final List<DataCollection> _collections;

  static Future<CollectionStore> load() async {
    final prefs = SharedPreferencesAsync();
    final collections = <DataCollection>[];
    var givenIds = false;
    try {
      final stored = await prefs.getString(_storageKey);
      if (stored != null) {
        for (final item in json.decode(stored) as List<dynamic>) {
          final map = item as Map<String, dynamic>;
          givenIds |= map['id'] == null;
          collections.add(DataCollection.fromMap(map));
        }
      }
    } catch (e) {
      debugPrint('Failed to load data collections: $e');
    }
    final store = CollectionStore._(prefs, collections);
    // Collections saved before they had an id were just given one: saved now, so it stays the same.
    if (givenIds) {
      await store._save();
    }
    return store;
  }

  List<DataCollection> get collections => List.unmodifiable(_collections);

  DataCollection? get activeCollection => _collections.where((collection) => collection.isActive).firstOrNull;

  CollectionRun? get _runInProgress =>
      _collections.expand((collection) => collection.runs).where((run) => run.isInProgress).firstOrNull;

  bool _isKnownRun(String runId) => _collections.any((collection) => collection.runs.any((run) => run.runId == runId));

  void start(DataCollection collection) {
    if (activeCollection != null) {
      return;
    }
    _collections.insert(0, collection);
    _changed();
  }

  /// A run still in progress stays in the collection and gets its end time when the prosthesis
  /// reports it ended.
  void finish() {
    final collection = activeCollection;
    if (collection == null) {
      return;
    }
    collection.finishedAt = DateTime.now().toUtc();
    _changed();
  }

  void delete(DataCollection collection) {
    if (collection.isActive) {
      return;
    }
    if (_collections.remove(collection)) {
      _changed();
    }
  }

  /// Opens and closes runs the way the orchestrator does, so their times match the database: a
  /// feedback that leaves the prosthesis on with an unknown run id ends the run in progress and
  /// starts that one, a known run id means the run kept going, and a feedback that leaves the
  /// prosthesis off ends the run in progress. A new run is kept in the collection its feedback
  /// names, the one the command that started it was sent in, if that collection is on this phone.
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
    final collection = _collections.where((collection) => collection.id == feedback.collectionId).firstOrNull;
    collection?.runs.add(
      CollectionRun(runId: runId, startedAt: feedback.timestamp, gait: feedback.gait, current: feedback.current),
    );
    if (inProgress != null || collection != null) {
      _changed();
    }
  }

  void _changed() {
    notifyListeners();
    unawaited(_save());
  }

  Future<void> _save() async {
    try {
      await _prefs.setString(_storageKey, json.encode([for (final collection in _collections) collection.toMap()]));
    } catch (e) {
      debugPrint('Failed to save data collections: $e');
    }
  }
}
