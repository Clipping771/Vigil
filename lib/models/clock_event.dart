class ClockEvent {
  final String id;
  final String organizationId;
  final String employeeId;
  final String eventType;
  final DateTime eventTime;
  final DateTime createdAt;

  ClockEvent({
    required this.id,
    required this.organizationId,
    required this.employeeId,
    required this.eventType,
    required this.eventTime,
    required this.createdAt,
  });

  factory ClockEvent.fromJson(Map<String, dynamic> json) {
    return ClockEvent(
      id: json['id'],
      organizationId: json['organization_id'],
      employeeId: json['employee_id'],
      eventType: json['event_type'],
      eventTime: DateTime.parse(json['event_time']),
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
