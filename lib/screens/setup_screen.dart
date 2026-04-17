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
  final TextEditingController _ecotrackController = TextEditingController();
  final TextEditingController _yalidineController = TextEditingController();
  bool _isLoading = false;
  GoogleSignInAccount? _user;
  
  // Step tracking: 1 = Google Sign-in, 2 = Google Sheet URL, 3 = EcoTrack API
  int _setupStep = 1;

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    final user = await GoogleAuthService.signIn();
    setState(() {
      _user = user;
      _isLoading = false;
      if (user != null) {
        _setupStep = 2; // Move to Sheet URL step
      }
    });

    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل تسجيل الدخول أو تم الإلغاء', textAlign: TextAlign.right), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveSheetUrl() async {
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

    // Extract the Spreadsheet ID to validate
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

    setState(() => _setupStep = 3); // Move to EcoTrack API step
  }

  Future<void> _saveEcoTrackAndComplete() async {
    final ecotrackToken = _ecotrackController.text.trim();
    final yalidineToken = _yalidineController.text.trim();

    if (ecotrackToken.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء إدخال رمز EcoTrack API', textAlign: TextAlign.right),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final url = _urlController.text.trim();
    final RegExp regExp = RegExp(r"spreadsheets/d/([a-zA-Z0-9-_]+)");
    final match = regExp.firstMatch(url);
    final sheetId = match!.group(1)!;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('spreadsheetId', sheetId);
    await prefs.setString('ecotrack_token', ecotrackToken);
    
    if (yalidineToken.isNotEmpty) {
      await prefs.setString('yalidine_token', yalidineToken);
    }

    setState(() => _isLoading = false);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen(spreadsheetId: sheetId)),
      );
    }
  }

  void _goBackToSheetStep() {
    setState(() => _setupStep = 2);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _ecotrackController.dispose();
    _yalidineController.dispose();
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
              // Step Indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildStepIndicator(1, _setupStep),
                  Container(width: 30, height: 2, color: _setupStep >= 2 ? const Color(0xFF10B981) : Colors.grey.shade300),
                  _buildStepIndicator(2, _setupStep),
                  Container(width: 30, height: 2, color: _setupStep >= 3 ? const Color(0xFF10B981) : Colors.grey.shade300),
                  _buildStepIndicator(3, _setupStep),
                ],
              ),
              const SizedBox(height: 40),

              // Step 1: Google Sign-in
              if (_setupStep == 1) ...[
                const Icon(Icons.table_chart_rounded, size: 80, color: Color(0xFF10B981)),
                const SizedBox(height: 24),
                const Text(
                  'تسجيل الدخول',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'سجل الدخول باستخدام حساب Google الخاص بك (الذي يملك صلاحية التعديل على الجدول).',
                  style: TextStyle(fontSize: 16, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
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
                        ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 3))
                        : const Text('تسجيل الدخول باستخدام Google', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                )
              ],

              // Step 2: Google Sheet URL
              if (_setupStep == 2) ...[
                const Icon(Icons.table_chart_rounded, size: 80, color: Color(0xFF10B981)),
                const SizedBox(height: 24),
                Text(
                  'مرحباً: ${_user!.email} ✅',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                const Text(
                  'خطوة 2: رابط Google Sheet',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'أدخل رابط جدول Google الذي يحتوي على بيانات الطلبات.',
                  style: TextStyle(fontSize: 16, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    labelText: 'رابط Google Sheet',
                    labelStyle: const TextStyle(color: Colors.grey),
                    hintText: 'https://docs.google.com/spreadsheets/d/...',
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
                    onPressed: _isLoading ? null : _saveSheetUrl,
                    child: const Text('التالي', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                )
              ],

              // Step 3: EcoTrack API Token
              if (_setupStep == 3) ...[
                const Icon(Icons.local_shipping, size: 80, color: Color(0xFF10B981)),
                const SizedBox(height: 24),
                const Text(
                  'خطوة 3: رمز EcoTrack API',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'أدخل رمز EcoTrack API الخاص بك لتفعيل خدمة التسليم المباشرة.\nهذا مطلوب لشحن الطلبات.',
                  style: TextStyle(fontSize: 16, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _ecotrackController,
                  decoration: InputDecoration(
                    labelText: 'رمز EcoTrack API',
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
                const SizedBox(height: 16),
                const Text(
                  'خيارات إضافية (اختياري)',
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
                    onPressed: _isLoading ? null : _saveEcoTrackAndComplete,
                    child: _isLoading 
                        ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                        : const Text('إكمال الإعداد', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _goBackToSheetStep,
                  child: const Text('رجوع', style: TextStyle(color: Colors.grey, fontSize: 14)),
                )
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator(int step, int currentStep) {
    bool isActive = step <= currentStep;
    return CircleAvatar(
      radius: 20,
      backgroundColor: isActive ? const Color(0xFF10B981) : Colors.grey.shade300,
      child: Text(
        step.toString(),
        style: TextStyle(
          color: isActive ? Colors.white : Colors.grey,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }
}
