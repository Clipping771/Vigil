/// Employment types and their labels, as stored in `employees.employment_type`.
const employmentTypes = {
  'full_time': 'Full-time',
  'part_time': 'Part-time',
  'casual': 'Casual',
};

/// Default yearly (annual, sick) leave days for an employment type. Part-time
/// is null because it depends on the hours each person works.
(int, int)? defaultLeaveDays(String employmentType) => switch (employmentType) {
      'full_time' => (20, 10),
      'casual' => (0, 0),
      _ => null,
    };

class Employee {
  final String id;
  final String organizationId;
  final String email;
  final String fullName;
  final String role;
  final String? siteLocation;
  final DateTime createdAt;
  final String employmentType;
  final int annualLeaveDays;
  final int sickLeaveDays;

  Employee({
    required this.id,
    required this.organizationId,
    required this.email,
    required this.fullName,
    required this.role,
    this.siteLocation,
    required this.createdAt,
    this.employmentType = 'full_time',
    this.annualLeaveDays = 20,
    this.sickLeaveDays = 10,
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
      employmentType: json['employment_type'] ?? 'full_time',
      annualLeaveDays: json['annual_leave_days'] ?? 20,
      sickLeaveDays: json['sick_leave_days'] ?? 10,
    );
  }
}
