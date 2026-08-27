class ExceptionRecord {
  final String id;
  final String organizationId;
  final String employeeId;
  final String exceptionType;
  final String severity;
  final String? shiftId;
  final String status;
  final String? description;
  final DateTime createdAt;
  final DateTime? resolvedAt;

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
  });

  factory ExceptionRecord.fromJson(Map<String, dynamic> json) {
    return ExceptionRecord(
      id: json['id'],
      organizationId: json['organization_id'],
      employeeId: json['employee_id'],
      exceptionType: json['exception_type'],
      severity: json['severity'],
      shiftId: json['shift_id'],
      status: json['status'],
      description: json['description'],
      createdAt: DateTime.parse(json['created_at']),
      resolvedAt: json['resolved_at'] != null ? DateTime.parse(json['resolved_at']) : null,
    );
  }
}
