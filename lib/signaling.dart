import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class Signaling {
  final String serverUrl;
  final String selfId;
  late WebSocketChannel _channel;

  final Map<String, Function(Map<String, dynamic>)> _handlers = {};
  Function(List<String>)? onUserList;
  Function(Map<String, dynamic>)? onOffer;

  Signaling(this.serverUrl, this.selfId);

  void connect() {
    _channel = WebSocketChannel.connect(Uri.parse(serverUrl));
    _channel.stream.listen(_onMessage, onDone: () {});
    _send({'type': 'register', 'from': selfId});
  }

  void _onMessage(dynamic data) {
    final msg = jsonDecode(data);
    print('Received: $msg');
    switch (msg['type']) {
      case 'users':
        onUserList?.call(List<String>.from(msg['data']));
        break;
      case 'offer':
      case 'answer':
      case 'candidate':
        _handlers[msg['type']]?.call(msg);
        break;
    }
  }

  // register callbacks from call page
  void on(String type, Function(Map<String, dynamic>) cb) =>
      _handlers[type] = cb;

  // outbound messages
  void sendOffer(String to, RTCSessionDescription offer) =>
      _send({'type': 'offer', 'from': selfId, 'to': to, 'data': offer.toMap()});

  void sendAnswer(String to, RTCSessionDescription answer) => _send(
      {'type': 'answer', 'from': selfId, 'to': to, 'data': answer.toMap()});

  void sendCandidate(String to, RTCIceCandidate cand) => _send(
      {'type': 'candidate', 'from': selfId, 'to': to, 'data': cand.toMap()});

  void _send(Map<String, dynamic> m) {
    _channel.sink.add(jsonEncode(m));
    print('Sent: $m');
  }
}
