import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/search_result.dart';
import '../models/hazard.dart';
import '../models/speed_zone.dart';

class ApiService {
  static String get baseUrl {
    if (kIsWeb) return 'http://127.0.0.1:8000';
    // For Physical Device, use 127.0.0.1 and run "adb reverse tcp:8000 tcp:8000"
    // For Emulator, 10.0.2.2 is standard, but 127.0.0.1 + adb reverse works for both.
    if (defaultTargetPlatform == TargetPlatform.android) return 'http://127.0.0.1:8000';
    return 'http://127.0.0.1:8000';
  } 
  
  Future<List<SearchResult>> searchPlaces(String query, {double? lat, double? lng}) async {
    String url = '$baseUrl/search?q=$query';
    if (lat != null && lng != null) {
      url += '&lat=$lat&lon=$lng';
    }
    
    final response = await http.get(Uri.parse(url));
    
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => SearchResult.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load search results');
    }
  }

  Future<List<List<LatLng>>> getRoutes(LatLng start, LatLng end) async {
    final startStr = "${start.latitude},${start.longitude}";
    final endStr = "${end.latitude},${end.longitude}";
    
    // Request alternatives
    final response = await http.get(Uri.parse('$baseUrl/route?start=$startStr&end=$endStr&alternatives=true'));
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['routes'] != null) {
        // Return list of routes (each route is a list of LatLng)
        return (data['routes'] as List).map<List<LatLng>>((route) {
           final geometry = route['geometry'];
           final coordinates = geometry['coordinates'] as List;
           return coordinates.map<LatLng>((coord) {
             return LatLng(coord[1], coord[0]);
           }).toList();
        }).toList();
      }
      return [];
    } else {
      throw Exception('Failed to load route');
    }
  }

  // Deprecated single route method, kept for compatibility if needed or redirect
  Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {
    final routes = await getRoutes(start, end);
    if (routes.isNotEmpty) return routes.first;
    return [];
  }
  
  // existing getHazards...

  Future<void> deleteHazard(int id) async {
    final response = await http.delete(Uri.parse('$baseUrl/hazards/$id'));
    if (response.statusCode != 200) {
       throw Exception('Failed to delete hazard');
    }
  }

  Future<List<Hazard>> getHazards() async {
    final response = await http.get(Uri.parse('$baseUrl/hazards'));
    
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Hazard.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load hazards');
    }
  }

  Future<void> reportHazard(double lat, double lng, String type, String tag, String description) async {
    final response = await http.post(
      Uri.parse('$baseUrl/hazards'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'lat': lat,
        'lng': lng,
        'type': type,
        'tag': tag,
        'description': description,
        'verified': false,
      }),
    );
    
    if (response.statusCode != 200) {
      throw Exception('Failed to report hazard');
    }
  }

  Future<List<SpeedZone>> getSpeedZones() async {
    final response = await http.get(Uri.parse('$baseUrl/speed-zones'));
    
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => SpeedZone.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load speed zones');
    }
  }
}
