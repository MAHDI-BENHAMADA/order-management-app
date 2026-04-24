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
    return switch (provider.integrationType) {
      'ecotrack' => 'ecotrack_token',
      'yalidine' => 'yalidine_token',
      'yalitec' => 'yalitec_token',
      'procolis' => 'procolis_token',
      _ => 'ecotrack_token',
    };
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
