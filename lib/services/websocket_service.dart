import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:golden_p/services/auth_service.dart';

class WebSocketService {
  static WebSocketService? instance;

  IO.Socket? _socket;
  final StreamController<Map<String, dynamic>> _signalController = StreamController.broadcast();

  WebSocketService() {
    instance = this;
  }
  
  // The NestJS Socket.IO Gateway URL (Local Wi-Fi IP)
  final String _wsUrl = 'http://127.0.0.1:3000/ws/signals';
  
  bool _isConnected = false;
  Timer? _reconnectTimer;

  Stream<Map<String, dynamic>> get signalStream => _signalController.stream;
  bool get isConnected => _isConnected;

  void connect() {
    if (_isConnected) return;
    if (AuthService.currentToken == null) {
      debugPrint('No Auth Token found. Cannot connect to secure WebSocket.');
      return;
    }

    try {
      _socket = IO.io(_wsUrl, IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': AuthService.currentToken}) // Socket.io 3+ approach
          .setExtraHeaders({'authorization': 'Bearer ${AuthService.currentToken}'}) // Socket.io 2 approach
          .build());

      _socket!.onConnect((_) {
        _isConnected = true;
        debugPrint('WebSocket Connected via Socket.IO');
      });

      _socket!.on('signal_update', (data) {
        try {
          if (data != null) {
            _signalController.add(Map<String, dynamic>.from(data));
          }
        } catch (e) {
          debugPrint('WS Parse Error: $e');
        }
      });

      _socket!.onDisconnect((_) {
        debugPrint('WebSocket Disconnected via Socket.IO');
        _handleDisconnect();
      });

      _socket!.connect();
    } catch (e) {
      debugPrint('WS Connection Error: $e');
      _handleDisconnect();
    }
  }

  void submitSignal(Map<String, dynamic> data) {
    if (_isConnected && _socket != null) {
      _socket!.emit('submit_signal', data);
      debugPrint('[WS] Emitted signal: $data');
    } else {
      debugPrint('[WS] Cannot emit signal. Not connected.');
    }
  }

  void _handleDisconnect() {
    if (!_isConnected) return;
    _isConnected = false;
    _socket?.disconnect();
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      connect();
    });
  }

  void disconnect() {
    _isConnected = false;
    _reconnectTimer?.cancel();
    _socket?.disconnect();
    debugPrint('WebSocket Closed Manually');
  }

  void dispose() {
    disconnect();
    _signalController.close();
  }
}
