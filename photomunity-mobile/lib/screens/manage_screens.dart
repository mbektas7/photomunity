import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/community_widgets.dart';
import '../widgets/design.dart';

// Yönetim ekranları: yarışma oluşturma/yönetimi ve topluluk ayarları.
// Web'deki /c/[slug]/contests/new, /contests/[id]/manage ve /c/[slug]/settings ile aynı API çağrıları.

/// Bölüm kartı: başlık, isteğe bağlı açıklama, içerik.
class _Section extends StatelessWidget {
  const _Section({required this.title, this.lead, required this.child});
  final String title;
  final String? lead;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: Space.s3),
      child: SurfaceCard(
        padding: const EdgeInsets.all(Space.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: AppText.heading(p.ink)),
            if (lead != null) ...[
              const SizedBox(height: 4),
              Text(lead!, style: font(14, height: 1.45, color: p.inkMuted)),
            ],
            const SizedBox(height: Space.s4),
            child,
          ],
        ),
      ),
    );
  }
}

Future<bool> _confirm(BuildContext context, String message, String ok) async {
  final t = L10n.of(context);
  return await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('common.cancel'))),
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
          ],
        ),
      ) ??
      false;
}

Future<String?> _prompt(BuildContext context, String label) async {
  final t = L10n.of(context);
  final ctrl = TextEditingController();
  final r = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: 3,
        minLines: 1,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(t('common.cancel'))),
        TextButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: Text(t('common.save'))),
      ],
    ),
  );
  ctrl.dispose();
  return r == null || r.isEmpty ? null : r;
}

// ================================================================ Yarışma formu

/// Yarışma oluşturma ve düzenleme formu. `locked` iken (yayından sonra) yalnızca metinler,
/// katılım sürüyorsa ödüller düzenlenebilir.
class ContestForm extends StatefulWidget {
  const ContestForm({
    super.key,
    this.initial,
    this.locked = false,
    this.prizesEditable = true,
    required this.busy,
    required this.submitLabel,
    required this.onSubmit,
  });
  final Contest? initial;
  final bool locked;
  final bool prizesEditable;
  final bool busy;
  final String submitLabel;
  final ValueChanged<Map<String, dynamic>> onSubmit;

  @override
  State<ContestForm> createState() => _ContestFormState();
}

class _ContestFormState extends State<ContestForm> {
  late final _title = TextEditingController(text: widget.initial?.title);
  late final _desc = TextEditingController(text: widget.initial?.description);
  late final _rules = TextEditingController(text: widget.initial?.rules);
  late final _minVotes = TextEditingController(text: '${widget.initial?.minVotes ?? 5}');
  late DateTime _deadline = widget.initial?.submissionDeadline.toLocal() ?? _at(21);
  late DateTime _votingEnd = widget.initial?.votingEnd.toLocal() ?? _at(28);
  late DateTime _results = widget.initial?.resultsAt.toLocal() ?? _at(30);
  late String _mode = widget.initial?.judgingMode ?? 'public';
  late bool _anonymous = widget.initial?.anonymous ?? true;
  late final List<TextEditingController> _prizes = [
    for (final pr in (widget.initial?.prizes.isNotEmpty ?? false)
        ? widget.initial!.prizes.map((p) => p.title)
        : ['', '', ''])
      TextEditingController(text: pr),
  ];

  static DateTime _at(int days) {
    final d = DateTime.now().add(Duration(days: days));
    return DateTime(d.year, d.month, d.day, 23, 59);
  }

  bool get _ordered => _deadline.isBefore(_votingEnd) && !_votingEnd.isAfter(_results);

