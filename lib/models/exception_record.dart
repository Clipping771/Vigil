class ExceptionRecord {
  final String id;
  final String organizationId;
  final String employeeId;
  final String exceptionType;
  final String severity; // 'critical', 'high', 'medium', 'low'
  final String? shiftId;
  final String status; // 'pending', 'resolved', 'ignored', 'acknowledged'
  final String? description;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? employeeName;
  final String? employeeEmail;
  final String? employeeRole;
  final String? siteLocation;
  final String? resolutionNote;

  ExceptionRecord({
    required this.id,
    required this.organizationId,
    required this.employeeId,
    required this.exceptionType,
    required this.severity,
    this.shiftId,
    required this.status,
    this.description,
    required this.createdAt,
    this.resolvedAt,
    this.employeeName,
    this.employeeEmail,
    this.employeeRole,
    this.siteLocation,
    this.resolutionNote,
  });

  bool get isPending => status.toLowerCase() == 'pending';
  bool get isResolved => status.toLowerCase() == 'resolved';
  bool get isAcknowledged => status.toLowerCase() == 'acknowledged';
  bool get isIgnored => status.toLowerCase() == 'ignored';

  bool get isCritical => severity.toLowerCase() == 'critical';
  bool get isHigh => severity.toLowerCase() == 'high';
  bool get isMedium => severity.toLowerCase() == 'medium';
  bool get isLow => severity.toLowerCase() == 'low';

  String get formattedType => exceptionType.replaceAll('_', ' ').toUpperCase();

  String get typeTitle {
    switch (exceptionType.toLowerCase()) {
      case 'missed_clock_in':
        return 'Missed Clock-In';
      case 'excessive_overtime':
        return 'Excessive Unapproved Overtime';
      case 'roster_breach':
        return 'Unscheduled Roster Breach';
      case 'geofence_violation':
        return 'Geofence Boundary Violation';
      case 'fair_work_compliance_breach':
        return 'Fair Work Act Rest/Break Breach';
      case 'leave_roster_conflict':
        return 'Leave & Roster Scheduling Conflict';
      case 'statistical_anomaly':
        return 'AI Statistical Anomaly Detected';
      case 'fraud_risk':
        return 'Suspected Ghost Punch / Fraud Risk';
      default:
        return formattedType;
    }
  }

  factory ExceptionRecord.fromJson(Map<String, dynamic> json) {
    final empData = json['employees'] is Map<String, dynamic>
        ? json['employees'] as Map<String, dynamic>
        : null;

    return ExceptionRecord(
      id: json['id']?.toString() ?? '',
      organizationId: json['organization_id']?.toString() ?? '',
      employeeId: json['employee_id']?.toString() ?? '',
      exceptionType: json['exception_type']?.toString() ?? 'roster_breach',
      severity: json['severity']?.toString() ?? 'medium',
      shiftId: json['shift_id']?.toString(),
      status: json['status']?.toString() ?? 'pending',
      description: json['description']?.toString(),
      createdAt: json['created_at'] != null 
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now() 
          : DateTime.now(),
      resolvedAt: json['resolved_at'] != null 
          ? DateTime.tryParse(json['resolved_at'].toString()) 
          : null,
      employeeName: json['employee_name']?.toString() ?? empData?['full_name']?.toString(),
      employeeEmail: json['employee_email']?.toString() ?? empData?['email']?.toString(),
      employeeRole: json['employee_role']?.toString() ?? empData?['role']?.toString(),
      siteLocation: json['site_location']?.toString() ?? empData?['site_location']?.toString(),
      resolutionNote: json['resolution_note']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'organization_id': organizationId,
      'employee_id': employeeId,
      'exception_type': exceptionType,
      'severity': severity,
      if (shiftId != null) 'shift_id': shiftId,
      'status': status,
      'description': description,
      'created_at': createdAt.toIso8601String(),
      if (resolvedAt != null) 'resolved_at': resolvedAt!.toIso8601String(),
      if (resolutionNote != null) 'resolution_note': resolutionNote,
    };
  }

  ExceptionRecord copyWith({
    String? id,
    String? organizationId,
    String? employeeId,
    String? exceptionType,
    String? severity,
    String? shiftId,
    String? status,
    String? description,
    DateTime? createdAt,
    DateTime? resolvedAt,
    String? employeeName,
    String? employeeEmail,
    String? employeeRole,
    String? siteLocation,
    String? resolutionNote,
  }) {
    return ExceptionRecord(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      employeeId: employeeId ?? this.employeeId,
      exceptionType: exceptionType ?? this.exceptionType,
      severity: severity ?? this.severity,
      shiftId: shiftId ?? this.shiftId,
      status: status ?? this.status,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      employeeName: employeeName ?? this.employeeName,
      employeeEmail: employeeEmail ?? this.employeeEmail,
      employeeRole: employeeRole ?? this.employeeRole,
      siteLocation: siteLocation ?? this.siteLocation,
      resolutionNote: resolutionNote ?? this.resolutionNote,
    );
  }
}
