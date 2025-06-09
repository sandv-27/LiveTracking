import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'pages/google_map_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Maps',
    theme: ThemeData(primarySwatch: Colors.blue),
    home: GoogleMapPage(),
    debugShowCheckedModeBanner: false,
  );
}