  @override
  void dispose() {
    for (final c in [_title, _desc, _rules, _minVotes, ..._prizes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(DateTime current, ValueChanged<DateTime> set) async {
    final d = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (d == null || !mounted) return;
    final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current));
    if (tm == null) return;
    setState(() => set(DateTime(d.year, d.month, d.day, tm.hour, tm.minute)));
  }

  void _submit() {
    final t = L10n.of(context);
    if (_title.text.trim().length < 3 || _desc.text.trim().isEmpty) {
      toast(context, t('cform.required'));
      return;
    }
    final prizes = [
      for (final c in _prizes)
        if (c.text.trim().isNotEmpty) c.text.trim(),
    ];
    widget.onSubmit({
      'title': _title.text.trim(),
      'description': _desc.text.trim(),
      'rules': _rules.text.trim().isEmpty ? null : _rules.text.trim(),
      if (!widget.locked) ...{
        'submission_deadline': _deadline.toUtc().toIso8601String(),
        'voting_end': _votingEnd.toUtc().toIso8601String(),
        'results_at': _results.toUtc().toIso8601String(),
        'judging_mode': _mode,
        'anonymous': _anonymous,
        'min_votes': int.tryParse(_minVotes.text) ?? 5,
      },
      if (widget.prizesEditable)
        'prizes': [for (final (i, title) in prizes.indexed) {'rank': i + 1, 'title': title}],
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final fmt = DateFormat.yMMMd(t.locale.languageCode).add_Hm();

    Widget dateRow(String label, DateTime value, ValueChanged<DateTime> set) => InkWell(
      borderRadius: BorderRadius.circular(Radii.box),
      onTap: widget.locked ? null : () => _pickDate(value, set),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(Radii.box)),
        child: Row(
          children: [
            Icon(LucideIcons.calendar, size: 20, color: widget.locked ? p.inkSubtle : p.ink),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: font(15, color: p.inkMuted))),
            Text(fmt.format(value), style: font(15, weight: 600, color: widget.locked ? p.inkMuted : p.ink, tabular: true)),
          ],
        ),
      ),
    );

    Widget modeCard(String mode) {
      final on = _mode == mode;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.box),
          onTap: widget.locked ? null : () => setState(() => _mode = mode),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: on ? p.accentTint : p.surface2,
              borderRadius: BorderRadius.circular(Radii.box),
              border: Border.all(color: on ? p.accent : Colors.transparent, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('cform.mode_$mode'), style: font(15.5, weight: 700, color: on ? p.accentText : p.ink)),
                const SizedBox(height: 4),
                Text(t('cform.mode_${mode}_hint'), style: font(13, height: 1.4, color: p.inkMuted)),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(
          title: t('cform.about'),
          child: Column(
            children: [
              TextField(controller: _title, maxLength: 150, decoration: InputDecoration(labelText: t('cform.title'), hintText: t('cform.title_placeholder'))),
              const SizedBox(height: 8),
              TextField(controller: _desc, maxLength: 5000, minLines: 3, maxLines: 8, decoration: InputDecoration(labelText: t('cform.description'), helperText: t('cform.description_hint'))),
              const SizedBox(height: 8),
              TextField(controller: _rules, maxLength: 5000, minLines: 2, maxLines: 6, decoration: InputDecoration(labelText: t('cform.rules'), helperText: t('cform.rules_hint'))),
            ],
          ),
        ),
        _Section(
          title: t('cform.dates'),
          lead: widget.locked ? t('cform.locked_hint') : t('cform.dates_hint'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              dateRow(t('cform.submission_deadline'), _deadline, (d) => _deadline = d),
              const SizedBox(height: Space.s2),
              dateRow(t('cform.voting_end'), _votingEnd, (d) => _votingEnd = d),
              const SizedBox(height: Space.s2),
              dateRow(t('cform.results_at'), _results, (d) => _results = d),
              if (!_ordered) ...[
                const SizedBox(height: Space.s3),
                Notice(t('cform.dates_order'), tone: NoticeTone.error),
              ],
            ],
          ),
        ),
        _Section(
          title: t('cform.judging'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [modeCard('public'), const SizedBox(width: Space.s2), modeCard('jury')]),
              if (_mode == 'jury' && widget.initial == null) ...[
                const SizedBox(height: 10),
                Text(t('cform.jury_after'), style: font(13.5, height: 1.4, color: p.inkMuted)),
              ],
              const SizedBox(height: Space.s2),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _anonymous,
                onChanged: widget.locked ? null : (v) => setState(() => _anonymous = v),
                title: Text(t('cform.anonymous'), style: font(15.5, weight: 600, color: p.ink)),
                subtitle: Text(t('cform.anonymous_hint'), style: font(13, color: p.inkMuted)),
              ),
              if (_mode == 'public')
                TextField(
                  controller: _minVotes,
                  enabled: !widget.locked,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: t('cform.min_votes'), helperText: t('cform.min_votes_hint')),
                ),
            ],
          ),
        ),
        _Section(
          title: t('cform.prizes'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, c) in _prizes.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s2),
                  child: Row(
                    children: [
                      SizedBox(width: 30, child: Text('${i + 1}.', style: font(17, weight: 700, color: p.ink, tabular: true))),
                      Expanded(
                        child: TextField(
                          controller: c,
                          enabled: widget.prizesEditable,
                          maxLength: 200,
                          decoration: InputDecoration(hintText: t('cform.prize_placeholder'), counterText: ''),
                        ),
                      ),
                      if (_prizes.length > 1 && widget.prizesEditable)
                        IconButton(
                          tooltip: t('cform.remove_prize'),
                          icon: const Icon(LucideIcons.x, size: 20),
                          onPressed: () => setState(() => _prizes.removeAt(i).dispose()),
                        ),
                    ],
                  ),
                ),
              if (_prizes.length < 10 && widget.prizesEditable)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _prizes.add(TextEditingController())),
                    icon: const Icon(LucideIcons.plus, size: 18),
                    label: Text(t('cform.add_prize')),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.s5),
        LargeButton(label: widget.submitLabel, busy: widget.busy, onPressed: _ordered ? _submit : null),
      ],
    );
  }
}

