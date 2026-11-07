import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../cubits/returns_cubit.dart';
import '../cubits/returns_state.dart';

class ReturnScreen extends StatefulWidget {
  const ReturnScreen({super.key});

  @override
  State<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends State<ReturnScreen> {
  final _searchCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<ReturnsCubit>()..init(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Process Returns')),
        body: BlocConsumer<ReturnsCubit, ReturnsState>(
          listener: (context, state) {
            if (state.errorMessage != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.errorMessage!), backgroundColor: Colors.red),
              );
            }
            if (state.successMessage != null) {
              _reasonCtrl.clear();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.successMessage!), backgroundColor: Colors.green),
              );
            }
          },
          builder: (context, state) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search bar
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            labelText: 'Search sale by ID or Ref (e.g., S...)',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      context.read<ReturnsCubit>().loadRecentSales();
                                    },
                                  )
                                : null,
                          ),
                          onSubmitted: (val) => context.read<ReturnsCubit>().searchSale(val),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => context.read<ReturnsCubit>().searchSale(_searchCtrl.text),
                        child: const Text('Search'),
                      ),
                      if (state.selectedSale != null) ...[
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () {
                            _searchCtrl.clear();
                            context.read<ReturnsCubit>().clearSelection();
                          },
                          child: const Text('Back to List'),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (state.isLoading)
                    const Expanded(child: Center(child: CircularProgressIndicator()))
                  else if (state.selectedSale != null)
                    Expanded(child: _buildSaleReturnDetails(context, state))
                  else
                    Expanded(child: _buildRecentSalesList(context, state)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRecentSalesList(BuildContext context, ReturnsState state) {
    if (state.recentSales.isEmpty) {
      return const Center(child: Text('No completed sales found to return.'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Select a recent sale to return items:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: state.recentSales.length,
            itemBuilder: (context, index) {
              final sale = state.recentSales[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.receipt)),
                  title: Text('Sale: ${sale.id.length > 8 ? sale.id.substring(0, 8) : sale.id} • Total: \$${Money(sale.total.toInt()).toDisplay()}'),
                  subtitle: Text('Date: ${sale.date.toLocal().toString().split('.')[0]} • Cashier: ${sale.cashierId}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.read<ReturnsCubit>().selectSale(sale),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSaleReturnDetails(BuildContext context, ReturnsState state) {
    final sale = state.selectedSale!;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: Colors.purple.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Selected Sale: ${sale.id.length > 8 ? sale.id.substring(0, 8) : sale.id}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('Date: ${sale.date.toLocal().toString().split('.')[0]} • Paid via: ${sale.paymentMethod.toUpperCase()}'),
                    ],
                  ),
                  Text('Original Total: \$${Money(sale.total.toInt()).toDisplay()}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.purple)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Select quantities to return:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          ...state.returnItems.map((item) {
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.productName.isNotEmpty ? item.productName : item.variantId, style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('${item.color} - ${item.size} • Unit: \$${Money(item.refundUnitPrice).toDisplay()} (Max: ${item.maxQty})', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: item.qty > 0 ? () => context.read<ReturnsCubit>().updateItemQty(item.variantId, item.qty - 1) : null,
                        ),
                        Text('${item.qty}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: item.qty < item.maxQty ? () => context.read<ReturnsCubit>().updateItemQty(item.variantId, item.qty + 1) : null,
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 90,
                      child: Text(
                        '\$${Money(item.lineTotal).toDisplay()}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.purple),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          // Refund Summary & Reason
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Refund Amount:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('\$${Money(state.totalRefund).toDisplay()}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.purple)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Return Reason (Required)',
                      border: OutlineInputBorder(),
                      hintText: 'e.g. Defective, wrong size, customer requested return',
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: state.isProcessing || state.totalRefund == 0
                          ? null
                          : () {
                              String cashierId = 'cashier';
                              try {
                                final authState = context.read<AuthCubit>().state;
                                if (authState is AuthAuthenticated) {
                                  cashierId = authState.user.id;
                                }
                              } catch (_) {}

                              context.read<ReturnsCubit>().processReturn(
                                    reason: _reasonCtrl.text,
                                    userId: cashierId,
                                    paymentMethod: sale.paymentMethod,
                                  );
                            },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
                      icon: state.isProcessing ? const SizedBox.shrink() : const Icon(Icons.assignment_return),
                      label: state.isProcessing
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Confirm and Process Return', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
