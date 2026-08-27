import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
import 'package:uuid/uuid.dart';

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
              title: Text('Add Shift for ${DateFormat('MMM d').format(_selectedDay ?? _focusedDay)}'),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<Employee>(
                        value: selectedEmployee,
                        decoration: const InputDecoration(labelText: 'Employee', border: OutlineInputBorder()),
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
                              icon: const Icon(Icons.access_time),
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
                              icon: const Icon(Icons.access_time),
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
                        decoration: const InputDecoration(labelText: 'Site Location', border: OutlineInputBorder()),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSaving ? null : () async {
                    if (selectedEmployee == null || siteController.text.trim().isEmpty) return;
                    setDialogState(() => isSaving = true);
                    
                    try {
                      final currentUser = ref.read(authProvider).currentUser;
                      if (currentUser == null) throw Exception('Not logged in');

                      final targetDay = _selectedDay ?? _focusedDay;
                      final startDateTime = DateTime(targetDay.year, targetDay.month, targetDay.day, startTime.hour, startTime.minute);
                      final endDateTime = DateTime(targetDay.year, targetDay.month, targetDay.day, endTime.hour, endTime.minute);

                      final fakeId = const Uuid().v4();
                      await Supabase.instance.client.from('shifts').insert({
                        'id': fakeId,
                        'organization_id': currentUser.organizationId,
                        'employee_id': selectedEmployee!.id,
                        'site_location': siteController.text.trim(),
                        'start_time': startDateTime.toUtc().toIso8601String(),
                        'end_time': endDateTime.toUtc().toIso8601String(),
                      });
                      
                      if (mounted) Navigator.of(context).pop(true);
                    } catch (e) {
                      setDialogState(() => isSaving = false);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add: $e'), backgroundColor: Colors.red));
                      }
                    }
                  },
                  child: isSaving 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save Shift'),
                ),
              ],
            );
          }
        );
      },
    ).then((result) {
      if (result == true) ref.refresh(rosterProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final groupedShiftsAsync = ref.watch(shiftsByDayProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Rosters & Shifts', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/dashboard'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: () => ref.refresh(rosterProvider),
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Shift'),
            onPressed: _showAddShiftDialog,
          ),
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
                      defaultTextStyle: const TextStyle(color: Colors.white),
                      weekendTextStyle: const TextStyle(color: Colors.white70),
                      markerDecoration: const BoxDecoration(color: Color(0xFF00E5FF), shape: BoxShape.circle),
                      selectedDecoration: BoxDecoration(
                        color: const Color(0xFF7C3AED).withOpacity(0.5),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF7C3AED), width: 1.5),
                      ),
                      todayDecoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white38),
                      ),
                    ),
                    headerStyle: HeaderStyle(
                      formatButtonVisible: true,
                      titleCentered: true,
                      formatButtonDecoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.5)),
                      ),
                      formatButtonTextStyle: const TextStyle(color: Colors.white, fontSize: 12),
                      titleTextStyle: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      leftChevronIcon: const Icon(Icons.chevron_left, color: Colors.white),
                      rightChevronIcon: const Icon(Icons.chevron_right, color: Colors.white),
                    ),
                    daysOfWeekStyle: const DaysOfWeekStyle(
                      weekdayStyle: TextStyle(color: Colors.white60, fontWeight: FontWeight.bold),
                      weekendStyle: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold),
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
                      style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xFF00E5FF).withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
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
                              Icon(Icons.event_available, size: 64, color: Colors.white24).animate().scale(),
                              const SizedBox(height: 16),
                              Text('No shifts scheduled for this day.', style: GoogleFonts.outfit(fontSize: 18, color: Colors.white54)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          key: ValueKey(_selectedDay), // Force list rebuild to re-trigger animations when day changes
                          itemCount: selectedShifts.length,
                          itemBuilder: (context, index) {
                            final shift = selectedShifts[index];
                            final timeFormat = DateFormat('h:mm a');
                            
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
                                        color: const Color(0xFF3B82F6).withOpacity(0.1),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3)),
                                      ),
                                      child: const Icon(Icons.person, color: Color(0xFF60A5FA), size: 20),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'UID: ${shift.employeeId.substring(0, 8)}',
                                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Icon(Icons.access_time, size: 14, color: Colors.white54),
                                              const SizedBox(width: 4),
                                              Text('${timeFormat.format(shift.startTime)} - ${timeFormat.format(shift.endTime)}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                              const SizedBox(width: 16),
                                              const Icon(Icons.location_on, size: 14, color: Colors.white54),
                                              const SizedBox(width: 4),
                                              Text(shift.siteLocation, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right, color: Colors.white24)
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
