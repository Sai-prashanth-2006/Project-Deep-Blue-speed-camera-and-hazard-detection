import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'services/api_service.dart';
import 'services/websocket_service.dart';
import 'models/hazard.dart';
import 'models/route_data.dart';

final apiServiceProvider = Provider((ref) => ApiService());

final webSocketServiceProvider = Provider((ref) => WebSocketService());

final hazardsProvider = NotifierProvider<HazardsNotifier, List<Hazard>>(() {
  return HazardsNotifier();
});

class HazardsNotifier extends Notifier<List<Hazard>> {
  @override
  List<Hazard> build() {
    _loadInitialHazards();
    _listenToWebSocket();
    return [];
  }

  Future<void> _loadInitialHazards() async {
    try {
      final hazards = await ref.read(apiServiceProvider).getHazards();
      state = hazards;
    } catch (e) {
      print("Error loading hazards: $e");
    }
  }

  void _listenToWebSocket() {
    final ws = ref.read(webSocketServiceProvider);
    ws.stream.listen((message) {
      final jsonMsg = json.decode(message);
      if (jsonMsg['type'] == 'new_hazard') {
        final hazard = Hazard.fromJson(jsonMsg['data']);
        // Check if exists to update/replace, else add
        final index = state.indexWhere((h) => h.id == hazard.id);
        if (index >= 0) {
           // Update existing
           final newState = [...state];
           newState[index] = hazard;
           state = newState;
        } else {
           // Add new
           state = [...state, hazard];
        }
      } else if (jsonMsg['type'] == 'delete_hazard') {
        final id = jsonMsg['id'];
        state = state.where((h) => h.id != id).toList();
      }
    });
  }

  Future<void> addHazard(double lat, double lng, String type, String tag, String description) async {
    await ref.read(apiServiceProvider).reportHazard(lat, lng, type, tag, description);
  }

  Future<void> removeHazard(int id) async {
    try {
      await ref.read(apiServiceProvider).deleteHazard(id);
      // Optimistically remove or wait for WS. Let's wait for WS "delete_hazard" event to be robust
    } catch (e) {
      print("Error removing hazard: $e");
    }
  }
}

// Stores the currently active route data (including steps)
final activeRouteProvider = NotifierProvider<ActiveRouteNotifier, RouteData?>(() {
  return ActiveRouteNotifier();
});

class ActiveRouteNotifier extends Notifier<RouteData?> {
  @override
  RouteData? build() {
    return null;
  }
  
  void updateRoute(RouteData newRoute) {
    state = newRoute;
  }
  
  void clearRoute() {
    state = null;
  }
}

// Stores the selected vehicle type
final vehicleTypeProvider = NotifierProvider<VehicleTypeNotifier, String>(() {
  return VehicleTypeNotifier();
});

class VehicleTypeNotifier extends Notifier<String> {
  @override
  String build() {
    return 'car';
  }

  void setType(String type) {
    state = type;
  }
}

