/// SocketIO service — connects to the Flask backend.
/// Exposes streams for tremor data and metrics updates.
///
/// To integrate real ESP32 hardware later:
///   No changes needed here. Just update the backend's ESP32Simulator
///   with actual serial/BLE reads — the socket events stay identical.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class SocketService {
  // -----------------------------------------------------------------------
  // Singleton
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  // TODO: change this to your machine's local IP when running on a real device
  static const String _baseUrl = 'http://10.0.2.2:5000'; // Android emulator → localhost

  // -----------------------------------------------------------------------
  // Sockets
  io.Socket? _sensorSocket;
  io.Socket? _sessionSocket;

  // -----------------------------------------------------------------------
  // Stream controllers
  final _tremorCtrl  = StreamController<Map<String, dynamic>>.broadcast();
  final _metricsCtrl = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get tremorStream  => _tremorCtrl.stream;
  Stream<Map<String, dynamic>> get metricsStream => _metricsCtrl.stream;

  bool get isConnected => _sensorSocket?.connected ?? false;

  // -----------------------------------------------------------------------
  void connect() {
    _sensorSocket = io.io(
      '$_baseUrl/sensor',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setPath('/socket.io')
          .setQuery({'EIO': '4'})
          .disableAutoConnect()
          .build(),
    );

    _sessionSocket = io.io(
      '$_baseUrl/session',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setPath('/socket.io')
          .setQuery({'EIO': '4'})
          .disableAutoConnect()
          .build(),
    );

    _sensorSocket!
      ..on('connect', (_) => debugPrint('[SocketService] sensor connected'))
      ..on('disconnect', (_) => debugPrint('[SocketService] sensor disconnected'))
      ..on('tremor_data', (data) {
        if (data is Map) _tremorCtrl.add(Map<String, dynamic>.from(data));
      })
      ..connect();

    _sessionSocket!
      ..on('connect', (_) => debugPrint('[SocketService] session connected'))
      ..on('metrics_update', (data) {
        if (data is Map) _metricsCtrl.add(Map<String, dynamic>.from(data));
      })
      ..connect();
  }

  void disconnect() {
    _sensorSocket?.disconnect();
    _sessionSocket?.disconnect();
  }

  void dispose() {
    _tremorCtrl.close();
    _metricsCtrl.close();
    disconnect();
  }
}
