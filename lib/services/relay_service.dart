import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class RelayService {
  WebSocketChannel? _channel;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _events.stream;
  bool get isOpen => _channel != null;

  Future<void> connect(String url) async {
    await disconnect();
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !['ws', 'wss'].contains(uri.scheme)) {
      throw const FormatException('Use a valid ws:// or wss:// relay URL.');
    }
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;
    await channel.ready.timeout(const Duration(seconds: 8));
    channel.stream.listen((value) {
      try {
        final decoded = jsonDecode(value as String);
        if (decoded is Map<String, dynamic>) _events.add(decoded);
      } catch (_) {
        _events.add({'type': 'error', 'message': 'Received an unreadable relay message.'});
      }
    }, onError: (Object error) {
      _events.add({'type': 'error', 'message': 'Relay connection failed: $error'});
      _channel = null;
    }, onDone: () {
      _events.add({'type': 'disconnected'});
      _channel = null;
    });
  }

  void send(Map<String, dynamic> message) {
    final channel = _channel;
    if (channel == null) throw StateError('Not connected to the relay.');
    channel.sink.add(jsonEncode(message));
  }

  Future<void> disconnect() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      try { channel.sink.add(jsonEncode({'type': 'leave'})); } catch (_) {}
      await channel.sink.close();
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
  }
}
