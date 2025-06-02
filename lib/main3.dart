import 'dart:math';
import 'package:firebasertc/signaling.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';


void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebRTC WS',
      home: Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late Signaling signaling;
  List<String> users = [];
  final selfId = 'user${Random().nextInt(9999)}';

  @override
  void initState() {
    super.initState();
    signaling =
        Signaling('ws://falcon-sweet-physically.ngrok-free.app/ws', selfId,);
    signaling.onUserList = (list) {
      setState(() => users = list.where((e) => e != selfId).toList());
    };
    signaling.connect();
  }

  @override
  Widget build(BuildContext ctx) => Scaffold(
        appBar: AppBar(title: Text('Me: $selfId')),
        body: ListView(
          children: users
              .map((u) => ListTile(
                    title: Text(u),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CallPage(
                            signaling: signaling, peerId: u, isCaller: true,),
                      ),
                    ),
                  ),)
              .toList(),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// CallPage: same widget used by caller & callee
class CallPage extends StatefulWidget {
  final Signaling signaling;
  final String peerId;
  final bool isCaller;
  const CallPage(
      {super.key,
      required this.signaling,
      required this.peerId,
      required this.isCaller});
  @override
  _CallPageState createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  RTCPeerConnection? pc;
  MediaStream? localStream;
  final _localRend = RTCVideoRenderer(), _remoteRend = RTCVideoRenderer();
  final _cached = <RTCIceCandidate>[];
  bool _remoteDescSet = false;

  @override
  void initState() {
    super.initState();
    _localRend.initialize();
    _remoteRend.initialize();
    _setup();
  }

  Future<void> _setup() async {
    localStream = await navigator.mediaDevices
        .getUserMedia({'video': true, 'audio': true});
    _localRend.srcObject = localStream;

    pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'}
      ]
    });

    for (var t in localStream!.getTracks()) {
      pc!.addTrack(t, localStream!);
    }

    pc!.onIceCandidate = (c) {
      if (c.candidate == null) return;
      if (_remoteDescSet) {
        widget.signaling.sendCandidate(widget.peerId, c);
      } else {
        _cached.add(c);
      }
    };

    pc!.onTrack = (e) {
      if (e.streams.isNotEmpty)
        setState(() => _remoteRend.srcObject = e.streams[0]);
    };

    // register inbound handlers
    widget.signaling
      ..on('offer', _onOffer)
      ..on('answer', _onAnswer)
      ..on('candidate', _onCandidate);

    if (widget.isCaller) {
      final offer = await pc!.createOffer();
      await pc!.setLocalDescription(offer);
      widget.signaling.sendOffer(widget.peerId, offer);
    }
  }

  // ── inbound handlers ─────────────────────────────────────────────────────────
  Future<void> _onOffer(Map<String, dynamic> msg) async {
    if (widget.isCaller) return; // ignore
    final desc = RTCSessionDescription(msg['data']['sdp'], msg['data']['type']);
    await pc!.setRemoteDescription(desc);
    final answer = await pc!.createAnswer();
    await pc!.setLocalDescription(answer);
    widget.signaling.sendAnswer(widget.peerId, answer);
    _flushCached();
  }

  Future<void> _onAnswer(Map<String, dynamic> msg) async {
    if (!widget.isCaller) return;
    final desc = RTCSessionDescription(msg['data']['sdp'], msg['data']['type']);
    await pc!.setRemoteDescription(desc);
    _remoteDescSet = true;
    _flushCached();
  }

  Future<void> _onCandidate(Map<String, dynamic> msg) async {
    final d = msg['data'];
    await pc?.addCandidate(
        RTCIceCandidate(d['candidate'], d['sdpMid'], d['sdpMLineIndex']));
  }

  // send cached ICE collected before remote description
  void _flushCached() {
    for (var c in _cached) widget.signaling.sendCandidate(widget.peerId, c);
    _cached.clear();
  }

  // ── UI ──────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext ctx) => Scaffold(
        appBar: AppBar(title: Text('Call with ${widget.peerId}')),
        body: Column(children: [
          Expanded(child: RTCVideoView(_localRend, mirror: true)),
          Expanded(child: RTCVideoView(_remoteRend)),
        ]),
      );

  @override
  void dispose() {
    _localRend.dispose();
    _remoteRend.dispose();
    localStream?.dispose();
    pc?.close();
    super.dispose();
  }
}

