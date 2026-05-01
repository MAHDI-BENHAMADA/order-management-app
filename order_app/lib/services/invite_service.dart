import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

class InviteService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Generate a random 6-character alphanumeric code
  static String _generateCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random();
    return String.fromCharCodes(Iterable.generate(
        6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  // Create an invite for a confirmer
  static Future<String> createInvite({
    required String name,
    required String role,
    required String phone,
    required String spreadsheetId,
    required String workspaceName,
  }) async {
    String code;
    bool exists = true;
    
    // Ensure the code is unique
    do {
      code = _generateCode();
      final doc = await _firestore.collection('invites').doc(code).get();
      exists = doc.exists;
    } while (exists);

    await _firestore.collection('invites').doc(code).set({
      'name': name,
      'role': role,
      'phone': phone,
      'spreadsheetId': spreadsheetId,
      'workspaceName': workspaceName,
      'createdAt': FieldValue.serverTimestamp(),
      'isActive': true,
    });

    return code;
  }

  // Validate an invite code and return the data
  static Future<Map<String, dynamic>?> validateInvite(String code) async {
    try {
      final doc = await _firestore.collection('invites').doc(code.toUpperCase()).get();
      if (doc.exists && doc.data()?['isActive'] == true) {
        return doc.data();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Get all invites for a specific spreadsheet
  static Stream<QuerySnapshot> getInvitesForSheet(String spreadsheetId) {
    return _firestore
        .collection('invites')
        .where('spreadsheetId', isEqualTo: spreadsheetId)
        .snapshots();
  }
  
  // Revoke an invite
  static Future<void> revokeInvite(String code) async {
    await _firestore.collection('invites').doc(code).update({'isActive': false});
  }
}
