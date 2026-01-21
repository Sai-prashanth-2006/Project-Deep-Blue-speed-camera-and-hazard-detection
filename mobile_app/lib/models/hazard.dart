class Hazard {
  final int id;
  final double lat;
  final double lng;
  final String type;
  final String tag;
  final String description;
  final bool verified;

  Hazard({
    required this.id,
    required this.lat,
    required this.lng,
    required this.type,
    required this.tag,
    required this.description,
    required this.verified,
  });

  factory Hazard.fromJson(Map<String, dynamic> json) {
    return Hazard(
      id: json['id'],
      lat: json['lat'],
      lng: json['lng'],
      type: json['type'],
      tag: json['tag'] ?? "Unknown", // Handle legacy/missing fields safely
      description: json['description'] ?? "No description",
      verified: json['verified'],
    );
  }
}
