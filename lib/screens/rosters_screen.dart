import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';
import '../providers/roster_provider.dart';
import '../providers/staff_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/premium_card.dart';
import '../models/shift.dart';
import '../models/employee.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_shell.dart';
import '../theme/ui.dart';

class RostersScreen extends ConsumerStatefulWidget {
  const RostersScreen({super.key});

  @override
  ConsumerState<RostersScreen> createState() => _RostersScreenState();
}

class _RostersScreenState extends ConsumerState<RostersScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  Future<void> _deleteShift(String shiftId) async {
    try {
      await Supabase.instance.client.from('shifts').delete().eq('id', shiftId);
      ref.invalidate(rosterProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shift removed successfully.'), backgroundColor: Colors.orange));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting shift: $e'), backgroundColor: Colors.red));
      }
    }
  }

  List<Shift> _getShiftsForDay(DateTime day, Map<DateTime, List<Shift>> shiftsMap) {
    // Normalize to midnight UTC for lookup
    final normalized = DateTime.utc(day.year, day.month, day.day);
    return shiftsMap[normalized] ?? [];
  }

  Future<void> _showAddShiftDialog() async {
    final staffAsync = ref.read(staffProvider);
    if (!staffAsync.hasValue || staffAsync.value!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No employees found to assign shifts.')));
      return;
    }

    final employees = staffAsync.value!;
    Employee? selectedEmployee = employees.first;
    TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 17, minute: 0);
    final siteController = TextEditingController(text: selectedEmployee.siteLocation ?? 'Main Site');
    bool isSaving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: context.surfaceHigh,
              title: Text('Add Shift for ${DateFormat('MMM d').format(_selectedDay ?? _focusedDay)}', style: TextStyle(color: context.fg(), fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<Employee>(
                        initialValue: selectedEmployee,
                        dropdownColor: context.surfaceLowest,
                        style: TextStyle(color: context.fg()),
                        decoration: InputDecoration(labelText: 'Employee', labelStyle: TextStyle(color: context.fg(0.7)), border: OutlineInputBorder()),
                        items: employees.map((e) => DropdownMenuItem(value: e, child: Text(e.fullName))).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              selectedEmployee = val;
                              siteController.text = val.siteLocation ?? 'Main Site';
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(foregroundColor: context.fg(), side: BorderSide(color: context.fg(0.24))),
                              icon: const Icon(Icons.access_time, color: Color(0xFF38BDF8)),
                              label: Text('Start: ${startTime.format(context)}'),
                              onPressed: () async {
                                final time = await showTimePicker(context: context, initialTime: startTime);
                                if (time != null) setDialogState(() => startTime = time);
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(foregroundColor: context.fg(), side: BorderSide(color: context.fg(0.24))),
                              icon: const Icon(Icons.access_time, color: Color(0xFF38BDF8)),
                              label: Text('End: ${endTime.format(context)}'),
                              onPressed: () async {
                                final time = await showTimePicker(context: context, initialTime: endTime);
                                if (time != null) setDialogState(() => endTime = time);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: siteController,
                        style: TextStyle(color: context.fg()),
                        decoration: InputDecoration(labelText: 'Site Location', labelStyle: TextStyle(color: context.fg(0.7)), border: OutlineInputBorder()),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(context).pop(),
                  child: Text('Cancel', style: TextStyle(color: context.fg(0.54))),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF38BDF8), foregroundColor: Colors.black),
                  onPressed: isSaving ? null : () async {
                    if (selectedEmployee == null || siteController.text.trim().isEmpty) return;
                    setDialogState(() => isSaving = true);
                    
                    try {
                      final currentUser = ref.read(authProvider).currentUser;
                      if (currentUser == null) throw Exception('Not logged in');

                      final targetDay = _selectedDay ?? _focusedDay;
                      final startDateTime = DateTime(targetDay.year, targetDay.month, targetDay.day, startTime.hour, startTime.minute);
                      var endDateTime = DateTime(targetDay.year, targetDay.month, targetDay.day, endTime.hour, endTime.minute);
                      // An end time at or before the start means the shift runs past midnight.
                      if (!endDateTime.isAfter(startDateTime)) {
                        endDateTime = endDateTime.add(const Duration(days: 1));
                      }

                      final overlaps = await Supabase.instance.client
                          .from('shifts')
                          .select('id')
                          .eq('employee_id', selectedEmployee!.id)
                          .lt('start_time', endDateTime.toUtc().toIso8601String())
                          .gt('end_time', startDateTime.toUtc().toIso8601String())
                          .limit(1);
                      if ((overlaps as List).isNotEmpty) {
                        throw Exception('${selectedEmployee!.fullName} already has a shift that overlaps this time.');
                      }

                      await Supabase.instance.client.from('shifts').insert({
                        'organization_id': currentUser.organizationId,
                        'employee_id': selectedEmployee!.id,
                        'site_location': siteController.text.trim(),
                        'start_time': startDateTime.toUtc().toIso8601String(),
                        'end_time': endDateTime.toUtc().toIso8601String(),
                      });
                      
                      if (context.mounted) Navigator.of(context).pop(true);
                    } catch (e) {
                      setDialogState(() => isSaving = false);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red));
                      }
                    }
                  },
                  child: isSaving 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Text('Save Shift', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      },
    ).then((result) {
      if (result == true) ref.invalidate(rosterProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final groupedShiftsAsync = ref.watch(shiftsByDayProvider);
    final staffAsync = ref.watch(staffProvider);
    final user = ref.watch(authProvider).currentUser;
    final bool isAdminOrManager = user?.role == 'admin' || user?.role == 'owner' || user?.role == 'system_admin' || user?.role == 'manager';
    final theme = Theme.of(context);

    // Map employee IDs to full names
    final Map<String, String> employeeNames = {
      for (var e in staffAsync.value ?? <Employee>[]) e.id: e.fullName
    };

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(
          isAdminOrManager ? 'Team Rosters & Scheduling' : 'My Work Schedule', 
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: context.fg()),
        ),
        leading: ShellMenuButton.maybe(context),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: context.fg(0.7)),
            tooltip: 'Refresh Rosters',
            onPressed: () => ref.invalidate(rosterProvider),
          ),
          if (isAdminOrManager) ...[
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF38BDF8), foregroundColor: Colors.black),
              icon: const Icon(Icons.add),
              label: const Text('Add Shift', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: _showAddShiftDialog,
            ),
          ],
          const SizedBox(width: 16),
        ],
      ),
      body: groupedShiftsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.redAccent))),
        data: (shiftsMap) {
          final selectedShifts = _selectedDay != null ? _getShiftsForDay(_selectedDay!, shiftsMap) : [];

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PremiumCard(
                  blurRadius: 20,
                  opacity: 0.1,
                  padding: const EdgeInsets.all(16),
                  child: TableCalendar<Shift>(
                    firstDay: DateTime.utc(2020, 10, 16),
                    lastDay: DateTime.utc(2030, 3, 14),
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                    calendarFormat: _calendarFormat,
                    eventLoader: (day) => _getShiftsForDay(day, shiftsMap),
                    startingDayOfWeek: StartingDayOfWeek.monday,
                    calendarStyle: CalendarStyle(
                      outsideDaysVisible: false,
                      defaultTextStyle: TextStyle(color: context.fg()),
                      weekendTextStyle: TextStyle(color: context.fg(0.7)),
                      markerDecoration: const BoxDecoration(color: Color(0xFF00E5FF), shape: BoxShape.circle),
                      selectedDecoration: BoxDecoration(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF7C3AED), width: 1.5),
                      ),
                      todayDecoration: BoxDecoration(
                        color: context.fg().withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: context.fg(0.38)),
                      ),
                    ),
                    headerStyle: HeaderStyle(
                      formatButtonVisible: true,
                      titleCentered: true,
                      formatButtonDecoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.5)),
                      ),
                      formatButtonTextStyle: TextStyle(color: context.fg(), fontSize: 12),
                      titleTextStyle: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.fg()),
                      leftChevronIcon: Icon(Icons.chevron_left, color: context.fg()),
                      rightChevronIcon: Icon(Icons.chevron_right, color: context.fg()),
                    ),
                    daysOfWeekStyle: DaysOfWeekStyle(
                      weekdayStyle: TextStyle(color: context.fg(0.6), fontWeight: FontWeight.bold),
                      weekendStyle: TextStyle(color: context.fg(0.38), fontWeight: FontWeight.bold),
                    ),
                    onDaySelected: (selectedDay, focusedDay) {
                      if (!isSameDay(_selectedDay, selectedDay)) {
                        setState(() {
                          _selectedDay = selectedDay;
                          _focusedDay = focusedDay;
                        });
                      }
                    },
                    onFormatChanged: (format) {
                      if (_calendarFormat != format) {
                        setState(() => _calendarFormat = format);
                      }
                    },
                    onPageChanged: (focusedDay) {
                      _focusedDay = focusedDay;
                    },
                  ),
                ).animate().fadeIn().slideY(begin: -0.1, end: 0),
                const SizedBox(height: 24),
                
                // Header for the selected day's shifts
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _selectedDay != null 
                        ? (isSameDay(_selectedDay, DateTime.now()) ? 'Today\'s Shifts' : DateFormat('EEEE, MMM d').format(_selectedDay!))
                        : 'Select a day',
                      style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: context.fg()),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xFF00E5FF).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                      child: Text('${selectedShifts.length} Shifts', style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 12)),
                    )
                  ],
                ).animate().fadeIn(delay: 200.ms),
                const SizedBox(height: 16),
                
                // List of shifts for the selected day
                Expanded(
                  child: selectedShifts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isAdminOrManager ? Icons.calendar_today_outlined : Icons.event_busy_outlined, 
                                size: 64, 
                                color: context.fg(0.24),
                              ).animate().scale(),
                              const SizedBox(height: 16),
                              Text(
                                isAdminOrManager 
                                    ? 'No shifts scheduled for this day.' 
                                    : 'No Roster Assigned Yet',
                                style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: context.fg(0.7)),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                                child: Text(
                                  isAdminOrManager
                                      ? 'Click "Add Shift" above to assign an employee to this date.'
                                      : 'You have no scheduled shifts for this date. Your manager has not published a roster yet.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 14, color: context.fg(0.38)),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          key: ValueKey(_selectedDay),
                          itemCount: selectedShifts.length,
                          itemBuilder: (context, index) {
                            final shift = selectedShifts[index];
                            final timeFormat = DateFormat('h:mm a');
                            final empDisplayName = employeeNames[shift.employeeId] ?? 'Staff (${shift.employeeId.substring(0, 8)})';
                            
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: PremiumCard(
                                blurRadius: 10,
                                opacity: 0.05,
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
                                      ),
                                      child: const Icon(Icons.badge_outlined, color: Color(0xFF60A5FA), size: 20),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            isAdminOrManager ? empDisplayName : 'My Assigned Shift',
                                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: context.fg()),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(Icons.access_time, size: 14, color: context.fg(0.54)),
                                              const SizedBox(width: 4),
                                              Text('${timeFormat.format(shift.startTime.toLocal())} - ${timeFormat.format(shift.endTime.toLocal())}', style: TextStyle(color: context.fg(0.7), fontSize: 13)),
                                              const SizedBox(width: 16),
                                              Icon(Icons.location_on, size: 14, color: context.fg(0.54)),
                                              const SizedBox(width: 4),
                                              Text(shift.siteLocation, style: TextStyle(color: context.fg(0.7), fontSize: 13)),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isAdminOrManager)
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                        tooltip: 'Remove Shift',
                                        onPressed: () => _deleteShift(shift.id),
                                      ),
                                  ],
                                ),
                              ),
                            ).animate().fadeIn(delay: (50 * index).ms).slideX(begin: 0.1, end: 0);
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
