import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/order.dart';

class ProcolisService {
  static const String baseUrl = 'https://zrexpress.com/api';
  static String? _apiToken;

  static void setApiToken(String token) {
    _apiToken = token;
  }

  static Future<String?> createShipment(AppOrder order) async {
    if (_apiToken == null) {
      throw Exception('Procolis API Token not set');
    }

    try {
      final address = order.address.isEmpty 
          ? '${order.wilaya} - المركز' 
          : order.address;

      final payload = {
        'token': _apiToken,
        'name': order.name,
        'phone': order.phone,
        'wilaya': order.wilaya,
        'commune': order.commune.isNotEmpty ? order.commune : 'المركز',
        'address': address,
        'product': order.product.isNotEmpty ? order.product : 'طلب',
        'price': order.price.isNotEmpty ? int.tryParse(order.price) ?? 0 : 0,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/shipment/create'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['tracking_number'] ?? data['id'] ?? data['reference'];
      } else {
        throw Exception('Procolis API Error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Procolis Shipment Error: $e');
    }
  }
}