/// Yeni yarışma: önce taslak olarak kaydedilir, sonra yönetim ekranına geçilir.
class NewContestScreen extends ConsumerStatefulWidget {
  const NewContestScreen({super.key, required this.slug});
  final String slug;

  @override
  ConsumerState<NewContestScreen> createState() => _NewContestScreenState();
}

class _NewContestScreenState extends ConsumerState<NewContestScreen> {
  bool _busy = false;

  Future<void> _create(Map<String, dynamic> body) async {
    setState(() => _busy = true);
    try {
      final c = await ref.read(apiProvider).post<Map<String, dynamic>>('/communities/${widget.slug}/contests', body);
      ref.invalidate(communityContestsProvider);
      if (mounted) context.pushReplacement('/contests/${c['id']}/manage?created=1');
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final community = ref.watch(communityProvider(widget.slug)).asData?.value;
    return Scaffold(
      appBar: AppBar(title: Text(community?.name ?? '', style: font(16, weight: 600, color: p.inkMuted))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 40),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('cform.new_title'), style: AppText.display(p.ink)),
                const SizedBox(height: 8),
                Text(t('cform.new_lead'), style: font(15, height: 1.45, color: p.inkMuted)),
              ],
            ),
          ),
          ContestForm(busy: _busy, submitLabel: t('cform.save_draft'), onSubmit: _create),
        ],
      ),
    );
  }
}

// ================================================================ Yarışma yönetimi

final _summaryProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, id) => ref.read(apiProvider).get<Map<String, dynamic>>('/contests/$id/summary'),
);
final _judgesProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, id) async => ((await ref.read(apiProvider).get<List<dynamic>>('/contests/$id/judges'))).cast<Map<String, dynamic>>(),
);
final _adminEntriesProvider = FutureProvider.autoDispose.family<List<Entry>, String>(
  (ref, id) async => (await ref.read(apiProvider).get<List<dynamic>>('/contests/$id/entries', query: {'view': 'admin'}))
      .map((e) => Entry.fromJson(e as Map<String, dynamic>))
      .toList(),
);
final _resultsProvider = FutureProvider.autoDispose.family<List<ResultRow>, String>(
  (ref, id) async => (await ref.read(apiProvider).get<List<dynamic>>('/contests/$id/results'))
      .map((r) => ResultRow.fromJson(r as Map<String, dynamic>))
      .toList(),
);

class ContestManageScreen extends ConsumerStatefulWidget {
  const ContestManageScreen({super.key, required this.id, this.created = false});
  final String id;
  final bool created;

  @override
  ConsumerState<ContestManageScreen> createState() => _ContestManageScreenState();
}

class _ContestManageScreenState extends ConsumerState<ContestManageScreen> {
  bool _saving = false;
  bool _publishing = false;

