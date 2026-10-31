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

/// Role of the signed-in preview user; change to preview other roles.
String previewRole = 'admin';
final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day);

Employee _emp(String id, String name, String role, [String? site]) => Employee(
      id: id,
      organizationId: _org,
      email: '${name.split(' ').first.toLowerCase()}@securelock.com',
      fullName: name,
      role: id == 'e1' ? previewRole : role,
      siteLocation: site,
      createdAt: _today,
    );

final _staff = [
  _emp('e1', 'Alice Smith', 'admin', 'Oakleigh HQ & Plant'),
  _emp('e2', 'Carol White', 'manager', 'Oakleigh HQ & Plant'),
  _emp('e3', 'Bob Jones', 'staff', 'Oakleigh HQ & Plant'),
  _emp('e4', 'Priya Patel', 'staff', 'Melbourne Distribution'),
  _emp('e5', 'Liam Nguyen', 'staff', 'Melbourne Distribution'),
  _emp('e6', 'Hana Ito', 'hr', 'Oakleigh HQ & Plant'),
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
  _shift('s1', 'e3', 7, 15, 'Oakleigh HQ & Plant'),
  _shift('s2', 'e4', 9, 17, 'Melbourne Distribution'),
  _shift('s3', 'e5', 12, 20, 'Melbourne Distribution'),
  _shift('s4', 'e1', 9, 17, 'Oakleigh HQ & Plant'),
  _shift('s5', 'e3', 7, 15, 'Oakleigh HQ & Plant', 1),
  _shift('s6', 'e4', 9, 17, 'Melbourne Distribution', 2),
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
        StaffLiveAttendance(employeeId: 'e3', fullName: 'Bob Jones', email: 'bob@securelock.com', role: 'staff',
            siteLocation: 'Oakleigh HQ & Plant', status: StaffWorkStatus.clockedIn,
            shiftStartTime: _today.add(const Duration(hours: 7, minutes: 2)), isGeofenced: true,
            lastEventTime: _today.add(const Duration(hours: 7, minutes: 2))),
        StaffLiveAttendance(employeeId: 'e4', fullName: 'Priya Patel', email: 'priya@securelock.com', role: 'staff',
            siteLocation: 'Melbourne Distribution', status: StaffWorkStatus.onBreak,
            shiftStartTime: _today.add(const Duration(hours: 9)), breakStartTime: _now.subtract(const Duration(minutes: 12)),
            isGeofenced: true, lastEventTime: _today.add(const Duration(hours: 9))),
        StaffLiveAttendance(employeeId: 'e5', fullName: 'Liam Nguyen', email: 'liam@securelock.com', role: 'staff',
            siteLocation: 'Melbourne Distribution', status: StaffWorkStatus.clockedOut),
        StaffLiveAttendance(employeeId: 'e2', fullName: 'Carol White', email: 'carol@securelock.com', role: 'manager',
            siteLocation: 'Oakleigh HQ & Plant', status: StaffWorkStatus.clockedOut),
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
            siteLocation: 'Oakleigh HQ & Plant');
    state = ExceptionState(allExceptions: [
      ex('x1', 'e5', 'Liam Nguyen', 'missed_clock_in', 'high', 'pending', 'Employee missed clock-in by more than 15 minutes at Melbourne Distribution.', 25),
      ex('x2', 'e3', 'Bob Jones', 'geofence_violation', 'high', 'pending', 'Clock-in registered 420 m outside the Oakleigh HQ & Plant zone.', 300),
      ex('x3', 'e4', 'Priya Patel', 'fair_work_compliance_breach', 'medium', 'acknowledged', 'Minimum 10-hour rest period not met between shifts (only 8.5 h).', 900),
      ex('x4', 'e3', 'Bob Jones', 'excessive_overtime', 'low', 'resolved', 'Clocked out 40 minutes after rostered end without pre-approval.', 3000),
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
      lr('l1', 'e4', 'Priya Patel', 'annual', 2, 4, 'pending', 'Family trip to Sydney'),
      lr('l2', 'e3', 'Bob Jones', 'sick', -3, -2, 'approved', 'Medical certificate provided'),
      lr('l3', 'e1', 'Alice Smith', 'annual', 20, 27, 'pending', 'Annual leave'),
      lr('l4', 'e5', 'Liam Nguyen', 'unpaid', 10, 10, 'declined', 'Personal commitment'),
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
  staffProvider.overrideWith((ref) => Stream.value(_staff)),
  rosterProvider.overrideWith((ref) => Stream.value(_shifts)),
  todayShiftProvider.overrideWith((ref) async => _shifts.first),
  geofenceProvider.overrideWith((ref) => Stream.value([
        GeofenceZone(id: 'z1', organizationId: _org, name: 'Oakleigh HQ & Plant', latitude: -37.8988, longitude: 145.0915, radiusMeters: 250, createdAt: _today),
        GeofenceZone(id: 'z2', organizationId: _org, name: 'Melbourne Distribution', latitude: -37.8136, longitude: 144.9631, radiusMeters: 200, createdAt: _today),
        GeofenceZone(id: 'z3', organizationId: _org, name: 'Sydney Branch', latitude: -33.8688, longitude: 151.2093, radiusMeters: 200, createdAt: _today),
      ])),
];
