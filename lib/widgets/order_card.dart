import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/order.dart';

class OrderCard extends StatelessWidget {
  final AppOrder order;
  final Function(String) onStatusChange;

  const OrderCard({
    Key? key,
    required this.order,
    required this.onStatusChange,
  }) : super(key: key);

  Future<void> _callPhone(BuildContext context) async {
    final Uri url = Uri.parse('tel:${order.phone}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر فتح تطبيق الاتصال!', textAlign: TextAlign.right),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      shadowColor: Colors.black12,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // Top Row: Info and Phone Button
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        order.wilaya,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _callPhone(context),
                  icon: const Icon(Icons.phone, color: Color(0xFF10B981)),
                  tooltip: 'اتصال',
                ),
              ],
            ),
            const Divider(height: 24, thickness: 1, color: Color(0xFFEEEEEE)),
            
            // Bottom Row: Status Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatusIcon(
                  icon: Icons.check_circle,
                  color: const Color(0xFF10B981), // Green ✅
                  isActive: order.status == 'confirm',
                  onTap: () => onStatusChange('confirm'),
                ),
                _buildStatusIcon(
                  icon: Icons.cancel,
                  color: Colors.redAccent, // Red ❌
                  isActive: order.status == 'canceled',
                  onTap: () => onStatusChange('canceled'),
                ),
                _buildStatusIcon(
                  icon: Icons.hourglass_empty_rounded,
                  color: Colors.orangeAccent, // Yellow ⏳
                  isActive: order.status == 'no_response',
                  onTap: () => onStatusChange('no_response'),
                ),
                _buildStatusIcon(
                  icon: Icons.upload_rounded,
                  color: const Color(0xFF065F46), // Dark Emerald green 📤
                  isActive: order.status == 'uploaded',
                  onTap: () => onStatusChange('uploaded'), // Triggers move to archive
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon({
    required IconData icon,
    required Color color,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.15) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: isActive ? color : Colors.grey.shade400,
          size: 28,
        ),
      ),
    );
  }
}
