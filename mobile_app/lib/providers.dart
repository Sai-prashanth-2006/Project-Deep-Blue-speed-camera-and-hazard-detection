import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'services/api_service.dart';
import 'services/websocket_service.dart';
import 'models/hazard.dart';

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
        state = [...state, hazard];
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

final activeRouteProvider = NotifierProvider<ActiveRouteNotifier, List<LatLng>>(() {
  return ActiveRouteNotifier();
});

class ActiveRouteNotifier extends Notifier<List<LatLng>> {
  @override
  List<LatLng> build() {
    return [];
  }
  
  void updateRoute(List<LatLng> newRoute) {
    state = newRoute;
  }
}
