import 'package:flutter/material.dart';
import 'package:robotics_project/view.dart';

void main() {
  runApp(const MyApp());
}
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DroneControlApp();
  }
}
