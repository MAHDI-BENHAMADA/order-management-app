import 'dart:convert';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class UpdateService {
  static const String _githubApiUrl = 'https://api.github.com/repos/MAHDI-BENHAMADA/order-management-app/releases/latest';

  /// Returns the latest version string (e.g., '1.1.0') if an update is available,
  /// otherwise returns null.
  static Future<String?> checkForUpdate() async {
    // Update prompts are only relevant for the Android app.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }

    try {
      final response = await http.get(Uri.parse(_githubApiUrl));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final tagName = data['tag_name'] as String?;
        
        if (tagName != null) {
          // Remove 'v' prefix if it exists
          final latestVersion = tagName.startsWith('v') ? tagName.substring(1) : tagName;
          
          final packageInfo = await PackageInfo.fromPlatform();
          final currentVersion = packageInfo.version;

          if (_isUpdateAvailable(currentVersion, latestVersion)) {
            return latestVersion;
          }
        }
      }
    } catch (e) {
      print('Failed to check for updates: $e');
    }
    return null;
  }

  /// Compares two semantic version strings (e.g., '1.0.0' vs '1.1.0')
  /// Returns true if latest > current
  static bool _isUpdateAvailable(String current, String latest) {
    try {
      final currentParts = current.split('.').map(int.parse).toList();
      final latestParts = latest.split('.').map(int.parse).toList();

      for (int i = 0; i < 3; i++) {
        final currentPart = i < currentParts.length ? currentParts[i] : 0;
        final latestPart = i < latestParts.length ? latestParts[i] : 0;

        if (latestPart > currentPart) {
          return true;
        } else if (latestPart < currentPart) {
          return false;
        }
      }
    } catch (e) {
      // If parsing fails, fall back to simple string comparison
      return latest.compareTo(current) > 0;
    }
    return false;
  }
}
