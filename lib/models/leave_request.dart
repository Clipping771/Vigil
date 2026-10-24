class LeaveRequest {
  final String id;
  final String? organizationId;
  final String employeeId;
  final String leaveType; // 'annual', 'sick', 'unpaid', 'maternity', 'paternity', 'compassionate', 'other'
  final DateTime startDate;
  final DateTime endDate;
  final String status; // 'pending', 'approved', 'declined', 'rejected'
  final String? reason;
  final DateTime? createdAt;
  final String? employeeName;
  final String? employeeEmail;
  final String? employeeRole;
  final String? employeeSite;

  LeaveRequest({
    required this.id,
    this.organizationId,
    required this.employeeId,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.reason,
    this.createdAt,
    this.employeeName,
    this.employeeEmail,
    this.employeeRole,
    this.employeeSite,
  });

  /// Duration in inclusive calendar days
  int get durationDays {
    final diff = endDate.difference(startDate).inDays;
    return diff >= 0 ? diff + 1 : 1;
  }

  bool get isPending => status.toLowerCase() == 'pending';
  bool get isApproved => status.toLowerCase() == 'approved';
  bool get isDeclined => status.toLowerCase() == 'declined' || status.toLowerCase() == 'rejected';

  /// Whether today falls within this approved leave period
  bool get isOngoingToday {
    if (!isApproved) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    return !today.isBefore(start) && !today.isAfter(end);
  }

  factory LeaveRequest.fromJson(Map<String, dynamic> json) {
    // Handle embedded employee object from Supabase join
    final empData = json['employees'] is Map<String, dynamic> 
        ? json['employees'] as Map<String, dynamic> 
        : null;

    return LeaveRequest(
      id: json['id']?.toString() ?? '',
      organizationId: json['organization_id']?.toString(),
      employeeId: json['employee_id']?.toString() ?? '',
      leaveType: json['leave_type']?.toString() ?? 'other',
      startDate: DateTime.tryParse(json['start_date']?.toString() ?? '') ?? DateTime.now(),
      endDate: DateTime.tryParse(json['end_date']?.toString() ?? '') ?? DateTime.now(),
      status: json['status']?.toString() ?? 'pending',
      reason: json['reason']?.toString(),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      employeeName: json['employee_name']?.toString() ?? empData?['full_name']?.toString(),
      employeeEmail: json['employee_email']?.toString() ?? empData?['email']?.toString(),
      employeeRole: json['employee_role']?.toString() ?? empData?['role']?.toString(),
      employeeSite: json['employee_site']?.toString() ?? empData?['site_location']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (organizationId != null) 'organization_id': organizationId,
      'employee_id': employeeId,
      'leave_type': leaveType,
      'start_date': startDate.toIso8601String().substring(0, 10),
      'end_date': endDate.toIso8601String().substring(0, 10),
      'status': status,
      'reason': reason,
    };
  }

  LeaveRequest copyWith({
    String? id,
    String? organizationId,
    String? employeeId,
    String? leaveType,
    DateTime? startDate,
    DateTime? endDate,
    String? status,
    String? reason,
    DateTime? createdAt,
    String? employeeName,
    String? employeeEmail,
    String? employeeRole,
    String? employeeSite,
  }) {
    return LeaveRequest(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      employeeId: employeeId ?? this.employeeId,
      leaveType: leaveType ?? this.leaveType,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      status: status ?? this.status,
      reason: reason ?? this.reason,
      createdAt: createdAt ?? this.createdAt,
      employeeName: employeeName ?? this.employeeName,
      employeeEmail: employeeEmail ?? this.employeeEmail,
      employeeRole: employeeRole ?? this.employeeRole,
      employeeSite: employeeSite ?? this.employeeSite,
    );
  }
}

