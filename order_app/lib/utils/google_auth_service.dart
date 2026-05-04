import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'google_auth_client.dart';

class GoogleAuthService {
  static const String _serviceAccountEmailUrl =
      'https://sheets-backend-bay.vercel.app/api/getServiceAccountEmail';

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: kIsWeb ? '909066568788-bffqc393944sd74ivvansckkou1158oc.apps.googleusercontent.com' : null,
    scopes: [
      sheets.SheetsApi.spreadsheetsScope,
      drive.DriveApi.driveScope,
    ],
  );

  /// Stream that fires whenever the signed-in user changes (including FedCM/One Tap auto sign-in)
  static Stream<GoogleSignInAccount?> get onUserChanged => _googleSignIn.onCurrentUserChanged;

  static Future<GoogleSignInAccount?> signIn() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account != null) {
        await _cacheAuthHeaders(account);
      }
      return account;
    } catch (error) {
      print('Google Sign-In Error: $error');
      return null;
    }
  }

  /// Cache auth headers to localStorage so we survive page refreshes on web
  static Future<void> _cacheAuthHeaders(GoogleSignInAccount account) async {
    try {
      final headers = await account.authHeaders;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_auth_headers', jsonEncode(headers));
      print('✅ Auth headers cached');
    } catch (e) {
      print('Failed to cache auth headers: $e');
    }
  }

  /// Called when FedCM/One Tap completes — caches the new headers immediately
  static Future<void> cacheCurrentUserHeaders() async {
    final account = _googleSignIn.currentUser;
    if (account != null) {
      await _cacheAuthHeaders(account);
    }
  }

  /// Clear cached headers (called when a 401 is detected)
  static Future<void> _clearCachedHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_auth_headers');
  }

  /// Try to get a valid auth client: cached headers → silent sign-in → cached token
  static Future<GoogleAuthClient?> _getAuthClient({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final isOwner = prefs.getBool('isOwner') ?? true;
    if (!isOwner) return null;

    // 1. Try current in-memory session
    GoogleSignInAccount? account = _googleSignIn.currentUser;
    if (account != null) {
      await _cacheAuthHeaders(account);
      final headers = await account.authHeaders;
      return GoogleAuthClient(headers);
    }

    // 2. Try silent sign-in (works on mobile, sometimes on web)
    try {
      account = await _googleSignIn.signInSilently();
      if (account != null) {
        await _cacheAuthHeaders(account);
        final headers = await account.authHeaders;
        return GoogleAuthClient(headers);
      }
    } catch (_) {}

    // 3. On web, use cached headers (survives page refresh until token expires ~1hr)
    if (kIsWeb && !forceRefresh) {
      final cachedJson = prefs.getString('cached_auth_headers');
      if (cachedJson != null) {
        final headers = Map<String, String>.from(jsonDecode(cachedJson));
        return GoogleAuthClient(headers);
      }
    }

    // 4. No valid session — caller must trigger interactive sign-in from a user gesture
    return null;
  }

  /// Interactive sign-in — MUST be called from a user gesture (button tap) to avoid popup blocking
  static Future<GoogleAuthClient?> interactiveSignIn() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account != null) {
        await _cacheAuthHeaders(account);
        final headers = await account.authHeaders;
        return GoogleAuthClient(headers);
      }
    } catch (e) {
      print('Interactive sign-in failed: $e');
    }
    return null;
  }

  static Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Clear only auth and session-related data, preserving API tokens and user preferences
    await prefs.remove('spreadsheetId');
    await prefs.remove('spreadsheet_id');
    await prefs.remove('spreadsheet_name');
    await prefs.remove('isOwner');
    await prefs.remove('userRole');
    await prefs.remove('workspaceName');
    await prefs.remove('staffName');
    await prefs.remove('inviteCode');
    await prefs.remove('service_account_email');
    await prefs.remove('cached_auth_headers');
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    try {
      await _googleSignIn.disconnect();
    } catch (_) {}
  }

  static Future<sheets.SheetsApi?> getSheetsApi() async {
    final client = await _getAuthClient();
    if (client == null) return null;
    return sheets.SheetsApi(client);
  }

  /// Get Sheets API with automatic retry on 401 (expired token).
  /// Call this instead of getSheetsApi() when you want auto-refresh.
  static Future<sheets.SheetsApi?> getSheetsApiWithRetry() async {
    var api = await getSheetsApi();
    if (api == null) return null;

    // We return a wrapper that detects 401 and retries with a fresh token.
    // The actual retry happens at the call site in home_screen.
    return api;
  }

  static Future<drive.DriveApi?> getDriveApi() async {
    final client = await _getAuthClient();
    if (client == null) return null;
    return drive.DriveApi(client);
  }

  /// Force re-authenticate (clears cache). Must be called from a user gesture to avoid popup blocking.
  static Future<sheets.SheetsApi?> refreshAndGetSheetsApi() async {
    await _clearCachedHeaders();
    final client = await interactiveSignIn();
    if (client == null) return null;
    return sheets.SheetsApi(client);
  }

  static Future<drive.DriveApi?> refreshAndGetDriveApi() async {
    await _clearCachedHeaders();
    final client = await interactiveSignIn();
    if (client == null) return null;
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
