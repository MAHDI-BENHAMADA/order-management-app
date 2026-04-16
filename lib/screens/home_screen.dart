import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import '../models/order.dart';
import '../widgets/order_card.dart';
import '../utils/google_auth_service.dart';
import 'setup_screen.dart';

class HomeScreen extends StatefulWidget {
  final String spreadsheetId;

  const HomeScreen({Key? key, required this.spreadsheetId}) : super(key: key);

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<AppOrder> allOrders = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    fetchData();
  }

  Future<void> fetchData() async {
    setState(() => isLoading = true);
    try {
      final api = await GoogleAuthService.getSheetsApi();
      if (api == null) {
        _showError('خطأ: لم يتم تسجيل الدخول بصلاحيات كافية.');
        await _logout();
        return;
      }

      // Read columns A to F. Adjust 'Sheet1' to the actual name if it's different.
      final response = await api.spreadsheets.values.get(widget.spreadsheetId, 'A:F');
      final rows = response.values ?? [];
      
      List<dynamic> parsedData = [];
      for (int i = 1; i < rows.length; i++) { // Start at 1 to skip headers
        var r = rows[i];
        // Ensure the row has enough columns (up to name at [2] and phone at [4])
        if (r.length >= 3 && r[2].toString().isNotEmpty) {
          parsedData.add({
            'row': i + 1, // original sheet row number
            'date': r.isNotEmpty ? r[0] : "",
            'time': r.length > 1 ? r[1] : "",
            'name': r.length > 2 ? r[2] : "",
            'wilaya': r.length > 3 ? r[3] : "",
            'phone': r.length > 4 ? r[4] : "",
            'status': r.length > 5 ? r[5] : "جديد",
          });
        }
      }

      setState(() {
        allOrders = AppOrder.processRawData(parsedData);
      });
    } catch (e) {
      _showError('تعذر جلب البيانات: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _logout() async {
    await GoogleAuthService.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('spreadsheetId');
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const SetupScreen()),
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _updateOrderStatus(AppOrder order, String newStatus) async {
    final oldStatus = order.status;
    setState(() {
      order.status = newStatus;
    });

    if (newStatus == 'uploaded') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('جاري النقل والرفع...'),
          duration: Duration(seconds: 1),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    }

    try {
      final api = await GoogleAuthService.getSheetsApi();
      if (api == null) throw Exception('API Call failed, not logged in.');

      final range = 'F${order.row}'; // Column F holds the status
      final valueRange = sheets.ValueRange(values: [[newStatus]]);
      
      await api.spreadsheets.values.update(
        valueRange,
        widget.spreadsheetId,
        range,
        valueInputOption: 'USER_ENTERED',
      );
    } catch (e) {
      // Revert if API fails
      setState(() {
        order.status = oldStatus;
      });
      _showError('خطأ أثناء التحديث! تم التراجع عن التغيير.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentList = allOrders.where((o) => o.status != 'uploaded').toList();
    final archivedOrders = allOrders.where((o) => o.status == 'uploaded').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة تتبع الطلبات', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchData,
            color: const Color(0xFF10B981),
            tooltip: 'تحديث',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            color: Colors.redAccent,
            tooltip: 'تغيير الرابط',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF10B981),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF10B981),
          tabs: const [
            Tab(text: "الطلبات الحالية"),
            Tab(text: "الأرشيف"),
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOrderList(currentList),
                _buildOrderList(archivedOrders),
              ],
            ),
    );
  }

  Widget _buildOrderList(List<AppOrder> orders) {
    if (orders.isEmpty) {
      return const Center(
        child: Text('لا توجد طلبات هنا', style: TextStyle(color: Colors.grey)),
      );
    }

    return RefreshIndicator(
      onRefresh: fetchData,
      color: const Color(0xFF10B981),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final order = orders[index];
          return OrderCard(
            key: ValueKey(order.row),
            order: order,
            onStatusChange: (newStatus) => _updateOrderStatus(order, newStatus),
          );
        },
      ),
    );
  }
}
