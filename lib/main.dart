import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/setup_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("Firebase init failed or already initialized");
  }
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? spreadsheetId = prefs.getString('spreadsheetId');
  runApp(OrderDashboardApp(initialSpreadsheetId: spreadsheetId));
}

class OrderDashboardApp extends StatelessWidget {
  final String? initialSpreadsheetId;

  const OrderDashboardApp({super.key, this.initialSpreadsheetId});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Order Tracker',
      debugShowCheckedModeBanner: false,
      // Enforce Arabic RTL layout globally
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ar', 'AE'), // Arabic
      ],
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        primaryColor: const Color(0xFF10B981), // Emerald Green
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF10B981),
          primary: const Color(0xFF10B981),
        ),
        textTheme: GoogleFonts.cairoTextTheme(Theme.of(context).textTheme),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
      ),
      home: initialSpreadsheetId != null && initialSpreadsheetId!.isNotEmpty 
            ? HomeScreen(spreadsheetId: initialSpreadsheetId!) 
            : const SetupScreen(),
    );
  }
}

