import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_service.dart';

class ApiWebSocketService {
  static final ApiWebSocketService _instance = ApiWebSocketService._internal();
  factory ApiWebSocketService() => _instance;
  ApiWebSocketService._internal();

  // Replace with the IP of your FastAPI backend!
  final String _baseUrl = '192.168.1.10:5000'; // Or whatever your IP is

  WebSocketChannel? _channel;
  late final ApiService api;

  final ValueNotifier<bool> isConnected = ValueNotifier(false);
  
  // Expose parsed tremor/metrics to the app (like SessionService)
  final ValueNotifier<Map<String, dynamic>?> tremorDataStream = ValueNotifier(null);

  void initialize() {
    api = ApiService(baseUrl: 'http://$_baseUrl');
    _connectWebSocket();
  }

  void _connectWebSocket() {
    try {
      final wsUrl = Uri.parse('ws://$_baseUrl/ws/live');
      debugPrint('[ApiWebSocketService] Connecting to $wsUrl');
      
      _channel = WebSocketChannel.connect(wsUrl);
      isConnected.value = true;

      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            if (data['type'] == 'tremor_update') {
              tremorDataStream.value = data['data'];
            }
          } catch (e) {
            debugPrint('[ApiWebSocketService] Parse error: $e');
          }
        },
        onDone: () {
          debugPrint('[ApiWebSocketService] Disconnected');
          isConnected.value = false;
          // Reconnect logic
          Future.delayed(const Duration(seconds: 3), _connectWebSocket);
        },
        onError: (error) {
          debugPrint('[ApiWebSocketService] Error: $error');
          isConnected.value = false;
        },
      );
    } catch (e) {
      debugPrint('[ApiWebSocketService] Connection failed: $e');
      isConnected.value = false;
    }
  }

  void disconnect() {
    _channel?.sink.close();
    isConnected.value = false;
  }
}
