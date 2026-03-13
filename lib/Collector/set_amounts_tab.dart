import 'package:flutter/material.dart';

class SetAmountsTab extends StatelessWidget {
  final List<Map<String, dynamic>> setAmounts;
  final Map<String, dynamic>? selectedMember;
  final int? selectedSetAmountIndex;
  final void Function(int index, double amount, String setAmountId) onSetAmount;
  final Future<void> Function(Map<String, dynamic> paymentData) onSavePayment;
  final List<Map<String, dynamic>> users; // <-- Add this line
  final List<Map<String, dynamic>>
  payments; // Add this to your widget's constructor

  const SetAmountsTab({
    super.key,
    required this.setAmounts,
    required this.selectedMember,
    required this.selectedSetAmountIndex,
    required this.onSetAmount,
    required this.onSavePayment,
    required this.users, // <-- Add this line
    required this.payments, // Add this to your widget's constructor
  });

  @override
  Widget build(BuildContext context) {
    // Add a controller and search state
    final searchController = TextEditingController();
    String searchQuery = '';

    return StatefulBuilder(
      builder: (context, setState) {
        // Filter setAmounts by userdeceased name
        final filteredSetAmounts = searchQuery.isEmpty
            ? setAmounts
            : setAmounts.where((item) {
                final user = users.firstWhere(
                  (u) => u['id'] == item['userdeceased'],
                  orElse: () => <String, dynamic>{},
                );
                final userName = user.isNotEmpty ? user['full_name'] : '';
                return userName.toLowerCase().contains(
                  searchQuery.toLowerCase(),
                );
              }).toList();

        // Sort filteredSetAmounts: unpaid first, then paid
        final sortedSetAmounts = List<Map<String, dynamic>>.from(
          filteredSetAmounts,
        );
        sortedSetAmounts.sort((a, b) {
          final aPaid =
              selectedMember != null &&
              payments.any(
                (payment) =>
                    payment['userdeceased'] == a['userdeceased'] &&
                    payment['user_id'] == selectedMember!['id'] &&
                    payment['status'] == 'paid',
              );
          final bPaid =
              selectedMember != null &&
              payments.any(
                (payment) =>
                    payment['userdeceased'] == b['userdeceased'] &&
                    payment['user_id'] == selectedMember!['id'] &&
                    payment['status'] == 'paid',
              );
          if (aPaid == bPaid) return 0;
          return aPaid ? 1 : -1; // unpaid first
        });

        return Column(
          children: [
            if (selectedMember != null)
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Member: ${selectedMember!['full_name']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0D47A1), // kAccent
                          fontSize: 18,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 800,
                      child: TextField(
                        controller: searchController,
                        decoration: const InputDecoration(
                          hintText: 'Search',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            vertical: 15,
                            horizontal: 17,
                          ),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          setState(() {
                            searchQuery = value;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(18),
                itemCount: sortedSetAmounts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, i) {
                  final item = sortedSetAmounts[i];
                  final user = users.firstWhere(
                    (u) => u['id'] == item['userdeceased'],
                    orElse: () => <String, dynamic>{},
                  );
                  final userName = user.isNotEmpty
                      ? user['full_name']
                      : 'Unknown';

                  // Check if this payment is already paid for the selected user and userdeceased
                  final isPaid =
                      selectedMember != null &&
                      payments.any(
                        (payment) =>
                            payment['userdeceased'] == item['userdeceased'] &&
                            payment['user_id'] == selectedMember!['id'] &&
                            payment['status'] == 'paid',
                      );

                  debugPrint(
                    'SetAmountTile: userdeceased=${item['userdeceased']} '
                    'user_id=${selectedMember?['id']} '
                    'status=${item['status']} '
                    'isPaid=$isPaid',
                  );

                  return ListTile(
                    title: Text(
                      userName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937), // kText
                      ),
                    ),
                    subtitle: isPaid
                        ? const Text(
                            'Paid',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : Text(
                            'Amount: ${item['amount'] ?? '-'}',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Color(0xFF4B5563), // kSubText
                            ),
                          ),
                    tileColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: const Color(0xFF0D47A1).withValues(alpha: 0.10),
                      ),
                    ),
                    onTap: isPaid
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final rootNavigator = Navigator.of(
                              context,
                              rootNavigator: true,
                            );
                            // Debug print for user_id and userdeceased
                            debugPrint(
                              'Tapped member: user_id=${selectedMember?['id']}, userdeceased=${item['userdeceased']}',
                            );

                            final controller = TextEditingController();
                            String? errorText;
                            final userDeceasedId = item['userdeceased'];
                            final requiredAmount = (item['amount'] is int)
                                ? (item['amount'] as int).toDouble()
                                : (item['amount'] is double)
                                ? item['amount'] as double
                                : double.tryParse(item['amount'].toString()) ??
                                      0.0;

                            double? amount = await showDialog<double>(
                              context: context,
                              builder: (context) {
                                final user = users.firstWhere(
                                  (u) => u['id'] == item['userdeceased'],
                                  orElse: () => <String, dynamic>{},
                                );
                                final userName = user.isNotEmpty
                                    ? user['full_name']
                                    : 'Unknown';
                                return StatefulBuilder(
                                  builder: (context, setState) {
                                    return AlertDialog(
                                      title: Text('Set Amount for $userName'),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          TextField(
                                            controller: controller,
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            decoration: InputDecoration(
                                              labelText: 'Amount',
                                              errorText: errorText,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Required: ${item['amount']}',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            final value = double.tryParse(
                                              controller.text,
                                            );
                                            if (value == requiredAmount) {
                                              Navigator.pop(context, value);
                                            } else {
                                              setState(() {
                                                errorText =
                                                    'Amount must be exactly $requiredAmount';
                                              });
                                            }
                                          },
                                          child: const Text('Save'),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            );
                            if (!context.mounted) return;

                            if (amount != null) {
                              final uuidRegExp = RegExp(
                                r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
                              );
                              final userDeceasedIdStr =
                                  userDeceasedId?.toString() ?? '';
                              final userIdStr =
                                  selectedMember?['id']?.toString() ?? '';

                              if (uuidRegExp.hasMatch(userDeceasedIdStr) &&
                                  uuidRegExp.hasMatch(userIdStr)) {
                                // Show loading dialog
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (context) => const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );

                                try {
                                  onSetAmount(i, amount, item['id'].toString());
                                } catch (e) {
                                  rootNavigator.pop();
                                  messenger.showSnackBar(
                                    SnackBar(content: Text('Error: $e')),
                                  );
                                }
                              } else {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Invalid user ID. Cannot save payment.',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
