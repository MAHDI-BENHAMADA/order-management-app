import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:googleapis/sheets/v4.dart' as sheets;

class StaffSheetsService {
  static const String _sheetsProxyUrl =
      'https://sheets-backend-6aoikb9wv-walidbenxyz-3942s-projects.vercel.app/api/sheetsProxy';

  static Future<sheets.ValueRange> getValues(String spreadsheetId, String range) async {
    final response = await http.post(
      Uri.parse(_sheetsProxyUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'get',
        'spreadsheetId': spreadsheetId,
        'range': range,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to get values: ${response.body}');
    }

    final data = jsonDecode(response.body);
    final values = (data['values'] as List<dynamic>?)
        ?.map((row) => row as List<dynamic>)
        .toList();

    return sheets.ValueRange(values: values ?? []);
  }

  static Future<void> updateValues(
    String spreadsheetId,
    String range,
    sheets.ValueRange valueRange, {
    String valueInputOption = 'USER_ENTERED',
  }) async {
    final response = await http.post(
      Uri.parse(_sheetsProxyUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'update',
        'spreadsheetId': spreadsheetId,
        'range': range,
        'valueInputOption': valueInputOption,
        'resource': valueRange.toJson(),
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update values: ${response.body}');
    }
  }

  static Future<void> batchUpdate(
    String spreadsheetId,
    sheets.BatchUpdateValuesRequest request,
  ) async {
    final response = await http.post(
      Uri.parse(_sheetsProxyUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'batchUpdate',
        'spreadsheetId': spreadsheetId,
        'resource': request.toJson(),
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to batch update: ${response.body}');
    }
  }
}
