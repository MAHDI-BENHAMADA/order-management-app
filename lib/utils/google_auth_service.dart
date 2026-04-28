import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'google_auth_client.dart';

class GoogleAuthService {
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

  static Future<AutoRefreshingAuthClient?> _getServiceAccountClient() async {
    try {
      final jsonString = await rootBundle.loadString('assets/service_account.json');
      final credentials = ServiceAccountCredentials.fromJson(jsonDecode(jsonString));
      
      final client = await clientViaServiceAccount(credentials, [
        sheets.SheetsApi.spreadsheetsScope,
        drive.DriveApi.driveReadonlyScope,
      ]);
      return client;
    } catch (e) {
      return null;
    }
  }

  static Future<sheets.SheetsApi?> getSheetsApi() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool isOwner = prefs.getBool('isOwner') ?? true;

    if (!isOwner) {
      final client = await _getServiceAccountClient();
      if (client != null) {
        return sheets.SheetsApi(client);
      }
      return null;
    }

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

    if (!isOwner) {
      final client = await _getServiceAccountClient();
      if (client != null) {
        return drive.DriveApi(client);
      }
      return null;
    }

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
}
