import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'api_service.dart';

/// Singleton service that manages the WebSocket connection to the FastAPI backend
/// and exposes an [ApiService] for REST calls.
///
/// Uses IOWebSocketChannel for reliable connections on mobile platforms.
class ApiWebSocketService {
  static final ApiWebSocketService _instance = ApiWebSocketService._internal();
  factory ApiWebSocketService() => _instance;
  ApiWebSocketService._internal();

  // ── Configuration ────────────────────────────────────────────────────
  // Change this to your computer's local IP when running the FastAPI backend.
  // Run `ipconfig` (Windows) or `ifconfig` (macOS/Linux) to find it.
  static const String defaultHost = '192.168.1.10';
  static const int defaultPort = 5000;

  String _host = defaultHost;
  int _port = defaultPort;

  String get baseUrl => 'http://$_host:$_port';
  String get wsUrl => 'ws://$_host:$_port/ws/live';

  // ── State ────────────────────────────────────────────────────────────
  WebSocketChannel? _channel;
  late final ApiService api;
  bool _initialized = false;
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;

  final ValueNotifier<bool> isConnected = ValueNotifier(false);
  final ValueNotifier<Map<String, dynamic>?> tremorDataStream = ValueNotifier(null);

  // ── Public API ───────────────────────────────────────────────────────
  void initialize({String? host, int? port}) {
    if (_initialized) return;
    _initialized = true;

    if (host != null) _host = host;
    if (port != null) _port = port;

    api = ApiService(baseUrl: baseUrl);
    _connectWebSocket();
  }

  void disconnect() {
    _shouldReconnect = false;
    _channel?.sink.close();
    isConnected.value = false;
  }

  // ── WebSocket ────────────────────────────────────────────────────────
  void _connectWebSocket() {
    if (!_shouldReconnect) return;

    try {
      final uri = Uri.parse(wsUrl);
      _reconnectAttempts++;
      debugPrint('[WS] Attempt #$_reconnectAttempts → connecting to $uri');

      // Use IOWebSocketChannel for mobile — more reliable than the generic one
      _channel = IOWebSocketChannel.connect(
        uri,
        pingInterval: const Duration(seconds: 15),
      );

      _channel!.stream.listen(
        (message) {
          // Mark as connected on first message
          if (!isConnected.value) {
            isConnected.value = true;
            _reconnectAttempts = 0;
            debugPrint('[WS] Connected and receiving data');
          }

          try {
            final data = jsonDecode(message);
            if (data is Map<String, dynamic> && data['type'] == 'tremor_update') {
              tremorDataStream.value = Map<String, dynamic>.from(data['data']);
            }
          } catch (e) {
            debugPrint('[WS] Parse error: $e');
          }
        },
        onDone: () {
          debugPrint('[WS] Closed');
          isConnected.value = false;
          _scheduleReconnect();
        },
        onError: (error) {
          debugPrint('[WS] Error: $error');
          isConnected.value = false;
          _scheduleReconnect();
        },
      );
    } catch (e) {
      debugPrint('[WS] Connect failed: $e');
      isConnected.value = false;
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect) return;
    // Exponential backoff: 2s, 4s, 8s, max 15s
    final delay = Duration(
        seconds: (_reconnectAttempts * 2).clamp(2, 15));
    debugPrint('[WS] Reconnecting in ${delay.inSeconds}s...');
    Future.delayed(delay, _connectWebSocket);
  }
}
