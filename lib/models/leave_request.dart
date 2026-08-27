class LeaveRequest {
  final String id;
  final String employeeId;
  final String leaveType; // 'annual', 'sick', 'unpaid'
  final DateTime startDate;
  final DateTime endDate;
  final String status; // 'pending', 'approved', 'rejected'
  final String? reason;

  LeaveRequest({
    required this.id,
    required this.employeeId,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.reason,
  });

  factory LeaveRequest.fromJson(Map<String, dynamic> json) {
    return LeaveRequest(
      id: json['id'],
      employeeId: json['employee_id'],
      leaveType: json['leave_type'],
      startDate: DateTime.parse(json['start_date']),
      endDate: DateTime.parse(json['end_date']),
      status: json['status'],
      reason: json['reason'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'employee_id': employeeId,
      'leave_type': leaveType,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'status': status,
      'reason': reason,
    };
  }
}
