class AppOrder {
  final int row;
  final String date;
  final String time;
  final String name;
  final String wilaya;
  final String phone;
  String status; // Mutable for local state changes

  AppOrder({
    required this.row,
    required this.date,
    required this.time,
    required this.name,
    required this.wilaya,
    required this.phone,
    required this.status,
  });

  factory AppOrder.fromJson(Map<String, dynamic> json) {
    return AppOrder(
      row: json['row'] as int,
      date: json['date'].toString(),
      time: json['time'].toString(),
      name: json['name'].toString(),
      wilaya: json['wilaya'].toString(),
      phone: json['phone'].toString(),
      status: json['status'].toString(),
    );
  }

  // Deduplication and sorting logic
  static List<AppOrder> processRawData(List<dynamic> rawData) {
    Map<String, AppOrder> uniqueOrders = {};

    for (var item in rawData) {
      final order = AppOrder.fromJson(item as Map<String, dynamic>);
      // Keep only highest row value for duplicate phones
      if (!uniqueOrders.containsKey(order.phone) || 
          uniqueOrders[order.phone]!.row < order.row) {
        uniqueOrders[order.phone] = order;
      }
    }

    List<AppOrder> processedList = uniqueOrders.values.toList();
    // Sort descending by row (newest first)
    processedList.sort((a, b) => b.row.compareTo(a.row));
    return processedList;
  }
}
