import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/employee.dart';
import '../models/shift.dart';
import '../providers/auth_provider.dart';
import '../providers/roster_provider.dart';
import '../providers/staff_provider.dart';
import '../widgets/app_shell.dart';
import '../widgets/ui_kit.dart';

class RostersScreen extends ConsumerStatefulWidget {
  const RostersScreen({super.key});

  @override
  ConsumerState<RostersScreen> createState() => _RostersScreenState();
}

class _RostersScreenState extends ConsumerState<RostersScreen> {
  CalendarFormat _format = CalendarFormat.month;
  DateTime _focused = DateTime.now();
  DateTime _selected = DateUtils.dateOnly(DateTime.now());

  List<Shift> _shiftsOn(DateTime day, Map<DateTime, List<Shift>> map) =>
      map[DateTime.utc(day.year, day.month, day.day)] ?? const [];

  @override
  Widget build(BuildContext context) {
    final grouped = ref.watch(shiftsByDayProvider);
    final staff = ref.watch(staffProvider).value ?? const <Employee>[];
    final me = ref.watch(authProvider).currentUser;
    final isManager = me?.isManager ?? false;
    final names = {for (final e in staff) e.id: e.fullName};
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return AppPage(
      title: isManager ? 'Rosters' : 'My schedule',
      maxWidth: 1000,
      actions: [
        IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(rosterProvider)),
      ],
      floatingActionButton: isManager
          ? FloatingActionButton.extended(
              heroTag: 'add-shift',
              onPressed: _addShift,
              icon: const Icon(Icons.add),
              label: const Text('Add shift'),
            )
          : null,
      children: [
        const SizedBox(height: 8),
        grouped.when(
          loading: () => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
          error: (_, _) => Card(
            child: EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load the roster',
              action: OutlinedButton(onPressed: () => ref.invalidate(rosterProvider), child: const Text('Try again')),
            ),
          ),
          data: (map) {
            final dayShifts = [..._shiftsOn(_selected, map)]..sort((a, b) => a.startTime.compareTo(b.startTime));
            final isToday = DateUtils.isSameDay(_selected, DateTime.now());
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                    child: TableCalendar<Shift>(
                      firstDay: DateTime.utc(2020, 1, 1),
                      lastDay: DateTime.utc(2035, 12, 31),
                      focusedDay: _focused,
                      selectedDayPredicate: (d) => isSameDay(_selected, d),
                      calendarFormat: _format,
                      availableCalendarFormats: const {CalendarFormat.month: 'Month', CalendarFormat.twoWeeks: '2 weeks', CalendarFormat.week: 'Week'},
                      eventLoader: (d) => _shiftsOn(d, map),
                      startingDayOfWeek: StartingDayOfWeek.monday,
                      headerStyle: HeaderStyle(
                        titleCentered: false,
                        titleTextStyle: t.titleLarge!,
                        formatButtonShowsNext: false,
                        formatButtonTextStyle: t.labelLarge!.copyWith(color: cs.primary),
                        formatButtonDecoration: BoxDecoration(
                          border: Border.all(color: cs.outline),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        leftChevronIcon: Icon(Icons.chevron_left, color: cs.onSurfaceVariant),
                        rightChevronIcon: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                      ),
                      daysOfWeekStyle: DaysOfWeekStyle(
                        weekdayStyle: t.labelMedium!.copyWith(color: cs.onSurfaceVariant),
                        weekendStyle: t.labelMedium!.copyWith(color: cs.onSurfaceVariant),
                      ),
                      calendarStyle: CalendarStyle(
                        outsideDaysVisible: false,
                        defaultTextStyle: t.bodyMedium!,
                        weekendTextStyle: t.bodyMedium!,
                        todayDecoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: cs.primary)),
                        todayTextStyle: t.bodyMedium!.copyWith(color: cs.primary, fontWeight: FontWeight.w600),
                        selectedDecoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                        selectedTextStyle: t.bodyMedium!.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w600),
                        markerDecoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                        markersMaxCount: 3,
                        markerSize: 5,
                      ),
                      onDaySelected: (sel, foc) => setState(() {
                        _selected = DateUtils.dateOnly(sel);
                        _focused = foc;
                      }),
                      onFormatChanged: (f) => setState(() => _format = f),
                      onPageChanged: (f) => _focused = f,
                    ),
                  ),
                ),
                SectionHeader(
                  isToday ? "Today's shifts" : DateFormat('EEEE, d MMMM').format(_selected),
                  subtitle: '${dayShifts.length} ${dayShifts.length == 1 ? 'shift' : 'shifts'}',
                ),
                Card(
                  child: dayShifts.isEmpty
                      ? EmptyState(
                          icon: Icons.event_available_outlined,
                          title: 'No shifts on this day',
                          message: isManager ? 'Use "Add shift" to roster someone.' : 'You are not rostered on this day.',
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < dayShifts.length; i++) ...[
                              if (i > 0) const Divider(indent: 72),
                              Builder(builder: (context) {
                                final s = dayShifts[i];
                                final name = names[s.employeeId] ?? (s.employeeId == me?.id ? me!.fullName : 'Team member');
                                final hours = s.endTime.difference(s.startTime).inMinutes / 60;
                                final time = '${DateFormat('h:mm a').format(s.startTime.toLocal())} – ${DateFormat('h:mm a').format(s.endTime.toLocal())}';
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  leading: UserAvatar(name: name, radius: 20),
                                  title: Text(name, style: t.titleSmall),
                                  subtitle: Text('$time  ·  ${hours.toStringAsFixed(hours % 1 == 0 ? 0 : 1)} h  ·  ${s.siteLocation}',
                                      style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                                  trailing: isManager
                                      ? IconButton(
                                          tooltip: 'Remove shift',
                                          icon: const Icon(Icons.delete_outline),
                                          onPressed: () => _deleteShift(s),
                                        )
                                      : null,
                                );
                              }),
                            ],
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _deleteShift(Shift s) async {
    final ok = await confirmDialog(
      context,
      title: 'Remove shift?',
      message: 'The employee will no longer be rostered for this shift.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok) return;
    try {
      await Supabase.instance.client.from('shifts').delete().eq('id', s.id);
      ref.invalidate(rosterProvider);
      if (mounted) showMessage(context, 'Shift removed.');
    } catch (_) {
      if (mounted) showMessage(context, 'Could not remove the shift. You may not have permission.');
    }
  }

  Future<void> _addShift() async {
    final me = ref.read(authProvider).currentUser;
    if (me == null) return;
    final List<Employee> employees;
    try {
      employees = await ref.read(staffProvider.future);
    } catch (_) {
      if (mounted) showMessage(context, 'Could not load your team. Try again.');
      return;
    }
    if (!mounted) return;
    if (employees.isEmpty) {
      showMessage(context, 'Invite employees from the Staff page before adding shifts.');
      return;
    }

    Employee employee = employees.first;
    var day = _selected;
    var start = const TimeOfDay(hour: 9, minute: 0);
    var end = const TimeOfDay(hour: 17, minute: 0);
    final site = TextEditingController(text: employee.siteLocation ?? '');
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setLocal) {
          final overnight = end.hour * 60 + end.minute <= start.hour * 60 + start.minute;
          return AlertDialog(
            title: const Text('Add shift'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<Employee>(
                      initialValue: employee,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Employee'),
                      items: [for (final e in employees) DropdownMenuItem(value: e, child: Text(e.fullName))],
                      onChanged: (v) {
                        if (v == null) return;
                        setLocal(() {
                          employee = v;
                          if (site.text.trim().isEmpty) site.text = v.siteLocation ?? '';
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: day,
                          firstDate: DateTime.now().subtract(const Duration(days: 30)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) setLocal(() => day = picked);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Date', suffixIcon: Icon(Icons.calendar_today_outlined)),
                        child: Text(DateFormat('EEE, d MMM yyyy').format(day)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () async {
                              final v = await showTimePicker(context: context, initialTime: start);
                              if (v != null) setLocal(() => start = v);
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(labelText: 'Starts', suffixIcon: Icon(Icons.schedule)),
                              child: Text(start.format(context)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () async {
                              final v = await showTimePicker(context: context, initialTime: end);
                              if (v != null) setLocal(() => end = v);
                            },
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Ends',
                                suffixIcon: const Icon(Icons.schedule),
                                helperText: overnight ? 'Ends next day' : null,
                              ),
                              child: Text(end.format(context)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(controller: site, decoration: const InputDecoration(labelText: 'Site', hintText: 'e.g. Adelaide CBD')),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: saving ? null : () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (site.text.trim().isEmpty) {
                          showMessage(this.context, 'Enter the site for this shift.');
                          return;
                        }
                        setLocal(() => saving = true);
                        try {
                          final startAt = DateTime(day.year, day.month, day.day, start.hour, start.minute);
                          var endAt = DateTime(day.year, day.month, day.day, end.hour, end.minute);
                          if (!endAt.isAfter(startAt)) endAt = endAt.add(const Duration(days: 1));
                          final db = Supabase.instance.client;
                          final overlap = await db
                              .from('shifts')
                              .select('id')
                              .eq('employee_id', employee.id)
                              .lt('start_time', endAt.toUtc().toIso8601String())
                              .gt('end_time', startAt.toUtc().toIso8601String())
                              .limit(1);
                          if ((overlap as List).isNotEmpty) {
                            throw Exception('${employee.fullName} already has a shift at this time.');
                          }
                          await db.from('shifts').insert({
                            'organization_id': me.organizationId,
                            'employee_id': employee.id,
                            'site_location': site.text.trim(),
                            'start_time': startAt.toUtc().toIso8601String(),
                            'end_time': endAt.toUtc().toIso8601String(),
                          });
                          ref.invalidate(rosterProvider);
                          if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                          if (mounted) {
                            setState(() => _selected = DateUtils.dateOnly(day));
                            showMessage(this.context, 'Shift added.');
                          }
                        } catch (e) {
                          setLocal(() => saving = false);
                          if (mounted) showMessage(this.context, e.toString().replaceFirst('Exception: ', ''));
                        }
                      },
                child: saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Add shift'),
              ),
            ],
          );
        },
      ),
    );
    site.dispose();
  }
}
