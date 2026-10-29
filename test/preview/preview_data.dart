// Sample data and provider overrides for previewing and layout-testing the
// signed-in app without a backend.
import 'package:vigil/models/employee.dart';
import 'package:vigil/models/exception_record.dart';
import 'package:vigil/models/geofence_zone.dart';
import 'package:vigil/models/leave_request.dart';
import 'package:vigil/models/shift.dart';
import 'package:vigil/providers/attendance_provider.dart';
import 'package:vigil/providers/auth_provider.dart';
import 'package:vigil/providers/exception_provider.dart';
import 'package:vigil/providers/geofence_provider.dart';
import 'package:vigil/providers/leave_provider.dart';
import 'package:vigil/providers/live_workforce_provider.dart';
import 'package:vigil/providers/roster_provider.dart';
import 'package:vigil/providers/staff_provider.dart';

const _org = 'org-preview';

/// Role of the signed-in preview user (Olivia); change to preview other roles.
String previewRole = 'owner';
final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day);

Employee _emp(String id, String name, String role, [String? site]) => Employee(
      id: id,
      organizationId: _org,
      email: '${name.split(' ').first.toLowerCase()}@acme.test',
      fullName: name,
      role: id == 'e1' ? previewRole : role,
      siteLocation: site,
      createdAt: _today,
    );

final _staff = [
  _emp('e1', 'Olivia Owner', 'owner', 'Head Office'),
  _emp('e2', 'Max Manager', 'manager', 'Adelaide CBD'),
  _emp('e3', 'Sam Staff', 'staff', 'Adelaide CBD'),
  _emp('e4', 'Priya Patel', 'staff', 'Glenelg'),
  _emp('e5', 'Liam Nguyen', 'staff', 'Glenelg'),
  _emp('e6', 'Hana Ito', 'hr', 'Head Office'),
];

Shift _shift(String id, String emp, int startH, int endH, String site, [int dayOffset = 0]) => Shift(
      id: id,
      organizationId: _org,
      employeeId: emp,
      siteLocation: site,
      startTime: _today.add(Duration(days: dayOffset, hours: startH)),
      endTime: _today.add(Duration(days: dayOffset, hours: endH)),
      createdAt: _today,
    );

final _shifts = [
  _shift('s1', 'e3', 7, 15, 'Adelaide CBD'),
  _shift('s2', 'e4', 9, 17, 'Glenelg'),
  _shift('s3', 'e5', 12, 20, 'Glenelg'),
  _shift('s4', 'e1', 9, 17, 'Head Office'),
  _shift('s5', 'e3', 7, 15, 'Adelaide CBD', 1),
  _shift('s6', 'e4', 9, 17, 'Glenelg', 2),
];

class _Auth extends AuthNotifier {
  _Auth() {
    state = AuthState(initialized: true, currentUser: _staff.first);
  }
}

class _Workforce extends WorkforceNotifier {
  _Workforce(super.ref) {
    state = WorkforceState(
      employeeNames: {for (final e in _staff) e.id: e.fullName},
      staffList: [
        StaffLiveAttendance(employeeId: 'e3', fullName: 'Sam Staff', email: 'sam@acme.test', role: 'staff',
            siteLocation: 'Adelaide CBD', status: StaffWorkStatus.clockedIn,
            shiftStartTime: _today.add(const Duration(hours: 7, minutes: 2)), isGeofenced: true,
            lastEventTime: _today.add(const Duration(hours: 7, minutes: 2))),
        StaffLiveAttendance(employeeId: 'e4', fullName: 'Priya Patel', email: 'priya@acme.test', role: 'staff',
            siteLocation: 'Glenelg', status: StaffWorkStatus.onBreak,
            shiftStartTime: _today.add(const Duration(hours: 9)), breakStartTime: _now.subtract(const Duration(minutes: 12)),
            isGeofenced: true, lastEventTime: _today.add(const Duration(hours: 9))),
        StaffLiveAttendance(employeeId: 'e5', fullName: 'Liam Nguyen', email: 'liam@acme.test', role: 'staff',
            siteLocation: 'Glenelg', status: StaffWorkStatus.clockedOut),
        StaffLiveAttendance(employeeId: 'e2', fullName: 'Max Manager', email: 'max@acme.test', role: 'manager',
            siteLocation: 'Adelaide CBD', status: StaffWorkStatus.clockedOut),
      ],
    );
  }
  @override
  Future<void> loadWorkforce() async {}
}

