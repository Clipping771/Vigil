class Shift {
  final String id;
  final String organizationId;
  final String employeeId;
  final String siteLocation;
  final DateTime startTime;
  final DateTime endTime;
  final DateTime createdAt;

  Shift({
    required this.id,
    required this.organizationId,
    required this.employeeId,
    required this.siteLocation,
    required this.startTime,
    required this.endTime,
    required this.createdAt,
  });

  factory Shift.fromJson(Map<String, dynamic> json) {
    return Shift(
      id: json['id'],
      organizationId: json['organization_id'],
      employeeId: json['employee_id'],
      siteLocation: json['site_location'],
      startTime: DateTime.parse(json['start_time']),
      endTime: DateTime.parse(json['end_time']),
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
