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

class _StatusSelector extends StatelessWidget {
  final String currentStatus;
  final ValueChanged<String> onSelected;

  const _StatusSelector({
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active.color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active.color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(active.icon, color: active.color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                active.label,
                style: TextStyle(
                  color: active.color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, color: Colors.black54),
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

  const OrderCard({
    super.key,
    required this.order,
    required this.onStatusChange,
    required this.onEdit,
    this.onShip,
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
    final hasTracking =
        order.trackingNumber != null && order.trackingNumber!.isNotEmpty;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      shadowColor: Colors.black12,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(order.name, style: _nameStyle),
                      const SizedBox(height: 4),
                      Text(
                        '${order.wilaya}  •  ${order.phone}',
                        style: _metaStyle,
                      ),
                      if (hasTracking)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'تتبع: ${order.trackingNumber!}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, color: Colors.blueGrey),
                  tooltip: 'تعديل',
                ),
                IconButton(
                  onPressed: () => _callPhone(context),
                  icon: const Icon(Icons.phone, color: Color(0xFF10B981)),
                  tooltip: 'اتصال ونسخ',
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _StatusSelector(
                    currentStatus: order.status,
                    onSelected: onStatusChange,
                  ),
                ),
                if (order.status == 'confirm' && onShip != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: FilledButton.icon(
                      onPressed: onShip,
                      icon: const Icon(Icons.local_shipping, size: 16),
                      label: const Text('شحن'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        backgroundColor: const Color(0xFF0066CC),
                        minimumSize: const Size(0, 40),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
