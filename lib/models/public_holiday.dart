/// A date an organization lists as a public holiday. Leave does not count it.
class PublicHoliday {
  final String id;
  final String organizationId;
  final DateTime date;
  final String name;

  const PublicHoliday({
    required this.id,
    required this.organizationId,
    required this.date,
    required this.name,
  });

  factory PublicHoliday.fromJson(Map<String, dynamic> json) {
    return PublicHoliday(
      id: json['id'].toString(),
      organizationId: json['organization_id'].toString(),
      date: DateTime.parse(json['holiday_date'].toString()),
      name: json['name']?.toString() ?? '',
    );
  }
}