  void _refresh() {
    ref.invalidate(contestProvider(widget.id));
    ref.invalidate(_summaryProvider(widget.id));
    ref.invalidate(_judgesProvider(widget.id));
    ref.invalidate(_adminEntriesProvider(widget.id));
    ref.invalidate(_resultsProvider(widget.id));
  }

  Future<void> _save(Contest c, Map<String, dynamic> body) async {
    final t = L10n.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(apiProvider).patch<dynamic>('/contests/${c.id}', body);
      ref.invalidate(contestProvider(widget.id));
      if (mounted) toast(context, t('manage.saved'));
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _publish(Contest c) async {
    final t = L10n.of(context);
    if (!await _confirm(context, t('manage.publish_confirm'), t('manage.publish'))) return;
    setState(() => _publishing = true);
    try {
      await ref.read(apiProvider).post<dynamic>('/contests/${c.id}/publish');
      _refresh();
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final async = ref.watch(contestProvider(widget.id));
    final c = async.asData?.value;
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (c != null)
            TextButton(onPressed: () => context.push('/contests/${c.id}'), child: Text(t('manage.view_public'))),
          const SizedBox(width: 8),
        ],
      ),
      body: c == null
          ? (async.hasError
                ? ErrorView(error: async.error!, onRetry: _refresh)
                : const Center(child: CircularProgressIndicator()))
          : c.myRole != 'admin'
          ? Padding(padding: const EdgeInsets.all(20), child: Notice(t('manage.forbidden'), tone: NoticeTone.error))
          : RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 40),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            StatusBadge(status: c.status, mode: c.judgingMode),
                            Text(c.community.name, style: font(14, color: p.inkMuted)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(c.title, style: AppText.display(p.ink)),
                      ],
                    ),
                  ),
                  if (widget.created) ...[
                    const SizedBox(height: Space.s3),
                    Notice(t('manage.created'), tone: NoticeTone.success),
                  ],
                  const SizedBox(height: Space.s3),
                  SurfaceCard(padding: const EdgeInsets.all(Space.s5), child: ContestTimeline(c: c)),
                  if (c.status == 'draft')
                    _Section(
                      title: t('manage.publish_title'),
                      lead: c.judgingMode == 'jury' ? t('manage.publish_body_jury') : t('manage.publish_body'),
                      child: FilledButton(
                        onPressed: _publishing ? null : () => _publish(c),
                        child: BusyLabel(busy: _publishing, label: t('manage.publish')),
                      ),
                    ),
                  if (c.status != 'draft') _Summary(c: c),
                  if (c.judgingMode == 'jury') _Judges(c: c),
                  if (c.status != 'draft') _Entries(c: c, onChanged: _refresh),
                  if (c.status == 'judging' || c.status == 'closed') _Preview(c: c),
                  _Section(
                    title: t('manage.details'),
                    lead: c.status == 'draft' ? null : t('manage.details_locked'),
                    child: const SizedBox.shrink(),
                  ),
                  ContestForm(
                    key: ValueKey('${c.id}-${c.status}'),
                    initial: c,
                    locked: c.status != 'draft',
                    prizesEditable: c.status == 'draft' || c.status == 'open',
                    busy: _saving,
                    submitLabel: t('cform.save'),
                    onSubmit: (b) => _save(c, b),
                  ),
                ],
              ),
            ),
    );
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.c});
  final Contest c;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    final s = ref.watch(_summaryProvider(c.id)).asData?.value;
    if (s == null) return const SizedBox.shrink();
    final stats = [
      ((s['entries'] as int) - (s['disqualified'] as int), t('manage.stat_entries')),
      if (c.judgingMode == 'public') ...[
        (s['voters'] as int, t('manage.stat_voters')),
        (s['votes'] as int, t('manage.stat_votes')),
      ],
    ];
    final suspicious = s['suspicious_ips'] as int? ?? 0;
    return _Section(
      title: t('manage.summary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final (i, (n, label)) in stats.indexed) ...[
                if (i > 0) const SizedBox(width: Space.s2),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(Radii.box)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$n', style: AppText.numeral(p.ink).copyWith(fontSize: 26)),
                        const SizedBox(height: 4),
                        Text(label, style: AppText.caption(p.inkMuted)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (suspicious > 0) ...[
            const SizedBox(height: Space.s3),
            Notice(t('manage.suspicious', {'count': suspicious}), tone: NoticeTone.error),
          ],
        ],
      ),
    );
  }
}

