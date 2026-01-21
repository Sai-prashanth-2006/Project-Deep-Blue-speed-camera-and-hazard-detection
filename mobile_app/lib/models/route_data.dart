import 'package:latlong2/latlong.dart';
import 'route_step.dart';

class RouteData {
  final List<LatLng> points;
  final List<RouteStep> steps;
  final double distance;
  final double duration;

  RouteData({
    required this.points,
    required this.steps,
    required this.distance,
    required this.duration,
  });
}
