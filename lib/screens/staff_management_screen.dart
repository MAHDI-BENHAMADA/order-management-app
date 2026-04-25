import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/invite_service.dart';

class StaffManagementScreen extends StatefulWidget {
  final String currentSpreadsheetId;
  const StaffManagementScreen({super.key, required this.currentSpreadsheetId});

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String _selectedRole = 'مؤكد طلبات (Confirmer)';
  bool _isGenerating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _generateInvite() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال الاسم ورقم الهاتف')),
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final code = await InviteService.createInvite(
        name: name,
        role: _selectedRole,
        phone: phone,
        spreadsheetId: widget.currentSpreadsheetId,
        workspaceName: 'مساحة العمل الافتراضية',
      );

      if (!mounted) return;

      _nameController.clear();
      _phoneController.clear();

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('تم إنشاء رمز الدعوة', textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('أرسل هذا الرمز للموظف لتسجيل الدخول:'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SelectableText(
                  code,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                    color: Color(0xFF10B981),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم نسخ الرمز')),
                );
              },
              child: const Text('نسخ الرمز'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('موافق'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء إنشاء الدعوة: $e')),
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الموظفين والدعوات'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top side: Create Invite Form
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'إضافة موظف جديد',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم الموظف',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedRole,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'الدور',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.work),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'مؤكد طلبات (Confirmer)',
                        child: Text('مؤكد طلبات (Confirmer)'),
                      ),
                      DropdownMenuItem(
                        value: 'مشرف (Admin)',
                        child: Text('مشرف (Admin)'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedRole = val);
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _isGenerating ? null : _generateInvite,
                      icon: _isGenerating 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.add),
                      label: const Text(
                        'إنشاء رمز دعوة',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom side: Active Invites List
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'الدعوات والموظفين النشطين',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  StreamBuilder<QuerySnapshot>(
                    stream: InviteService.getInvitesForSheet(widget.currentSpreadsheetId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(child: Text('خطأ: ${snapshot.error}'));
                      }

                      final docs = snapshot.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Text(
                              'لا يوجد موظفين حالياً في مساحة العمل هذه.',
                              style: TextStyle(fontSize: 16, color: Colors.grey),
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final data = docs[index].data() as Map<String, dynamic>;
                          final code = docs[index].id;
                          final isActive = data['isActive'] ?? false;
                          
                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isActive ? const Color(0xFF10B981).withValues(alpha: 0.2) : Colors.red.shade100,
                                child: Icon(Icons.person, color: isActive ? const Color(0xFF10B981) : Colors.red),
                              ),
                              title: Text(data['name'] ?? 'بدون اسم', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${data['role']} - ${data['phone']}'),
                                  Text('رمز الدخول: $code', style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 1)),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: isActive 
                                ? IconButton(
                                    icon: const Icon(Icons.block, color: Colors.red),
                                    tooltip: 'إلغاء تنشيط',
                                    onPressed: () => _revokeInvite(code),
                                  )
                                : const Chip(
                                    label: Text('غير نشط', style: TextStyle(fontSize: 12)),
                                    backgroundColor: Colors.white,
                                  ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _revokeInvite(String code) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الإلغاء'),
        content: const Text('هل أنت متأكد من رغبتك في إلغاء تنشيط هذا الموظف؟ لن يتمكن من تسجيل الدخول بعد الآن.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('تراجع'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              InviteService.revokeInvite(code);
              Navigator.pop(context);
            },
            child: const Text('إلغاء تنشيط'),
          ),
        ],
      ),
    );
  }
}
