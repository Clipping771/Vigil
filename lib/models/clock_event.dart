class ClockEvent {
  final String id;
  final String organizationId;
  final String employeeId;
  final String eventType;
  final DateTime eventTime;
  final double? latitude;
  final double? longitude;
  final bool isGeofenced;
  final DateTime createdAt;

  ClockEvent({
    required this.id,
    required this.organizationId,
    required this.employeeId,
    required this.eventType,
    required this.eventTime,
    this.latitude,
    this.longitude,
    this.isGeofenced = false,
    required this.createdAt,
  });

  factory ClockEvent.fromJson(Map<String, dynamic> json) {
    return ClockEvent(
      id: json['id'],
      organizationId: json['organization_id'],
      employeeId: json['employee_id'],
      eventType: json['event_type'],
      eventTime: DateTime.parse(json['event_time']).toLocal(),
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
      isGeofenced: json['is_geofenced'] ?? false,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']).toLocal() : DateTime.now(),
    );
  }
}
