import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/hazard.dart';

class WebSocketService {
  final WebSocketChannel _channel;

  static String get _wsUrl {
    if (kIsWeb) return 'ws://127.0.0.1:8000/ws';
    if (defaultTargetPlatform == TargetPlatform.android) return 'ws://127.0.0.1:8000/ws';
    return 'ws://127.0.0.1:8000/ws';
  }

  WebSocketService() 
      : _channel = WebSocketChannel.connect(
          Uri.parse(_wsUrl),
        );

  Stream<dynamic> get stream => _channel.stream;

  void dispose() {
    _channel.sink.close();
  }
  
  // Helper to parse message
  Hazard? parseHazardUpdate(String message) {
    try {
      final data = json.decode(message);
      if (data['type'] == 'new_hazard') {
        return Hazard.fromJson(data['data']);
      }
    } catch (e) {
      print("Error parsing WS message: $e");
    }
    return null;
  }
}
