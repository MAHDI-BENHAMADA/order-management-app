import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/order.dart';

class YalitecService {
  static const String baseUrl = 'https://api.yalitec.me';
  static String? _apiToken;

  static void setApiToken(String token) {
    _apiToken = token;
  }

  static Future<String?> createShipment(AppOrder order) async {
    if (_apiToken == null) {
      throw Exception('Yalitec API Token not set');
    }

    try {
      final address = order.address.isEmpty 
          ? '${order.wilaya} - المركز' 
          : order.address;

      final payload = {
        'username': _apiToken,
        'name': order.name,
        'phone': order.phone,
        'wilaya': order.wilaya,
        'commune': order.commune.isNotEmpty ? order.commune : 'المركز',
        'address': address,
        'product': order.product.isNotEmpty ? order.product : 'طلب',
        'price': order.price.isNotEmpty ? int.tryParse(order.price) ?? 0 : 0,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/shipment/add'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['tracking_number'] ?? data['id'];
      } else {
        throw Exception('Yalitec API Error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Yalitec Shipment Error: $e');
    }
  }
}
