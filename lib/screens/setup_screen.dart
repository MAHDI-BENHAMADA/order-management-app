import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../utils/google_auth_service.dart';
import 'home_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _yalidineController = TextEditingController();
  final TextEditingController _ecotrackController = TextEditingController();
  bool _isLoading = false;
  GoogleSignInAccount? _user;

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    final user = await GoogleAuthService.signIn();
    setState(() {
      _user = user;
      _isLoading = false;
    });

    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل تسجيل الدخول أو تم الإلغاء', textAlign: TextAlign.right), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || !url.contains('spreadsheets/d/')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء إدخال رابط صحيح لـ Google Sheet', textAlign: TextAlign.right),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Extract the Spreadsheet ID
    final RegExp regExp = RegExp(r"spreadsheets/d/([a-zA-Z0-9-_]+)");
    final match = regExp.firstMatch(url);
    if (match == null || match.groupCount < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لم نتمكن من استخراج معرف Sheet ID!', textAlign: TextAlign.right),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    final sheetId = match.group(1)!;

    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('spreadsheetId', sheetId);
    
    // Save logistics tokens if provided
    if (_yalidineController.text.trim().isNotEmpty) {
      await prefs.setString('yalidine_token', _yalidineController.text.trim());
    }
    if (_ecotrackController.text.trim().isNotEmpty) {
      await prefs.setString('ecotrack_token', _ecotrackController.text.trim());
    }
    
    setState(() => _isLoading = false);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen(spreadsheetId: sheetId)),
      );
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _yalidineController.dispose();
    _ecotrackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إعداد التطبيق', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.table_chart_rounded, size: 80, color: Color(0xFF10B981)),
              const SizedBox(height: 24),
              const Text(
                'الخطوة الأخيرة للربط بجداول Google',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'سجل الدخول باستخدام حساب Google الخاص بك (الذي يملك صلاحية التعديل على الجدول)، ثم ضع رابط الجدول.',
                style: TextStyle(fontSize: 16, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              
              if (_user == null) ...[
                SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.grey)),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.g_mobiledata, size: 30),
                    onPressed: _isLoading ? null : _signInWithGoogle,
                    label: _isLoading 
                        ? const CircularProgressIndicator()
                        : const Text('تسجيل الدخول باستخدام Google', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                )
              ] else ...[
                Text(
                  ' مرحباً: ${_user!.email} ✅',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    labelText: 'رابط Google Sheet (يبدأ بـ https://docs.google.com)',
                    labelStyle: const TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFF10B981), width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  keyboardType: TextInputType.url,
                  textDirection: TextDirection.ltr,
                ),
                const SizedBox(height: 16),
                const Text(
                  'خيارات التسليم (اختياري)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _yalidineController,
                  decoration: InputDecoration(
                    labelText: 'رمز Yalidine API (اختياري)',
                    labelStyle: const TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFF10B981), width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ecotrackController,
                  decoration: InputDecoration(
                    labelText: 'رمز EcoTrack API (اختياري)',
                    labelStyle: const TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFF10B981), width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    onPressed: _isLoading ? null : _saveUrl,
                    child: _isLoading 
                        ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                        : const Text('حفظ وبدء الاستخدام', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
