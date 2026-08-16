import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'services/firebase_service.dart';
import 'widgets/app_colors.dart';
import 'widgets/ui_components.dart';

class HistoryPage extends StatelessWidget {
  final String type; // 'filling' or 'wastage'

  const HistoryPage({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    final firebase = Provider.of<FirebaseService>(context);
    final title = type == 'filling' ? 'Filling History' : 'Usage History';
    final stream = type == 'filling'
        ? firebase.fillingHistoryStream
        : firebase.wastageHistoryStream;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: AppColors.deepBlue,
                    ),
                  ),
                  Text(
                    'Tracking every drop with precision',
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: stream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  final docs = snapshot.data ?? [];
                  if (docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.history,
                            size: 64,
                            color: Colors.grey.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No data available yet',
                            style: TextStyle(
                              color: Colors.grey.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index];
                      final timestamp = data['timestamp'] as DateTime;
                      final amount =
                          data[type == 'filling'
                              ? 'liters_filled'
                              : 'liters_wasted'] ??
                          0.0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: GlassBox(
                          borderRadius: 15,
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: type == 'filling'
                                      ? Colors.green.withOpacity(0.1)
                                      : Colors.orange.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  type == 'filling'
                                      ? Icons.add_circle
                                      : Icons.remove_circle,
                                  color: type == 'filling'
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      DateFormat(
                                        'EEEE, MMM d, h:mm a',
                                      ).format(timestamp),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.deepBlue,
                                      ),
                                    ),
                                    Text(
                                      'Recorded via Auto-Sensor',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Builder(
                                builder: (context) {
                                  final double displayValue = type == 'filling'
                                      ? (amount * 1000.0) / 10.0
                                      : (amount * 1000.0);

                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${displayValue.toStringAsFixed(1)} ml',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: type == 'filling'
                                              ? Colors.green
                                              : Colors.orange,
                                        ),
                                      ),
                                      Text(
                                        type == 'filling' ? 'Filled' : 'Usage',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 100), // Space for bottom nav
          ],
        ),
      ),
    );
  }
}
