import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebRTCPage extends StatefulWidget {
  const WebRTCPage({super.key});

  @override
  _WebRTCPageState createState() => _WebRTCPageState();
}

class _WebRTCPageState extends State<WebRTCPage> {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _inRoom = false;
  late final WebSocketChannel _socket;
  final String socketUrl = 'ws://falcon-sweet-physically.ngrok-free.app/ws';
  final selfId = 'user${Random().nextInt(9999)}';
  List<String> userList = [];
  late String sender, receiver;
  final List<RTCIceCandidate> _cached = [];
  bool _remoteDescriptionSet = false;

  final Map<String, dynamic> _configuration = {
    'iceServers': [
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ]
  };

  @override
  void initState() {
    super.initState();
    connectToSocket();
    initRenderers();
  }

  Future<void> connectToSocket() async {
    _socket = WebSocketChannel.connect(Uri.parse(socketUrl));
    _socket.stream.listen(_onMessage, onDone: () {});
    _send({'type': 'register', 'from': selfId});
  }

  void _onMessage(dynamic data) {
    final msg = jsonDecode(data);
    print('Received: $msg');
    switch (msg['type']) {
      case 'users':
        setState(() {
          userList = List<String>.from(msg['data']);
        });
        break;
      case 'offer':
        _onOffer(msg);
        break;
      case 'answer':
        _onAnswer(msg);
        break;
      case 'candidate':
        _onCandidate(msg);
        break;
    }
  }

  void sendOffer(String to, RTCSessionDescription offer) {
    _send({
      'type': 'offer',
      'from': selfId,
      'to': to,
      'data': offer.toMap(),
    });
  }

  void sendAnswer(String to, RTCSessionDescription answer) {
    _send({
      'type': 'answer',
      'from': selfId,
      'to': to,
      'data': answer.toMap(),
    });
  }

  void sendCandidate(String to, RTCIceCandidate cand) {
    _send({
      'type': 'candidate',
      'from': selfId,
      'to': to,
      'data': cand.toMap(),
    });
  }

  void _send(Map<String, dynamic> m) {
    _socket.sink.add(jsonEncode(m));
    print('Sent: $m');
  }

  Future<void> _onOffer(Map<String, dynamic> msg) async {
    if (msg['to'] != selfId) return;
    final desc = RTCSessionDescription(msg['data']['sdp'], msg['data']['type']);

    _remoteStream = await createLocalMediaStream('remote');
    _remoteRenderer.srcObject = _remoteStream;

    _peerConnection!.onIceCandidate = (RTCIceCandidate c) {
      if (_remoteDescriptionSet) {
        sendCandidate(msg['from'], c);
      } else {
        _cached.add(c);
      }
    };

    // onTrack for remote media
    _peerConnection!.onTrack = (RTCTrackEvent event) {
      if (event.track.kind == 'audio') {
        _remoteStream?.addTrack(event.track);
      }
      if (event.track.kind == 'video') {
        _remoteRenderer.srcObject = event.streams[0];
      }
    };

    await _peerConnection!.setRemoteDescription(desc);

    _localStream?.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    final answer = await _peerConnection!.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });

    await _peerConnection!.setLocalDescription(answer);
    sendAnswer(msg['from'], answer);

    setState(() {
      _inRoom = true;
      sender = msg['from'];
      receiver = selfId;
    });

    await Future.delayed(Duration(seconds: 1));

    _remoteDescriptionSet = true;
    _flushCached(msg['from']);
  }

  Future<void> _onAnswer(Map<String, dynamic> msg) async {
    if (_inRoom && msg['from'] == receiver && msg['to'] == sender) {
      final desc = RTCSessionDescription(
        msg['data']['sdp'],
        msg['data']['type'],
      );
      await _peerConnection!.setRemoteDescription(desc);
      _remoteDescriptionSet = true;
      _flushCached(msg['from']);
    }
  }

  Future<void> _onCandidate(Map<String, dynamic> msg) async {
    if (_inRoom &&
        ((msg['from'] == receiver && msg['to'] == sender) ||
            (msg['to'] == receiver && msg['from'] == sender))) {
      final d = msg['data'];
      await _peerConnection?.addCandidate(
        RTCIceCandidate(d['candidate'], d['sdpMid'], d['sdpMLineIndex']),
      );
    }
  }

  // send cached ICE collected before remote description
  void _flushCached(String to) {
    for (RTCIceCandidate c in _cached) {
      sendCandidate(to, c);
    }
    _cached.clear();
  }

  Future<void> initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _openUserMedia() async {
    final stream = await navigator.mediaDevices.getUserMedia({
      'video': true,
      'audio': true,
    });

    _localRenderer.srcObject = stream;

    setState(() {
      _localStream = stream;
    });

    _peerConnection = await createPeerConnection(_configuration);
  }

  Future<void> sendCallOffer(String calleeId) async {
    _remoteStream = await createLocalMediaStream('remote');
    _remoteRenderer.srcObject = _remoteStream;

    // Add local stream tracks
    _localStream?.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    // ICE Candidate handler
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (_remoteDescriptionSet) {
        sendCandidate(calleeId, candidate);
      } else {
        _cached.add(candidate);
      }
    };

    // onTrack for remote media
    _peerConnection!.onTrack = (RTCTrackEvent event) {
      if (event.track.kind == 'audio') {
        _remoteStream?.addTrack(event.track);
      }
      if (event.track.kind == 'video') {
        _remoteRenderer.srcObject = event.streams[0];
      }
    };

    // Create offer
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    sendOffer(calleeId, offer);

    setState(() {
      _inRoom = true;
      sender = selfId;
      receiver = calleeId;
    });
  }

  Future<void> _hangUp() async {
    await _localRenderer.dispose();
    await _remoteRenderer.dispose();

    await _localStream?.dispose();
    await _remoteStream?.dispose();

    await _peerConnection?.close();

    setState(() {
      _localStream = null;
      _remoteStream = null;
      _peerConnection = null;
      _inRoom = false;
    });
  }

  @override
  void dispose() {
    _hangUp();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('WebRTC Video Chat')),
      body: Column(
        children: [
          if (!_inRoom) SizedBox(height: 10),
          if (!_inRoom)
            SizedBox(
              height: 150,
              child: ListView(
                children: userList
                    .map((u) => ListTile(
                          title: Text(u),
                          onTap: () {
                            sendCallOffer(u);
                          },
                        ))
                    .toList(),
              ),
            ),
          SizedBox(height: 10),
          Expanded(
            child: Row(
              children: [
                Expanded(child: RTCVideoView(_localRenderer, mirror: true)),
                Expanded(child: RTCVideoView(_remoteRenderer)),
              ],
            ),
          ),
          SizedBox(height: 10),
          Wrap(
            spacing: 10,
            children: [
              ElevatedButton(
                  onPressed: _openUserMedia, child: Text('Open Camera')),
              ElevatedButton(
                  onPressed: _inRoom ? _hangUp : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: Text('Hang Up')),
            ],
          ),
        ],
      ),
    );
  }
}
