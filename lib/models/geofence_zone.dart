class GeofenceZone {
  final String id;
  final String organizationId;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final DateTime createdAt;

  GeofenceZone({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.createdAt,
  });

  factory GeofenceZone.fromJson(Map<String, dynamic> json) {
    return GeofenceZone(
      id: json['id'],
      organizationId: json['organization_id'],
      name: json['name'],
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      radiusMeters: (json['radius_meters'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'organization_id': organizationId,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'radius_meters': radiusMeters,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