class _Exceptions extends ExceptionNotifier {
  _Exceptions(super.ref) {
    ExceptionRecord ex(String id, String emp, String name, String type, String sev, String status, String desc, int minsAgo) =>
        ExceptionRecord(id: id, organizationId: _org, employeeId: emp, employeeName: name, exceptionType: type,
            severity: sev, status: status, description: desc, createdAt: _now.subtract(Duration(minutes: minsAgo)),
            siteLocation: 'Glenelg');
    state = ExceptionState(allExceptions: [
      ex('x1', 'e5', 'Liam Nguyen', 'missed_clock_in', 'high', 'pending', 'Employee missed clock-in by more than 15 minutes.', 25),
      ex('x2', 'e3', 'Sam Staff', 'geofence_violation', 'high', 'pending', 'Clock-in registered 420 m outside the Adelaide CBD site.', 300),
      ex('x3', 'e4', 'Priya Patel', 'fair_work_compliance_breach', 'medium', 'acknowledged', 'Minimum 10-hour rest period not met between shifts (only 8.5 h).', 900),
      ex('x4', 'e3', 'Sam Staff', 'excessive_overtime', 'low', 'resolved', 'Clocked out 40 minutes after rostered end.', 3000),
    ]);
  }
  @override
  Future<void> fetchExceptions({bool silent = false}) async {}
}

class _Leave extends LeaveNotifier {
  _Leave(super.ref) {
    LeaveRequest lr(String id, String emp, String name, String type, int from, int to, String status, String reason) => LeaveRequest(
        id: id, organizationId: _org, employeeId: emp, employeeName: name, leaveType: type,
        startDate: _today.add(Duration(days: from)), endDate: _today.add(Duration(days: to)), status: status, reason: reason);
    state = LeaveState(requests: [
      lr('l1', 'e4', 'Priya Patel', 'annual', 2, 4, 'pending', 'Family trip to Melbourne'),
      lr('l2', 'e3', 'Sam Staff', 'sick', -3, -2, 'approved', 'Flu, medical certificate provided'),
      lr('l3', 'e1', 'Olivia Owner', 'annual', 20, 27, 'pending', 'Annual holiday'),
      lr('l4', 'e5', 'Liam Nguyen', 'unpaid', 10, 10, 'declined', 'Concert'),
    ]);
  }
  @override
  Future<void> loadLeaveRequests({bool silent = false}) async {}
}

class _Attendance extends AttendanceNotifier {
  _Attendance(super.ref) {
    state = AttendanceState(
      status: ShiftStatus.clockedIn,
      lastClockIn: _today.add(const Duration(hours: 9)),
      totalBreakDuration: const Duration(minutes: 30),
      currentSegmentBreak: const Duration(minutes: 30),
    );
  }
  @override
  Future<void> loadTodayAttendance() async {}
}

final previewOverrides = [
  authProvider.overrideWith((ref) => _Auth()),
  workforceProvider.overrideWith((ref) => _Workforce(ref)),
  exceptionStateProvider.overrideWith((ref) => _Exceptions(ref)),
  leaveStateProvider.overrideWith((ref) => _Leave(ref)),
  attendanceProvider.overrideWith((ref) => _Attendance(ref)),
  staffProvider.overrideWith((ref) async => _staff),
  rosterProvider.overrideWith((ref) async => _shifts),
  todayShiftProvider.overrideWith((ref) async => _shifts.first),
  geofenceProvider.overrideWith((ref) async => [
        GeofenceZone(id: 'z1', organizationId: _org, name: 'Adelaide CBD', latitude: -34.9285, longitude: 138.6007, radiusMeters: 150, createdAt: _today),
        GeofenceZone(id: 'z2', organizationId: _org, name: 'Glenelg', latitude: -34.9800, longitude: 138.5150, radiusMeters: 200, createdAt: _today),
      ]),
];
