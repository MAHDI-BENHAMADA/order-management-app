import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/order.dart';

// Extracted const text styles for memory efficiency
const _nameStyle = TextStyle(
  fontSize: 18,
  fontWeight: FontWeight.bold,
  color: Colors.black87,
);

const _wilayaStyle = TextStyle(
  fontSize: 14,
  color: Colors.grey,
);

const _divider = Divider(
  height: 24,
  thickness: 1,
  color: Color(0xFFEEEEEE),
);

const _phoneIcon = Icon(
  Icons.phone,
  color: Color(0xFF10B981),
);

// Const status icon button widget - prevents unnecessary rebuilds
class _StatusIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isActive;
  final VoidCallback onTap;

  const _StatusIconButton({
    required this.icon,
    required this.color,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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

class OrderCard extends StatelessWidget {
  final AppOrder order;
  final Function(String) onStatusChange;
  final VoidCallback onEdit;
  final VoidCallback? onShip;

  const OrderCard({
    Key? key,
    required this.order,
    required this.onStatusChange,
    required this.onEdit,
    this.onShip,
  }) : super(key: key);

  Future<void> _callPhone(BuildContext context) async {
    // Copy phone number to clipboard
    await Clipboard.setData(ClipboardData(text: order.phone));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم نسخ رقم الهاتف بنجاح!', textAlign: TextAlign.right),
          duration: Duration(seconds: 1),
        ),
      );
    }
    
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      shadowColor: Colors.black.withOpacity(0.08),
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
                        style: _nameStyle,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        order.wilaya,
                        style: _wilayaStyle,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit, color: Colors.blueGrey),
                  tooltip: 'تعديل',
                ),
                IconButton(
                  onPressed: () => _callPhone(context),
                  icon: _phoneIcon,
                  tooltip: 'اتصال ونسخ',
                ),
              ],
            ),
            _divider,
            // Bottom Row: Status Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatusIconButton(
                  icon: Icons.check_circle,
                  color: const Color(0xFF10B981),
                  isActive: order.status == 'confirm',
                  onTap: () => onStatusChange('confirm'),
                ),
                _StatusIconButton(
                  icon: Icons.cancel,
                  color: Colors.redAccent,
                  isActive: order.status == 'canceled',
                  onTap: () => onStatusChange('canceled'),
                ),
                _StatusIconButton(
                  icon: Icons.hourglass_empty_rounded,
                  color: Colors.orangeAccent,
                  isActive: order.status == 'no_response',
                  onTap: () => onStatusChange('no_response'),
                ),
                if (order.status == 'confirm' && onShip != null)
                  _StatusIconButton(
                    icon: Icons.local_shipping,
                    color: const Color(0xFF0066cc),
                    isActive: false,
                    onTap: onShip!,
                  ),
                _StatusIconButton(
                  icon: Icons.upload_rounded,
                  color: const Color(0xFF065F46),
                  isActive: order.status == 'uploaded',
                  onTap: () => onStatusChange('uploaded'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}