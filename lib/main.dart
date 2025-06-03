import 'package:flutter/material.dart';
import 'pages/google_map_page.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Maps',
    theme: ThemeData(primarySwatch: Colors.blue),
    home: GoogleMapPage(),
  );
}
