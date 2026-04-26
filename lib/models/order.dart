class AppOrder {
  final int row;
  final String date;
  final String time;
  String name;
  String wilaya;
  String phone;
  String commune;
  String address;
  String product;
  String price;
  String? trackingNumber;
  String status; // Mutable for local state changes

  AppOrder({
    required this.row,
    required this.date,
    required this.time,
    required this.name,
    required this.wilaya,
    required this.phone,
    this.commune = '',
    this.address = '',
    this.product = '',
    this.price = '',
    this.trackingNumber,
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
      commune: json['commune']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      product: json['product']?.toString() ?? '',
      price: json['price']?.toString() ?? '',
      trackingNumber: json['trackingNumber']?.toString(),
      status: json['status'].toString(),
    );
  }

  int get completionScore =>
      (name.isNotEmpty ? 1 : 0) +
      (phone.isNotEmpty ? 1 : 0) +
      (wilaya.isNotEmpty ? 1 : 0);

  // Deduplication and sorting logic
  static List<AppOrder> processRawData(List<dynamic> rawData) {
    Map<String, AppOrder> uniqueOrders = {};

    for (var item in rawData) {
      final order = AppOrder.fromJson(item as Map<String, dynamic>);

      // Use phone as key; if empty, fall back to row number so rows are never collapsed
      final key = order.phone.trim().isNotEmpty ? order.phone.trim() : 'row_${order.row}';

      if (!uniqueOrders.containsKey(key)) {
        uniqueOrders[key] = order;
      } else {
        final existingOrder = uniqueOrders[key]!;
        // Priority 1: The row with the most completed fields (Name + Phone + Wilaya).
        if (order.completionScore > existingOrder.completionScore) {
          uniqueOrders[key] = order;
        }
        // Priority 2: If data is equal, pick the newest entry (highest row index).
        else if (order.completionScore == existingOrder.completionScore &&
            order.row > existingOrder.row) {
          uniqueOrders[key] = order;
        }
      }
    }

    List<AppOrder> processedList = uniqueOrders.values.toList();
    // Sort descending by row (newest first)
    processedList.sort((a, b) => b.row - a.row);
    return processedList;
  }
}
