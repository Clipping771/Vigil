import '../models/shift.dart';
import '../models/exception_record.dart';

class ComplianceEngine {
  // Fair Work Act constants (simplified for prototype)
  static const int minBreakMinutes = 30;
  static const int minHoursBeforeBreak = 5;
  static const int maxShiftHours = 12;

  static List<ExceptionRecord> checkShiftCompliance(Shift shift) {
    List<ExceptionRecord> violations = [];
    final shiftDurationHours = shift.endTime.difference(shift.startTime).inHours;

    // 1. Max Shift Hours Check
    if (shiftDurationHours > maxShiftHours) {
      violations.add(ExceptionRecord(
        id: 'fw-${DateTime.now().millisecondsSinceEpoch}',
        employeeId: shift.employeeId,
        exceptionType: 'fair_work_violation',
        severity: 'high',
        shiftId: shift.id,
        status: 'pending',
        description: 'Shift exceeds Fair Work maximum of $maxShiftHours hours.',
        createdAt: DateTime.now(),
      ));
    }

    // 2. Break Minimums Check (Assuming shift has a break logged, simplified check)
    if (shiftDurationHours >= minHoursBeforeBreak) {
      // In a real system, we'd check actual break clock events. 
      // For prototype, we flag a warning to ensure breaks are scheduled.
       violations.add(ExceptionRecord(
        id: 'fw-break-${DateTime.now().millisecondsSinceEpoch}',
        employeeId: shift.employeeId,
        exceptionType: 'compliance_warning',
        severity: 'medium',
        shiftId: shift.id,
        status: 'pending',
        description: 'Shift is over $minHoursBeforeBreak hours. Ensure a ${minBreakMinutes}m break is provided.',
        createdAt: DateTime.now(),
      ));
    }

    return violations;
  }
}
