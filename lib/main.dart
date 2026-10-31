import 'package:flutter/material.dart';
import 'screens/dashboard_screen.dart';

void main() => runApp(const QRSenderApp());

class QRSenderApp extends StatelessWidget {
  const QRSenderApp({super.key});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF17251F);
    return MaterialApp(
      title: 'QR Sender',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7F3),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2D7554), brightness: Brightness.light),
        fontFamily: 'Arial',
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: ink, letterSpacing: -1.2),
          headlineMedium: TextStyle(fontSize: 25, fontWeight: FontWeight.w700, color: ink, letterSpacing: -.6),
          titleLarge: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: ink),
          bodyLarge: TextStyle(fontSize: 15, color: Color(0xFF52615A), height: 1.5),
          bodyMedium: TextStyle(fontSize: 13, color: Color(0xFF68766F), height: 1.45),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: const Color(0xFFF5F7F5),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE7ECE8))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF2D7554), width: 1.5)),
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}
