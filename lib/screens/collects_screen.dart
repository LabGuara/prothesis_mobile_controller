import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/collect.dart';
import '../services/collect_store.dart';
import '../services/mqtt_service.dart';
import '../theme/gait_mode_styles.dart';

const _dialogTitleStyle = TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600);
const _dialogContentStyle = TextStyle(color: Color(0xFFCBD5E1), fontSize: 14, height: 1.4);

class CollectsScreen extends StatelessWidget {
  const CollectsScreen({super.key, required this.mqttService, required this.collectStore});

  final MqttService mqttService;
  final CollectStore collectStore;

  static final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');
  static final DateFormat _timeFormat = DateFormat('HH:mm:ss');

  Future<void> _createCollect(BuildContext context) async {
    final volunteer = await showDialog<String>(context: context, builder: (_) => const _NewCollectDialog());
    if (volunteer == null) {
      return;
    }

    final collect = Collect.create(volunteer);
    try {
      await mqttService.publishCollectStart(collect);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to start the collect: $e'), backgroundColor: Colors.red));
      }
      return;
    }
    collectStore.start(collect);
  }

  Future<void> _finishCollect(BuildContext context) async {
    final collect = collectStore.activeCollect;
    if (collect == null) {
      return;
    }
    final runInProgress = collect.runs.lastOrNull?.isInProgress ?? false;
    final confirmed = await _confirm(
      context,
      title: 'Finish collect?',
      message:
          'New runs will no longer be added to the collect of ${collect.volunteer}.'
          '${runInProgress ? ' The run in progress stays in it and gets its end time when the prosthesis stops.' : ''}',
      confirmLabel: 'Finish',
    );
    if (confirmed) {
      collectStore.finish();
    }
  }

  Future<void> _deleteCollect(BuildContext context, Collect collect) async {
    final confirmed = await _confirm(
      context,
      title: 'Delete collect?',
      message:
          'The collect of ${collect.volunteer} and its run IDs will be removed from this phone. '
          'The runs stay in the database.',
      confirmLabel: 'Delete',
    );
    if (confirmed) {
      collectStore.delete(collect);
    }
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        titleTextStyle: _dialogTitleStyle,
        contentTextStyle: _dialogContentStyle,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF94A3B8)),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  void _copyId(BuildContext context, String id, String copiedMessage) {
    Clipboard.setData(ClipboardData(text: id));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(copiedMessage),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF334155),
        ),
      );
  }

  String _formatTime(DateTime time) => _timeFormat.format(time.toLocal());

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: collectStore,
      builder: (context, _) {
        final collects = collectStore.collects;
        final isCollecting = collectStore.activeCollect != null;

        return Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          appBar: AppBar(
            title: const Text('Collects', style: TextStyle(fontWeight: FontWeight.w600)),
            backgroundColor: const Color(0xFF0F172A),
            foregroundColor: Colors.white,
            elevation: 0,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(height: 1, color: const Color(0xFF1E293B)),
            ),
          ),
          body: collects.isEmpty
              ? _buildEmpty()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  itemCount: collects.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _buildCollectCard(context, collects[index]),
                ),
          floatingActionButton: isCollecting
              ? FloatingActionButton.extended(
                  key: const ValueKey('finish'),
                  onPressed: () => _finishCollect(context),
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('Finish collect', style: TextStyle(fontWeight: FontWeight.w600)),
                )
              : FloatingActionButton(
                  key: const ValueKey('new'),
                  onPressed: () => _createCollect(context),
                  tooltip: 'New collect',
                  backgroundColor: const Color(0xFF14B8A6),
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.add_rounded),
                ),
        );
      },
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          'No collects yet. Create one to group the runs of a volunteer.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF64748B), fontSize: 14, height: 1.5),
        ),
      ),
    );
  }

  Widget _buildCollectCard(BuildContext context, Collect collect) {
    final isActive = collect.isActive;
    final runs = collect.runs.length;

    return Material(
      color: const Color(0xFF1E293B),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isActive ? const Color(0xFF14B8A6) : const Color(0xFF334155), width: 1.5),
      ),
      child: ExpansionTile(
        key: PageStorageKey<DateTime>(collect.startedAt),
        initiallyExpanded: isActive,
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: const Color(0xFF94A3B8),
        collapsedIconColor: const Color(0xFF64748B),
        tilePadding: const EdgeInsets.only(left: 16, right: 12),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        leading: Icon(
          isActive ? Icons.radio_button_checked_rounded : Icons.check_circle_outline_rounded,
          color: isActive ? const Color(0xFF14B8A6) : const Color(0xFF64748B),
        ),
        title: Text(
          collect.volunteer,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${isActive ? 'Active' : 'Finished'} · ${_dateTimeFormat.format(collect.startedAt.toLocal())} · '
          '${runs == 1 ? '1 run' : '$runs runs'}',
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
        ),
        children: [
          const Divider(height: 1, color: Color(0xFF334155)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: _buildCopyableId(context, collect.id, label: 'ID', copiedMessage: 'Collect ID copied'),
          ),
          const Divider(height: 1, color: Color(0xFF334155)),
          if (collect.runs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                isActive ? 'No runs yet' : 'No runs were recorded',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
            ),
          for (final (index, run) in collect.runs.indexed) ...[
            if (index > 0) const Divider(height: 1, color: Color(0xFF334155)),
            _buildRun(context, index + 1, run),
          ],
          if (!isActive) ...[
            const Divider(height: 1, color: Color(0xFF334155)),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _deleteCollect(context, collect),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Delete'),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRun(BuildContext context, int number, CollectRun run) {
    final mode = run.gaitMode;
    final style = gaitModeStyles[mode];
    final color = style?.color ?? const Color(0xFF94A3B8);
    final endedAt = run.endedAt;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(style?.icon ?? Icons.help_outline_rounded, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$number  ${mode?.label ?? 'Gait ${run.gait}'}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (run.current != null)
                      Text(
                        '${run.current} mA',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    text: '${_formatTime(run.startedAt)} - ',
                    children: [
                      endedAt == null
                          ? const TextSpan(
                              text: 'in progress',
                              style: TextStyle(color: Color(0xFF14B8A6), fontWeight: FontWeight.w600),
                            )
                          : TextSpan(text: _formatTime(endedAt)),
                    ],
                  ),
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 13,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                _buildCopyableId(context, run.runId, copiedMessage: 'Run ID copied'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCopyableId(BuildContext context, String id, {required String copiedMessage, String? label}) {
    return Transform.translate(
      offset: const Offset(-6, 0),
      child: InkWell(
        onTap: () => _copyId(context, id, copiedMessage),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 2, 0, 2),
          child: Row(
            children: [
              if (label != null) ...[
                Text(
                  label,
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  id,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF64748B)),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.copy_rounded, size: 13, color: Color(0xFF64748B)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewCollectDialog extends StatefulWidget {
  const _NewCollectDialog();

  @override
  State<_NewCollectDialog> createState() => _NewCollectDialogState();
}

class _NewCollectDialogState extends State<_NewCollectDialog> {
  final _controller = TextEditingController();

  String get _volunteer => _controller.text.trim();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_volunteer.isNotEmpty) {
      Navigator.pop(context, _volunteer);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      titleTextStyle: _dialogTitleStyle,
      title: const Text('New collect'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
        cursorColor: const Color(0xFF14B8A6),
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          labelText: 'Volunteer name',
          labelStyle: TextStyle(color: Color(0xFF94A3B8)),
          floatingLabelStyle: TextStyle(color: Color(0xFF14B8A6)),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF475569))),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF14B8A6), width: 2)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF94A3B8)),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _volunteer.isEmpty ? null : _submit,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF14B8A6),
            disabledForegroundColor: const Color(0xFF475569),
          ),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
