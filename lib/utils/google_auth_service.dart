import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'google_auth_client.dart';

class GoogleAuthService {
  static const String _serviceAccountEmailUrl =
      'https://sheets-backend-6aoikb9wv-walidbenxyz-3942s-projects.vercel.app/api/getServiceAccountEmail';

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      sheets.SheetsApi.spreadsheetsScope, // Request permission to read/write spreadsheets
      drive.DriveApi.driveScope, // Full drive scope needed to change permissions of files
    ],
  );

  static Future<GoogleSignInAccount?> signIn() async {
    try {
      return await _googleSignIn.signIn();
    } catch (error) {
      return null;
    }
  }

  static Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    try {
      await _googleSignIn.disconnect();
    } catch (_) {}
  }

  static Future<sheets.SheetsApi?> getSheetsApi() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool isOwner = prefs.getBool('isOwner') ?? true;

    if (!isOwner) return null;

    // Try to get current user, or attempt a silent sign-in if returning to the app
    GoogleSignInAccount? account = _googleSignIn.currentUser;
    if (account == null) {
      try {
        account = await _googleSignIn.signInSilently();
      } catch (e) {
        return null;
      }
    }
    
    if (account == null) return null;

    final authHeaders = await account.authHeaders;
    final client = GoogleAuthClient(authHeaders);
    return sheets.SheetsApi(client);
  }

  static Future<drive.DriveApi?> getDriveApi() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool isOwner = prefs.getBool('isOwner') ?? true;

    if (!isOwner) return null;

    // Try to get current user, or attempt a silent sign-in if returning to the app
    GoogleSignInAccount? account = _googleSignIn.currentUser;
    if (account == null) {
      try {
        account = await _googleSignIn.signInSilently();
      } catch (e) {
        return null;
      }
    }
    
    if (account == null) return null;

    final authHeaders = await account.authHeaders;
    final client = GoogleAuthClient(authHeaders);
    return drive.DriveApi(client);
  }

  static Future<String?> getServiceAccountEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedEmail = prefs.getString('service_account_email');
      if (cachedEmail != null && cachedEmail.isNotEmpty) {
        return cachedEmail;
      }

      final response = await http.get(Uri.parse(_serviceAccountEmailUrl));
      if (response.statusCode != 200) {
        return null;
      }

      final decodedBody = jsonDecode(response.body);
      final serviceAccountEmail = decodedBody['serviceAccountEmail'] as String?;
      if (serviceAccountEmail != null && serviceAccountEmail.isNotEmpty) {
        await prefs.setString('service_account_email', serviceAccountEmail);
      }
      return serviceAccountEmail;
    } catch (e) {
      return null;
    }
  }
}
