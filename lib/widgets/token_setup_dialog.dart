import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shipping_provider.dart';

/// Dialog to enter or update API token for a shipping provider
class TokenSetupDialog extends StatefulWidget {
  final ShippingProvider provider;
  final VoidCallback onTokenSaved;

  const TokenSetupDialog({
    super.key,
    required this.provider,
    required this.onTokenSaved,
  });

  @override
  State<TokenSetupDialog> createState() => _TokenSetupDialogState();
}

class _TokenSetupDialogState extends State<TokenSetupDialog> {
  late TextEditingController _tokenController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _saveToken() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء إدخال الرمز', textAlign: TextAlign.right),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final tokenKey = _getTokenKey(widget.provider);
      await prefs.setString(tokenKey, token);

      if (mounted) {
        Navigator.pop(context);
        widget.onTokenSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: $e', textAlign: TextAlign.right),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getTokenKey(ShippingProvider provider) {
    return 'provider_token_${provider.id}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('إدخال رمز ${widget.provider.displayName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'يجب إدخال رمز API للمتابعة',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tokenController,
              decoration: InputDecoration(
                labelText: 'رمز API',
                labelStyle: const TextStyle(color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Color(0xFF10B981), width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              obscureText: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _saveToken,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                )
              : const Text('حفظ'),
        ),
      ],
    );
  }
}

class TokenStatusDialog extends StatefulWidget {
  const TokenStatusDialog({super.key});

  @override
  State<TokenStatusDialog> createState() => _TokenStatusDialogState();
}

class _TokenStatusDialogState extends State<TokenStatusDialog> {
  final List<ShippingProvider> _providers = ShippingProvider.values;
  Map<String, bool> _statusByProviderId = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTokenStatuses();
  }

  String _getTokenKey(ShippingProvider provider) {
    return 'provider_token_${provider.id}';
  }

  Future<void> _loadTokenStatuses() async {
    final prefs = await SharedPreferences.getInstance();
    final statuses = <String, bool>{};

    for (final provider in _providers) {
      final tokenKey = _getTokenKey(provider);
      final token = prefs.getString(tokenKey);
      statuses[provider.id] = token != null && token.trim().isNotEmpty;
    }

    if (!mounted) return;
    setState(() {
      _statusByProviderId = statuses;
      _isLoading = false;
    });
  }

  Future<void> _openTokenSetup(ShippingProvider provider) async {
    await showDialog(
      context: context,
      builder: (context) => TokenSetupDialog(
        provider: provider,
        onTokenSaved: () {},
      ),
    );

    if (!mounted) return;
    await _loadTokenStatuses();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إعداد رموز API', textAlign: TextAlign.right),
      content: SizedBox(
        width: double.maxFinite,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    'يمكنك ضبط رمز API لكل مزود بشكل مستقل.',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.right,
                  ),
                  const SizedBox(height: 12),
                  ..._providers.map((provider) {
                    final isSet = _statusByProviderId[provider.id] ?? false;
                    final statusText = isSet ? 'الرمز محفوظ' : 'غير مضبوط';
                    final statusColor = isSet ? const Color(0xFF10B981) : Colors.red;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    provider.displayName,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    statusText,
                                    style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: () => _openTokenSetup(provider),
                                  child: Text(isSet ? 'تعديل' : 'تعيين'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              provider.integrationType.toUpperCase(),
                              style: TextStyle(color: Colors.grey[600], fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
      ],
    );
  }
}