class _Judges extends ConsumerStatefulWidget {
  const _Judges({required this.c});
  final Contest c;

  @override
  ConsumerState<_Judges> createState() => _JudgesState();
}

class _JudgesState extends ConsumerState<_Judges> {
  final _who = TextEditingController();
  final _weight = TextEditingController(text: '1');
  bool _busy = false;

  @override
  void dispose() {
    _who.dispose();
    _weight.dispose();
    super.dispose();
  }

  Future<void> _call(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
      ref.invalidate(_judgesProvider(widget.c.id));
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() => _call(() async {
    final v = _who.text.trim();
    if (v.isEmpty) return;
    final w = double.tryParse(_weight.text.replaceAll(',', '.')) ?? 1;
    final body = v.contains('@') && !v.startsWith('@')
        ? {'email': v, 'weight': w}
        : {'username': v.replaceFirst('@', ''), 'weight': w};
    await ref.read(apiProvider).post<dynamic>('/contests/${widget.c.id}/judges', body);
    _who.clear();
    _weight.text = '1';
  });

  Future<void> _editWeight(Map<String, dynamic> j) async {
    final t = L10n.of(context);
    final v = await _prompt(context, t('manage.weight'));
    final w = double.tryParse((v ?? '').replaceAll(',', '.'));
    if (w == null) return;
    await _call(() => ref.read(apiProvider).patch<dynamic>('/contests/${widget.c.id}/judges/${j['id']}', {'weight': w}));
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final judges = ref.watch(_judgesProvider(widget.c.id)).asData?.value ?? const [];
    final locked = widget.c.status == 'closed' || widget.c.status == 'finished';
    final total = judges.fold<double>(0, (s, j) => s + ((j['pending'] as bool? ?? false) ? 0 : (j['weight'] as num).toDouble()));
    return _Section(
      title: t('manage.judges'),
      lead: t('manage.judges_lead'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final j in judges)
            Builder(
              builder: (_) {
                final user = j['user'] == null ? null : UserCard.fromJson(j['user'] as Map<String, dynamic>);
                final pending = j['pending'] as bool? ?? false;
                final weight = (j['weight'] as num).toDouble();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      user != null
                          ? Avatar(name: user.displayName, url: user.avatarUrl, size: 38)
                          : Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(color: p.surface2, shape: BoxShape.circle),
                              child: Icon(LucideIcons.mail, size: 18, color: p.inkMuted),
                            ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user?.displayName ?? (j['email'] as String? ?? ''), maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: font(15, weight: 600, color: p.ink)),
                            Text(pending ? t('manage.invite_pending') : t('manage.scored', {'count': j['scored'] ?? 0}),
                                style: AppText.caption(p.inkMuted)),
                          ],
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(Radii.pill),
                        onTap: locked ? null : () => _editWeight(j),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: ExifChip(
                            '${t('manage.weight')} ${NumberFormat('0.#').format(weight)}'
                            '${!pending && total > 0 ? ' · %${(weight / total * 100).round()}' : ''}',
                          ),
                        ),
                      ),
                      if (!locked)
                        IconButton(
                          tooltip: t('manage.remove_judge'),
                          icon: const Icon(LucideIcons.x, size: 20),
                          onPressed: _busy
                              ? null
                              : () => _call(() => ref.read(apiProvider).delete<dynamic>('/contests/${widget.c.id}/judges/${j['id']}')),
                        ),
                    ],
                  ),
                );
              },
            ),
          if (!locked) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _who,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(labelText: t('manage.judge_who'), hintText: t('manage.judge_placeholder')),
                  ),
                ),
                const SizedBox(width: Space.s2),
                SizedBox(
                  width: 84,
                  child: TextField(
                    controller: _weight,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: t('manage.weight')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.s3),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: p.surface2, foregroundColor: p.ink),
              onPressed: _busy ? null : _add,
              child: BusyLabel(busy: _busy, label: t('manage.add_judge')),
            ),
          ],
          const SizedBox(height: Space.s3),
          Text(t('manage.weight_hint'), style: font(13, height: 1.4, color: p.inkMuted)),
        ],
      ),
    );
  }
}

