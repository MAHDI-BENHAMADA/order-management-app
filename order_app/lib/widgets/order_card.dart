import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/order.dart';

const _nameStyle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w700,
  color: Colors.black87,
);
const _metaStyle = TextStyle(fontSize: 13, color: Colors.black54);

class _StatusOption {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _StatusOption(this.value, this.label, this.icon, this.color);
}

const List<_StatusOption> _statusOptions = [
  _StatusOption('جديد', 'جديد', Icons.fiber_new, Color(0xFF2563EB)),
  _StatusOption('confirm', 'مؤكد', Icons.check_circle, Color(0xFF10B981)),
  _StatusOption(
    'no_response',
    'لا إجابة',
    Icons.hourglass_empty_rounded,
    Colors.orange,
  ),
  _StatusOption('canceled', 'ملغى', Icons.cancel, Colors.redAccent),
  _StatusOption('uploaded', 'أرشيف', Icons.upload_rounded, Color(0xFF065F46)),
];

_StatusOption _statusFor(String status) {
  return _statusOptions.firstWhere(
    (item) => item.value == status,
    orElse: () =>
        const _StatusOption('جديد', 'جديد', Icons.fiber_new, Color(0xFF2563EB)),
  );
}

class StatusSelector extends StatelessWidget {
  final String currentStatus;
  final ValueChanged<String> onSelected;

  const StatusSelector({
    required this.currentStatus,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final active = _statusFor(currentStatus);

    return PopupMenuButton<String>(
      onSelected: onSelected,
      itemBuilder: (context) {
        return _statusOptions
            .map(
              (option) => PopupMenuItem<String>(
                value: option.value,
                child: Row(
                  children: [
                    Icon(option.icon, color: option.color, size: 18),
                    const SizedBox(width: 8),
                    Text(option.label),
                  ],
                ),
              ),
            )
            .toList();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: active.color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active.color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min, // Wrap content tightly
          children: [
            Icon(active.icon, color: active.color, size: 16),
            const SizedBox(width: 6),
            Text(
              active.label,
              style: TextStyle(
                color: active.color,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, color: Colors.black54, size: 16),
          ],
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
  final Widget? totalPriceWidget; // Widget to display total price (base + shipping)
  
  const OrderCard({
    super.key,
    required this.order,
    required this.onStatusChange,
    required this.onEdit,
    this.onShip,
    this.totalPriceWidget,
  });

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
            content: Text(
              'تعذر فتح تطبيق الاتصال!',
              textAlign: TextAlign.right,
            ),
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
    final hasTracking = order.trackingNumber != null && order.trackingNumber!.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 1,
      shadowColor: Colors.black12,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Name and Status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    order.name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                StatusSelector(
                  currentStatus: order.status,
                  onSelected: onStatusChange,
                ),
              ],
            ),
            const SizedBox(height: 4),

            // Middle Row: Phone & Wilaya
            Row(
              children: [
                const Icon(Icons.phone_android, size: 13, color: Colors.black54),
                const SizedBox(width: 4),
                Text(
                  order.phone,
                  style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w500),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text('•', style: TextStyle(color: Colors.black38)),
                ),
                const Icon(Icons.location_on_outlined, size: 13, color: Colors.black54),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    order.wilaya,
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // Middle Row 2: Product & Price
            if (order.product.isNotEmpty || totalPriceWidget != null || order.price.isNotEmpty)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.shopping_bag_outlined, size: 13, color: Colors.black54),
                  const SizedBox(width: 4),
                  if (order.product.isNotEmpty)
                    Flexible(
                      child: Text(
                        order.product,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (order.product.isNotEmpty && (totalPriceWidget != null || int.tryParse(order.price.trim()) != null))
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Text('•', style: TextStyle(color: Colors.black38)),
                    ),
                  if (totalPriceWidget != null)
                    totalPriceWidget!
                  else if (int.tryParse(order.price.trim()) != null)
                    Text(
                      '${order.price} د.ج',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                    ),
                ],
              ),
            
            if (hasTracking)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(Icons.local_shipping_outlined, size: 13, color: Colors.black54),
                    const SizedBox(width: 4),
                    Text(
                      'تتبع: ${order.trackingNumber!}',
                      style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 8),
            const Divider(height: 1, thickness: 0.5),
            const SizedBox(height: 8),

            // Bottom Row: Actions
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      _buildActionBtn(context, Icons.phone, 'اتصال', const Color(0xFF10B981), () => _callPhone(context)),
                      const SizedBox(width: 8),
                      _buildActionBtn(context, Icons.edit_outlined, 'تعديل', Colors.blueGrey, onEdit),
                    ],
                  ),
                ),
                if (order.status == 'confirm' && onShip != null)
                  FilledButton.icon(
                    onPressed: onShip,
                    icon: const Icon(Icons.local_shipping, size: 14),
                    label: const Text('شحن', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      backgroundColor: const Color(0xFF0066CC),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBtn(BuildContext context, IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
