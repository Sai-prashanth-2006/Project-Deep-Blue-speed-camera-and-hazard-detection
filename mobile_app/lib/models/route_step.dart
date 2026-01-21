class RouteStep {
  final String instruction;
  final double distance; // in meters
  final double duration; // in seconds
  final int type; // maneuver type (turn left, right, etc.)

  RouteStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.type,
  });

  factory RouteStep.fromJson(Map<String, dynamic> json) {
    return RouteStep(
      instruction: json['maneuver']?['instruction'] ?? "Follow route", // Fallback if OSRM format varies
      distance: (json['distance'] as num).toDouble(),
      duration: (json['duration'] as num).toDouble(),
      type: json['maneuver']?['type'] == 'turn' ? 1 : 0, // Simplified type mapping
    );
  }
}