class _Entries extends ConsumerWidget {
  const _Entries({required this.c, required this.onChanged});
  final Contest c;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    final list = ref.watch(_adminEntriesProvider(c.id)).asData?.value ?? const <Entry>[];
    Future<void> disqualify(Entry e) async {
      final reason = await _prompt(context, t('manage.disqualify_reason'));
      if (reason == null) return;
      try {
        await ref.read(apiProvider).post<dynamic>('/contests/${c.id}/entries/${e.id}/disqualify', {'reason': reason});
        onChanged();
      } catch (err) {
        if (context.mounted) toast(context, errorText(context, err));
      }
    }

    return _Section(
      title: t('manage.entries', {'count': list.where((e) => !e.disqualified).length}),
      lead: c.status == 'open' ? t('manage.entries_private') : null,
      child: list.isEmpty
          ? Text(t('manage.no_entries'), style: font(15, color: p.inkMuted))
          : GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: Space.s3,
              crossAxisSpacing: Space.s3,
              childAspectRatio: 0.92,
              children: [
                for (final e in list)
                  Opacity(
                    opacity: e.disqualified ? 0.45 : 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Küçük resim kare içinde, kırpılmadan (contain)
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(Radii.photo)),
                            clipBehavior: Clip.antiAlias,
                            child: e.thumb == null ? null : NetPhoto(url: e.thumb!.url, fit: BoxFit.contain),
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Text(e.user?.displayName ?? e.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: font(13.5, color: p.ink)),
                            ),
                            if (e.disqualified)
                              Text(t('manage.disqualified'), style: font(12.5, weight: 600, color: p.danger))
                            else if (c.status != 'finished')
                              IconButton(
                                tooltip: t('manage.disqualify'),
                                icon: Icon(LucideIcons.ban, size: 18, color: p.inkMuted),
                                onPressed: () => disqualify(e),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Preview extends ConsumerWidget {
  const _Preview({required this.c});
  final Contest c;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    final rows = ref.watch(_resultsProvider(c.id)).asData?.value ?? const [];
    return _Section(
      title: t('manage.preview'),
      lead: t('manage.preview_lead'),
      child: Column(
        children: [
          for (final r in rows)
            Builder(
              builder: (_) {
                final e = r.entry;
                final score = r.score;
                final count = r.count;
                final scores = r.scores;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(width: 30, child: Text('${r.rank ?? '–'}', style: font(18, weight: 700, color: p.ink, tabular: true))),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 56,
                          height: 42,
                          color: p.surface2,
                          child: e.thumb == null ? null : NetPhoto(url: e.thumb!.url, fit: BoxFit.contain),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.user?.displayName ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: font(14.5, color: p.ink)),
                            // Jüri üyelerinin tek tek puanları (yalnızca yöneticiye gelir)
                            if (scores != null && scores.isNotEmpty)
                              Text(
                                scores.join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: font(12.5, color: p.inkMuted, tabular: true),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        '${score == null ? '–' : score.toStringAsFixed(2)} · '
                        '${t(c.judgingMode == 'jury' ? 'manage.judges_count' : 'manage.votes_count', {'count': count})}',
                        style: font(13, color: p.inkMuted, tabular: true),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ================================================================ Topluluk ayarları

class CommunitySettingsScreen extends ConsumerStatefulWidget {
  const CommunitySettingsScreen({super.key, required this.slug, this.created = false});
  final String slug;
  final bool created;

  @override
  ConsumerState<CommunitySettingsScreen> createState() => _CommunitySettingsScreenState();
}

class _CommunitySettingsScreenState extends ConsumerState<CommunitySettingsScreen> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _city = TextEditingController();
  final _country = TextEditingController();
  final _adminUser = TextEditingController();
  final _adminEmail = TextEditingController();
  bool _filled = false;
  String? _busy; // logo | cover | save | admin | invite

  static const _types = {
    'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'webp': 'image/webp', 'heic': 'image/heic', 'heif': 'image/heif',
  };

  @override
  void dispose() {
    for (final c in [_name, _desc, _city, _country, _adminUser, _adminEmail]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(Community c) {
    if (_filled) return;
    _filled = true;
    _name.text = c.name;
    _desc.text = c.description ?? '';
    _city.text = c.city ?? '';
    _country.text = c.country ?? '';
  }

  Future<void> _run(String what, Future<void> Function() fn, {String? done}) async {
    setState(() => _busy = what);
    try {
      await fn();
      ref.invalidate(communityProvider(widget.slug));
      ref.invalidate(communitiesProvider);
      if (done != null && mounted) toast(context, done);
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _image(String kind) async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    final type = _types[file.name.split('.').last.toLowerCase()];
    if (type == null) {
      toast(context, L10n.of(context)('quality.unsupported_format'));
      return;
    }
    await _run(kind, () async {
      final api = ref.read(apiProvider);
      final slot = await api.post<Map<String, dynamic>>('/communities/${widget.slug}/images/upload-url',
          {'kind': kind, 'content_type': type, 'size_bytes': await file.length()});
      final fields = (slot['fields'] as Map).map((k, v) => MapEntry('$k', '$v'));
      await api.uploadToStorage(slot['upload_url'] as String, fields, file.path, file.name, (_) {});
      await api.post<dynamic>('/communities/${widget.slug}/images/complete', {'kind': kind, 'key': fields['key']});
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final async = ref.watch(communityProvider(widget.slug));
    final c = async.asData?.value;
    if (c != null) _fill(c);
    return Scaffold(
      appBar: AppBar(title: Text(c?.name ?? '', style: font(16, weight: 600, color: p.inkMuted))),
      body: c == null
          ? (async.hasError
                ? ErrorView(error: async.error!, onRetry: () => ref.invalidate(communityProvider(widget.slug)))
                : const Center(child: CircularProgressIndicator()))
          : !c.isAdmin
          ? Padding(padding: const EdgeInsets.all(20), child: Notice(t('manage.forbidden'), tone: NoticeTone.error))
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 40),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                  child: Text(t('csettings.title'), style: AppText.display(p.ink)),
                ),
                if (widget.created) ...[
                  const SizedBox(height: Space.s3),
                  Notice(t('csettings.created'), tone: NoticeTone.success),
                ],
                // Görseller: kapak afiş olarak kırpılır; logo yuvarlatılmış kare
                _Section(
                  title: t('csettings.images'),
                  lead: t('csettings.images_hint'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(Radii.photo),
                        onTap: _busy == null ? () => _image('cover') : null,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.photo),
                          child: AspectRatio(
                            aspectRatio: 3,
                            child: Container(
                              color: p.surface2,
                              alignment: Alignment.center,
                              child: c.coverUrl != null
                                  ? NetPhoto(url: c.coverUrl!)
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(LucideIcons.camera, size: 18, color: p.inkMuted),
                                        const SizedBox(width: 8),
                                        Text(_busy == 'cover' ? t('csettings.uploading') : t('csettings.add_cover'),
                                            style: font(14, weight: 600, color: p.inkMuted)),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: Space.s3),
                      Row(
                        children: [
                          CommunityLogo(name: c.name, url: c.logoUrl, size: 64),
                          const SizedBox(width: Space.s3),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: p.surface2, foregroundColor: p.ink),
                            onPressed: _busy == null ? () => _image('logo') : null,
                            icon: const Icon(LucideIcons.camera, size: 18),
                            label: Text(_busy == 'logo' ? t('csettings.uploading') : t('csettings.change_logo')),
                          ),
                          if (c.coverUrl != null) ...[
                            const SizedBox(width: Space.s2),
                            TextButton(onPressed: _busy == null ? () => _image('cover') : null, child: Text(t('csettings.change_cover'))),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                _Section(
                  title: t('csettings.info'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(controller: _name, maxLength: 100, decoration: InputDecoration(labelText: t('csettings.name'))),
                      const SizedBox(height: 8),
                      TextField(controller: _desc, maxLength: 3000, minLines: 3, maxLines: 8, decoration: InputDecoration(labelText: t('csettings.description'))),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: _city, decoration: InputDecoration(labelText: t('csettings.city')))),
                          const SizedBox(width: Space.s2),
                          SizedBox(
                            width: 110,
                            child: TextField(
                              controller: _country,
                              maxLength: 2,
                              textCapitalization: TextCapitalization.characters,
                              decoration: InputDecoration(labelText: t('csettings.country'), counterText: ''),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.s4),
                      FilledButton(
                        onPressed: _busy != null
                            ? null
                            : () => _run(
                                'save',
                                () => ref.read(apiProvider).patch<dynamic>('/communities/${c.slug}', {
                                  'name': _name.text.trim(),
                                  'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
                                  'city': _city.text.trim().isEmpty ? null : _city.text.trim(),
                                  'country': _country.text.trim().isEmpty ? null : _country.text.trim().toUpperCase(),
                                }),
                                done: t('csettings.saved'),
                              ),
                        child: BusyLabel(busy: _busy == 'save', label: t('csettings.save')),
                      ),
                    ],
                  ),
                ),
                _Section(
                  title: t('csettings.join_approval'),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: c.joinApproval,
                    title: Text(t('csettings.join_approval'), style: font(15, weight: 600, color: p.ink)),
                    subtitle: Text(t('csettings.join_approval_hint'), style: font(13, color: p.inkMuted)),
                    onChanged: _busy != null
                        ? null
                        : (v) => _run(
                            'approval',
                            () => ref.read(apiProvider).patch<dynamic>('/communities/${c.slug}', {'join_approval': v}),
                          ),
                  ),
                ),
                if (c.myRole == 'owner')
                  _Section(
                    title: t('csettings.admins'),
                    lead: t('csettings.admins_lead'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PersonRow(user: c.owner, trailing: Text(t('community.role.owner'), style: AppText.caption(p.inkMuted))),
                        for (final a in c.admins)
                          _PersonRow(
                            user: a,
                            trailing: IconButton(
                              tooltip: t('csettings.remove_admin', {'name': a.displayName}),
                              icon: const Icon(LucideIcons.x, size: 20),
                              onPressed: _busy != null
                                  ? null
                                  : () => _run('admin', () => ref.read(apiProvider).delete<dynamic>('/communities/${c.slug}/admins/${a.username}')),
                            ),
                          ),
                        const SizedBox(height: Space.s3),
                        TextField(controller: _adminUser, decoration: InputDecoration(labelText: t('csettings.add_by_username'), hintText: '@kullanici')),
                        const SizedBox(height: Space.s2),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: p.surface2, foregroundColor: p.ink),
                          onPressed: _busy != null
                              ? null
                              : () => _run(
                                  'admin',
                                  () async {
                                    await ref.read(apiProvider).post<dynamic>('/communities/${c.slug}/admins',
                                        {'username': _adminUser.text.replaceFirst('@', '').trim()});
                                    _adminUser.clear();
                                  },
                                  done: t('csettings.admin_added'),
                                ),
                          child: BusyLabel(busy: _busy == 'admin', label: t('csettings.add_admin')),
                        ),
                        const SizedBox(height: Space.s4),
                        TextField(
                          controller: _adminEmail,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(labelText: t('csettings.invite_by_email'), helperText: t('csettings.invite_hint')),
                        ),
                        const SizedBox(height: Space.s2),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: p.surface2, foregroundColor: p.ink),
                          onPressed: _busy != null
                              ? null
                              : () => _run('invite', () async {
                                  final r = await ref.read(apiProvider).post<Map<String, dynamic>>('/communities/${c.slug}/invites',
                                      {'email': _adminEmail.text.trim()});
                                  _adminEmail.clear();
                                  if (mounted) {
                                    toast(this.context, r['status'] == 'added' ? t('csettings.admin_added') : t('csettings.invite_sent'));
                                  }
                                }),
                          child: BusyLabel(busy: _busy == 'invite', label: t('csettings.send_invite')),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.user, required this.trailing});
  final UserCard user;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Avatar(name: user.displayName, url: user.avatarUrl, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.displayName, style: font(15, weight: 600, color: p.ink)),
                Text('@${user.username}', style: AppText.caption(p.inkMuted)),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
