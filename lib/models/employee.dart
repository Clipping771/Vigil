class Employee {
  final String id;
  final String organizationId;
  final String email;
  final String fullName;
  final String role;
  final String? siteLocation;
  final DateTime createdAt;

  Employee({
    required this.id,
    required this.organizationId,
    required this.email,
    required this.fullName,
    required this.role,
    this.siteLocation,
    required this.createdAt,
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['id'],
      organizationId: json['organization_id'],
      email: json['email'],
      fullName: json['full_name'],
      role: json['role'],
      siteLocation: json['site_location'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
