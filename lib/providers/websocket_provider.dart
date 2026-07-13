import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/websocket_service.dart';

final websocketServiceProvider = Provider<WebSocketService>((ref) {
  final service = WebSocketService();
  service.connect();
  
  ref.onDispose(() {
    service.dispose();
  });
  
  return service;
});

final websocketSignalStreamProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final wsService = ref.watch(websocketServiceProvider);
  return wsService.signalStream;
});
