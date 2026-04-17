import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'google_auth_client.dart';

class GoogleAuthService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      sheets.SheetsApi.spreadsheetsScope, // Request permission to read/write spreadsheets
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
    await _googleSignIn.disconnect();
  }

  static Future<sheets.SheetsApi?> getSheetsApi() async {
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
}
