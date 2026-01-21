class SpeedZone {
  final int id;
  final double lat;
  final double lng;
  final double radius;
  final int limit;

  SpeedZone({
    required this.id,
    required this.lat,
    required this.lng,
    required this.radius,
    required this.limit,
  });

  factory SpeedZone.fromJson(Map<String, dynamic> json) {
    return SpeedZone(
      id: json['id'],
      lat: json['lat'],
      lng: json['lng'],
      radius: json['radius'].toDouble(),
      limit: json['limit'],
    );
  }
}
