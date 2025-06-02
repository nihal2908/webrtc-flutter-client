import 'package:firebase_core/firebase_core.dart';
import 'package:firebasertc/self_socket.dart';
// import 'package:firebasertc/webrtc_page.dart';
import 'package:flutter/material.dart';

// import 'package:firebasertc/webrtc_manual.dart';
// import 'package:firebasertc/chat_gpt.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: WebRTCPage(),
      // home: WebRTCPage(),
    );
  }
}
