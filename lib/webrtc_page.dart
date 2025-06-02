// ignore_for_file: library_private_types_in_public_api

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class WebRTCPage extends StatefulWidget {
  const WebRTCPage({super.key});

  @override
  _WebRTCPageState createState() => _WebRTCPageState();
}

class _WebRTCPageState extends State<WebRTCPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  String? _roomId;
  bool _inRoom = false;
  bool _gotAnswer = false;

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

    setState(() {
      _localStream = stream;
    });
  }

  Future<void> _createRoom() async {
    _peerConnection = await createPeerConnection(_configuration);
    // _registerPeerConnectionListeners();

    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });

    final offer = await _peerConnection!.createOffer();

    // ice gathering begins

    final roomWithOffer = {
      'offer': {
        'sdp': offer.sdp,
        'type': offer.type,
      }
    };
    final roomRef = await _db.collection('rooms').add(roomWithOffer);
    _roomId = roomRef.id;

    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) async {
      if (kDebugMode) {
        print("@@@@@@@@@@ got my candidate");
      }
      if (_gotAnswer) {
        print("writing it to the database");
        await roomRef.collection('callerCandidates').add(candidate.toMap());
      } else {
        print("storing candidates in queue");
        _queuedCandidates.add(candidate);
      }
    };

    await _peerConnection!.setLocalDescription(offer);

    setState(() => _inRoom = true);

    // Check immediately if the answer already exists
    final snapshot = await roomRef.get();
    final data = snapshot.data();
    if (data != null && data['answer'] != null) {
      final answer = RTCSessionDescription(
        data['answer']['sdp'],
        data['answer']['type'],
      );
      await _peerConnection?.setRemoteDescription(answer);
      _remoteDescriptionSet = true;
      for (final c in _queuedCandidates) {
        await _peerConnection?.addCandidate(c);
      }
      _queuedCandidates.clear();
    }

    // Then listen for future updates
    roomRef.snapshots().listen((snapshot) async {
      final data = snapshot.data();
      if (data != null &&
          _peerConnection?.getRemoteDescription() == null &&
          data['answer'] != null) {
        final answer = RTCSessionDescription(
          data['answer']['sdp'],
          data['answer']['type'],
        );
        if (kDebugMode) {
          print('@@@@@@@@@@@@@ got answer');
        }
        await _peerConnection?.setRemoteDescription(answer);
        _remoteDescriptionSet = true;
        for (final c in _queuedCandidates) {
          await _peerConnection?.addCandidate(c);
        }
        _queuedCandidates.clear();
      }
    });

    _listenForRemoteCandidates(roomRef, 'calleeCandidates');

    _peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        setState(() {
          _remoteRenderer.srcObject = event.streams[0];
        });
      }
    };
  }

  Future<void> _joinRoom(String roomId) async {
    final roomRef = _db.collection('rooms').doc(roomId);
    final roomSnapshot = await roomRef.get();

    if (!roomSnapshot.exists) return;

    _peerConnection = await createPeerConnection(_configuration);
    // _registerPeerConnectionListeners();

    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });

    final data = roomSnapshot.data()!;
    final offer = data['offer'];
    await _peerConnection?.setRemoteDescription(
      RTCSessionDescription(offer['sdp'], offer['type']),
    );

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    await roomRef.update({
      'answer': {
        'sdp': answer.sdp,
        'type': answer.type,
      }
    });
    _roomId = roomId;

    setState(() => _inRoom = true);

    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) async {
      if (kDebugMode) {
        print("@@@@@@@@@@@@@@@@@@@@ writing callee candidates");
      }
      await roomRef.collection('calleeCandidates').add(candidate.toMap());
    };

    _listenForRemoteCandidates(roomRef, 'callerCandidates');

    _peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        setState(() {
          _remoteRenderer.srcObject = event.streams[0];
        });
      }
    };
  }

  bool _remoteDescriptionSet = false;
  final List<RTCIceCandidate> _queuedCandidates = [];

  void _listenForRemoteCandidates(
      DocumentReference roomRef, String collectionName) {
    roomRef.collection(collectionName).snapshots().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          final candidate = RTCIceCandidate(
            data!['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          );

          if (_remoteDescriptionSet) {
            _peerConnection?.addCandidate(candidate);
          } else {
            _queuedCandidates.add(candidate);
          }
        }
      }
    });
  }

  // void _listenForRemoteCandidates(
  //   DocumentReference roomRef,
  //   String collectionName,
  // ) {
  //   roomRef.collection(collectionName).snapshots().listen((snapshot) {
  //     for (var change in snapshot.docChanges) {
  //       if (change.type == DocumentChangeType.added) {
  //         final data = change.doc.data();
  //         _peerConnection?.addCandidate(RTCIceCandidate(
  //           data!['candidate'],
  //           data['sdpMid'],
  //           data['sdpMLineIndex'],
  //         ));
  //       }
  //     }
  //   });
  // }

  Future<void> _hangUp() async {
    await _localRenderer.dispose();
    await _remoteRenderer.dispose();

    await _localStream?.dispose();
    await _remoteStream?.dispose();

    await _peerConnection?.close();

    if (_roomId != null) {
      final roomRef = _db.collection('rooms').doc(_roomId);
      final calleeCandidates =
          await roomRef.collection('calleeCandidates').get();
      for (var doc in calleeCandidates.docs) {
        await doc.reference.delete();
      }
      final callerCandidates =
          await roomRef.collection('callerCandidates').get();
      for (var doc in callerCandidates.docs) {
        await doc.reference.delete();
      }
      await roomRef.delete();
    }

    setState(() {
      _localStream = null;
      _remoteStream = null;
      _peerConnection = null;
      _roomId = null;
      _inRoom = false;
    });
  }

  // void _registerPeerConnectionListeners() {
  //   _peerConnection?.onIceConnectionState = (state) {
  //     print('@@@@@@@@@@@@@@@@@@@@@@@@@@@@ICE connection state: $state');
  //   };
  //   _peerConnection?.onConnectionState = (state) {
  //     print('@@@@@@@@@@@@@@@@@@@@@@@@@@@@Connection state: $state');
  //   };
  //   _peerConnection?.onSignalingState = (state) {
  //     print('@@@@@@@@@@@@@@@@@@@@@@@@@@@@Signaling state: $state');
  //   };
  // }

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
                  onPressed: _inRoom ? null : _createRoom,
                  child: Text('Create Room')),
              ElevatedButton(
                  onPressed: _inRoom
                      ? null
                      : () async {
                          final controller = TextEditingController();
                          final roomId = await showDialog<String>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text('Join Room'),
                              content: TextField(
                                controller: controller,
                                decoration:
                                    InputDecoration(hintText: 'Room ID'),
                              ),
                              actions: [
                                TextButton(
                                  child: Text('Cancel'),
                                  onPressed: () => Navigator.pop(context),
                                ),
                                TextButton(
                                  child: Text('Join'),
                                  onPressed: () =>
                                      Navigator.pop(context, controller.text),
                                ),
                              ],
                            ),
                          );
                          if (roomId != null && roomId.isNotEmpty) {
                            await _joinRoom(roomId);
                          }
                        },
                  child: Text('Join Room')),
              ElevatedButton(
                  onPressed: _inRoom ? _hangUp : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: Text('Hang Up')),
            ],
          ),
          if (_roomId != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text('Current Room ID: $_roomId'),
            ),
        ],
      ),
    );
  }
}
