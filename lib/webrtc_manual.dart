import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRTCPage extends StatefulWidget {
  @override
  _WebRTCPageState createState() => _WebRTCPageState();
}

class _WebRTCPageState extends State<WebRTCPage> {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  String _sdpOffer = '';
  String _sdpAnswer = '';
  List<String> _remoteCandidates = [];

  final Map<String, dynamic> _configuration = {
    'iceServers': [
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ]
  };

  @override
  void initState() {
    super.initState();
    initRenderers();
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
    setState(() => _localStream = stream);
  }

  Future<void> _createOffer() async {
    _peerConnection = await createPeerConnection(_configuration);
    _registerPeerConnectionListeners();

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        setState(() {
          _remoteStream = event.streams[0];
          _remoteRenderer.srcObject = _remoteStream;
        });
      }
    };

    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });

    _peerConnection!.onIceCandidate = (candidate) {
      final candidateJson = {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex
      };
      _remoteCandidates.add(candidateJson.toString());
      setState(() {});
    };

    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    setState(() {
      _sdpOffer = offer.sdp!;
    });
  }

  Future<void> _setRemoteOffer(String sdp) async {
    _peerConnection = await createPeerConnection(_configuration);
    _registerPeerConnectionListeners();

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        setState(() {
          _remoteStream = event.streams[0];
          _remoteRenderer.srcObject = _remoteStream;
        });
      }
    };

    _peerConnection!.onIceCandidate = (candidate) {
      final candidateJson = {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex
      };
      _remoteCandidates.add(candidateJson.toString());
      setState(() {});
    };

    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(sdp, 'offer'),
    );

    RTCSessionDescription answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    setState(() {
      _sdpAnswer = answer.sdp!;
    });
  }

  Future<void> _setRemoteAnswer(String sdp) async {
    await _peerConnection?.setRemoteDescription(
      RTCSessionDescription(sdp, 'answer'),
    );
  }

  Future<void> _addRemoteCandidate(String candidateStr) async {
    final parts = candidateStr
        .replaceAll(RegExp(r"[\{\}]"), '')
        .split(', ')
        .map((e) => e.split(':'))
        .toList();
    final Map<String, String> data = {
      for (var part in parts) part[0].trim(): part[1].trim()
    };

    await _peerConnection?.addCandidate(
      RTCIceCandidate(data['candidate'], data['sdpMid'],
          int.tryParse(data['sdpMLineIndex']!)),
    );
  }

  Future<void> _hangUp() async {
    await _localRenderer.dispose();
    await _remoteRenderer.dispose();
    await _localStream?.dispose();
    await _remoteStream?.dispose();
    await _peerConnection?.close();
    _peerConnection = null;

    setState(() {
      _localStream = null;
      _remoteStream = null;
      _sdpOffer = '';
      _sdpAnswer = '';
      _remoteCandidates.clear();
    });
  }

  void _registerPeerConnectionListeners() {
    _peerConnection?.onIceConnectionState = (state) {
      print('ICE connection state: $state');
    };
    _peerConnection?.onConnectionState = (state) {
      print('Connection state: $state');
    };
    _peerConnection?.onSignalingState = (state) {
      print('Signaling state: $state');
    };
  }

  @override
  void dispose() {
    _hangUp();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Manual WebRTC Signaling')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 200, // or MediaQuery.of(context).size.height * 0.3
                    width: double.infinity,
                    child: RTCVideoView(_localRenderer, mirror: true),
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 200, // or MediaQuery.of(context).size.height * 0.3
                    width: double.infinity,
                    child: RTCVideoView(_remoteRenderer),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Wrap(
              spacing: 10,
              children: [
                ElevatedButton(
                    onPressed: _openUserMedia, child: Text('Open Camera')),
                ElevatedButton(
                    onPressed: _createOffer, child: Text('Create Offer')),
                ElevatedButton(
                    onPressed: () async {
                      final sdp = await _showInputDialog('Paste Offer SDP');
                      if (sdp != null) _setRemoteOffer(sdp);
                    },
                    child: Text('Set Remote Offer')),
                ElevatedButton(
                    onPressed: () async {
                      final sdp = await _showInputDialog('Paste Answer SDP');
                      if (sdp != null) _setRemoteAnswer(sdp);
                    },
                    child: Text('Set Remote Answer')),
                ElevatedButton(
                    onPressed: () async {
                      final candidate =
                          await _showInputDialog('Paste Remote Candidate');
                      if (candidate != null) _addRemoteCandidate(candidate);
                    },
                    child: Text('Add Remote Candidate')),
                ElevatedButton(
                    onPressed: _hangUp,
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: Text('Hang Up')),
              ],
            ),
            SizedBox(height: 12),
            _buildCopyBlock('Offer SDP', _sdpOffer),
            _buildCopyBlock('Answer SDP', _sdpAnswer),
            if (_remoteCandidates.isNotEmpty)
              _buildCopyBlock(
                  'Generated Candidates', _remoteCandidates.join('\n')),
          ],
        ),
      ),
    );
  }

  Widget _buildCopyBlock(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$title:', style: TextStyle(fontWeight: FontWeight.bold)),
        Row(
          children: [
            Expanded(
              child: SelectableText(content, maxLines: 5),
            ),
            IconButton(
              icon: Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: content));
              },
            )
          ],
        ),
        Divider(),
      ],
    );
  }

  Future<String?> _showInputDialog(String label) async {
    final controller = TextEditingController();
    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          maxLines: null,
          decoration: InputDecoration(hintText: label),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: Text('OK')),
        ],
      ),
    );
  }
}
