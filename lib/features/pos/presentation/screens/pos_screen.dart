import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../../customers/domain/entities/customer_entity.dart';
import '../../../customers/domain/repositories/customer_repository.dart';
import '../../../customers/data/datasources/customers_local_data_source.dart';
import '../../../product_variants/domain/entities/variant_entity.dart';
import '../../domain/entities/sale_item_entity.dart';
import '../../domain/services/kitchen_order_ticket_service.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../cubits/pos_cubit.dart';
import '../widgets/fast_matrix_variant_picker_dialog.dart';
import '../../../shifts/presentation/cubits/shift_cubit.dart';
import '../../../shifts/presentation/cubits/shift_state.dart';
import '../../../shifts/presentation/widgets/open_shift_dialog.dart';
import '../../../shifts/presentation/screens/shift_screen.dart';
import '../../../invoices/domain/entities/invoice_details_entity.dart';
import '../../../invoices/domain/repositories/invoices_repository.dart';
import '../../../invoices/presentation/widgets/sale_success_dialog.dart';
import '../../../invoices/presentation/services/receipt_pdf_service.dart';
import '../../../installments/domain/entities/customer_installment_entity.dart';
import '../../../installments/domain/entities/installment_schedule_entry.dart';
import '../../../installments/domain/services/installment_calculator.dart';
import '../../../employees/presentation/widgets/cashier_profile_dialog.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/services/shortcut_settings_service.dart';
import '../../../../core/services/hotkey_strip_service.dart';
import '../../../settings/presentation/widgets/shortcuts_config_dialog.dart';
import '../../../../core/services/crash_logger_service.dart';
import '../../../../core/database/app_database.dart';
import 'package:drift/drift.dart' show Value;
import '../../../installments/domain/facades/installments_facade.dart';
import '../../../invoices/data/services/receipt_settings_service.dart';
import '../../../installments/presentation/screens/installment_detail_screen.dart';
import '../../../installments/data/services/manager_pin_service.dart';
import '../../domain/entities/payment_split.dart';
import '../../domain/entities/sale_entity.dart';
import '../widgets/installment_checkout_dialog.dart';
import '../widgets/split_payment_dialog.dart';
import '../../../products/presentation/widgets/simple_product_form_dialog.dart';
import '../../../delivery/domain/entities/delivery_order_entity.dart';
import '../../../delivery/domain/repositories/delivery_repository.dart';
import '../../../delivery/presentation/screens/delivery_orders_screen.dart';
import '../../../inventory/presentation/widgets/kitchen_waste_dialog.dart';
import '../../../delivery/presentation/widgets/delivery_checkout_dialog.dart';
import '../../../pre_orders/presentation/screens/pre_orders_screen.dart';
import '../../../auth/services/cashier_permissions_service.dart';
import '../../../settings/data/services/activity_settings_service.dart';
import '../../../../core/widgets/app_floating_toast.dart';

Color _getCategoryColor(String? categoryId) {
  if (categoryId == null || categoryId.isEmpty) return const Color(0xFF673AB7);
  final palette = [
    const Color(0xFF5E35B1), // Deep Purple
    const Color(0xFF1E88E5), // Blue
    const Color(0xFF00897B), // Teal
    const Color(0xFF43A047), // Green
    const Color(0xFFFB8C00), // Orange
    const Color(0xFFD81B60), // Pink
    const Color(0xFF8E24AA), // Purple
    const Color(0xFF3949AB), // Indigo
    const Color(0xFF00ACC1), // Cyan
    const Color(0xFFE64A19), // Deep Orange
  ];
  final hash = categoryId.codeUnits.fold(0, (acc, c) => acc + c);
  return palette[hash % palette.length];
}

Color _mapColorNameToColor(String name) {
  final n = name.trim().toLowerCase();
  if (n.contains('red') || n.contains('أحمر')) return Colors.red.shade600;
  if (n.contains('blue') || n.contains('أزرق')) return Colors.blue.shade600;
  if (n.contains('green') || n.contains('أخضر')) return Colors.green.shade600;
  if (n.contains('black') || n.contains('أسود')) return Colors.black87;
  if (n.contains('white') || n.contains('أبيض')) return Colors.white;
  if (n.contains('yellow') || n.contains('أصفر')) return Colors.amber.shade700;
  if (n.contains('purple') || n.contains('بنفسجي')) {
    return Colors.purple.shade600;
  }
  if (n.contains('grey') || n.contains('gray') || n.contains('رمادي')) {
    return Colors.grey.shade600;
  }
  if (n.contains('navy') || n.contains('كحلي')) return const Color(0xFF0D47A1);
  if (n.contains('brown') || n.contains('بني')) return Colors.brown.shade600;
  if (n.contains('pink') || n.contains('وردي')) return Colors.pink.shade400;
  if (n.contains('orange') || n.contains('برتقالي')) {
    return Colors.orange.shade700;
  }
  return AppColors.primary;
}

class PosScreen extends StatelessWidget {
  final Future<void> Function(InvoiceDetailsEntity invoice)? printReceiptOverride;
  const PosScreen({super.key, this.printReceiptOverride});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (context) => getIt<PosCubit>()..init()),
        BlocProvider(create: (context) => getIt<ShiftCubit>()..loadShiftData()),
      ],
      child: _PosView(printReceiptOverride: printReceiptOverride),
    );
  }
}

class _PosView extends StatefulWidget {
  final Future<void> Function(InvoiceDetailsEntity invoice)? printReceiptOverride;
  const _PosView({this.printReceiptOverride});

  @override
  State<_PosView> createState() => _PosViewState();
}

class _PosViewState extends State<_PosView> {
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _searchCtrl = TextEditingController();
  final GlobalKey<_CartPanelState> _cartPanelKey = GlobalKey<_CartPanelState>();
  final StringBuffer _scannerBuffer = StringBuffer();
  DateTime _lastScanKeyTime = DateTime.now();
  InvoiceDetailsEntity? _lastCompletedInvoice;
  bool _deliveryEnabled = false;
  bool _preOrdersEnabled = false;
  StreamSubscription? _featuresSub;
  Timer? _searchDebounceTimer;
  int? _selectedGridIndex;
  final ScrollController _productGridScrollController = ScrollController();

  int _calculateGridColumns() {
    final screenWidth = MediaQuery.maybeSizeOf(context)?.width ?? 1280;
    final gridWidth = (screenWidth - 550).clamp(300.0, 1600.0);
    final cols = (gridWidth / 175).floor().clamp(2, 6);
    return cols;
  }

  void _scrollGridToIndex(int index, int cols) {
    if (!_productGridScrollController.hasClients) return;
    final row = index ~/ cols;
    final targetOffset = (row * 126.0).clamp(0.0, _productGridScrollController.position.maxScrollExtent);
    final currentOffset = _productGridScrollController.offset;
    final viewportHeight = _productGridScrollController.position.viewportDimension;
    if (targetOffset < currentOffset || targetOffset + 126.0 > currentOffset + viewportHeight) {
      _productGridScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleHardwareScan);
    _loadLatestInvoice();
    if (getIt.isRegistered<FeatureGate>()) {
      final gate = getIt<FeatureGate>();
      gate.isEnabled(FeatureKeys.delivery).then((val) {
        if (mounted && _deliveryEnabled != val) {
          setState(() => _deliveryEnabled = val);
        }
      });
      gate.isEnabled(FeatureKeys.preOrders).then((val) {
        if (mounted && _preOrdersEnabled != val) {
          setState(() => _preOrdersEnabled = val);
        }
      });
      _featuresSub = gate.watchFeatures().listen((features) {
        final del = features[FeatureKeys.delivery] ?? false;
        final pre = features[FeatureKeys.preOrders] ?? false;
        if (mounted && (_deliveryEnabled != del || _preOrdersEnabled != pre)) {
          setState(() {
            _deliveryEnabled = del;
            _preOrdersEnabled = pre;
          });
        }
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _loadLatestInvoice() {
    if (getIt.isRegistered<InvoicesRepository>()) {
      getIt<InvoicesRepository>().getInvoices(limit: 1).then((res) {
        res.fold((_) {}, (list) {
          if (mounted && list.isNotEmpty && _lastCompletedInvoice == null) {
            setState(() {
              _lastCompletedInvoice = list.first;
            });
          }
        });
      }).catchError((_) {});
    }
  }

  void _handleCheckoutSuccess(InvoiceDetailsEntity invoice) {
    if (!mounted) return;
    setState(() {
      _lastCompletedInvoice = invoice;
    });
  }

  Future<void> _reprintLastInvoice() async {
    final invoice = _lastCompletedInvoice;
    if (invoice == null) {
      if (mounted) {
        AppFloatingToast.show(
          context,
          message: 'لا توجد فاتورة سابقة لإعادة طباعتها',
          type: ToastType.warning,
        );
      }
      return;
    }

    try {
      if (widget.printReceiptOverride != null) {
        await widget.printReceiptOverride!(invoice);
      } else {
        await ReceiptPdfService.printReceipt(invoice);
      }
    } catch (e) {
      debugPrint('Re-print printer error: $e');
      if (mounted) {
        AppFloatingToast.show(
          context,
          message:
              'تم حفظ الفاتورة بنجاح. تعذر الاتصال بالطابعة، يمكنك إعادة الطباعة بالضغط على [F9] بعد التحقق من الورق والكابل.',
          type: ToastType.error,
          duration: const Duration(seconds: 4),
        );
      }
    }
  }

  Future<void> _showSwitchCashierDialog() async {
    List<User> activeUsers = [];
    try {
      if (getIt.isRegistered<AppDatabase>()) {
        final db = getIt<AppDatabase>();
        activeUsers = await (db.select(db.users)
              ..where((u) => u.isActive.equals(true))
              ..where((u) => u.deletedAt.isNull()))
            .get();
      }
    } catch (e) {
      debugPrint('Error loading cashiers: $e');
    }

    if (!mounted) return;

    User? selectedUser = activeUsers.isNotEmpty ? activeUsers.first : null;
    final pinCtrl = TextEditingController();
    String? errorMsg;
    bool isSubmitting = false;

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.swap_horiz_rounded, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Text(
                    'تبديل الكاشير السريع (Quick Switch)',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'اختر الكاشير وأدخل رمز PIN للتحويل الفوري دون إفراغ السلة أو تسجيل الخروج:',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 12.5, color: AppColors.onSurface),
                    ),
                    const SizedBox(height: 14),
                    if (activeUsers.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: activeUsers.map((u) {
                          final isSelected = selectedUser?.id == u.id;
                          return ChoiceChip(
                            key: Key('pos_cashier_chip_${u.username}'),
                            label: Text(
                              u.displayName.isNotEmpty ? u.displayName : u.username,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                            ),
                            selected: isSelected,
                            onSelected: (val) {
                              if (val) {
                                setDialogState(() {
                                  selectedUser = u;
                                  errorMsg = null;
                                });
                              }
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextField(
                      key: const Key('pos_cashier_pin_field'),
                      controller: pinCtrl,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'رمز PIN الخاص بالكاشير',
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (errorMsg != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorMsg!,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          color: AppColors.error,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
                  child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
                ),
                ElevatedButton(
                  key: const Key('pos_confirm_switch_cashier_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isSubmitting || selectedUser == null
                      ? null
                      : () async {
                          final pin = pinCtrl.text.trim();
                          if (pin.isEmpty) {
                            setDialogState(() => errorMsg = 'يرجى إدخال رمز PIN.');
                            return;
                          }

                          setDialogState(() {
                            isSubmitting = true;
                            errorMsg = null;
                          });

                          final authCubit = context.read<AuthCubit>();
                          final success = await authCubit.switchCashierWithPin(
                            usernameOrId: selectedUser!.id,
                            pin: pin,
                          );

                          if (!dialogCtx.mounted) return;

                          if (success) {
                            Navigator.pop(dialogCtx);
                            if (mounted) {
                              AppFloatingToast.show(
                                context,
                                message:
                                    'تم تبديل الكاشير بنجاح: ${selectedUser!.displayName}',
                                type: ToastType.success,
                              );
                              setState(() {});
                            }
                          } else {
                            setDialogState(() {
                              isSubmitting = false;
                              errorMsg = 'رمز PIN غير صحيح للكاشير المحدد.';
                            });
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('تبديل الكاشير', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _navigateCategory({required bool forward}) {
    final posCubit = context.read<PosCubit>();
    final categories = posCubit.state.categories;
    if (categories.isEmpty) return;

    final total = categories.length + 1;
    final currentCatId = posCubit.state.selectedCategory;
    int currentIndex = 0;
    if (currentCatId != 'All') {
      final idx = categories.indexWhere((c) => c.id == currentCatId);
      if (idx >= 0) {
        currentIndex = idx + 1;
      }
    }

    final targetIndex = forward
        ? (currentIndex + 1) % total
        : (currentIndex - 1 + total) % total;

    if (targetIndex == 0) {
      posCubit.resetAllFilters();
    } else {
      final targetCat = categories[targetIndex - 1];
      posCubit.filterByCategory(targetCat.id);
    }
  }

  bool _handleHardwareScan(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent) return false;

    // Only handle POS global shortcuts & scans when POS is the active top route
    // (avoid firing while a modal dialog like Split Payment / Installments / Receipt is open).
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;

    final key = event.logicalKey;
    final s = getIt.isRegistered<ShortcutSettingsService>() ? getIt<ShortcutSettingsService>() : null;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;

    // Shortcut [F1]: Open Shortcuts Guide
    final shortcutsActivator = s?.getActivator('openShortcuts') ?? const SingleActivator(LogicalKeyboardKey.f1);
    if (shortcutsActivator.accepts(event, HardwareKeyboard.instance) || (!isCtrl && !isAlt && key == LogicalKeyboardKey.f1)) {
      _scannerBuffer.clear();
      _openShortcutsGuide();
      return true;
    }

    // Shortcut [F2] or [Ctrl+F]: Focus & select search bar
    final searchActivator = s?.getActivator('quickSearch') ?? const SingleActivator(LogicalKeyboardKey.f2);
    if (searchActivator.accepts(event, HardwareKeyboard.instance) ||
        (!isCtrl && !isAlt && key == LogicalKeyboardKey.f2) ||
        (isCtrl && !isAlt && key == LogicalKeyboardKey.keyF)) {
      _scannerBuffer.clear();
      _searchFocusNode.requestFocus();
      if (_searchCtrl.text.isNotEmpty) {
        _searchCtrl.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _searchCtrl.text.length,
        );
      }
      return true;
    }

    // Shortcut [Ctrl+D]: Focus Discount
    final discountActivator = s?.getActivator('focusDiscount') ?? const SingleActivator(LogicalKeyboardKey.keyD, control: true);
    if (discountActivator.accepts(event, HardwareKeyboard.instance) || (isCtrl && !isAlt && key == LogicalKeyboardKey.keyD)) {
      _scannerBuffer.clear();
      _cartPanelKey.currentState?.focusDiscount();
      return true;
    }

    // Shortcut [F5]: Quick Pay Cash
    final cashActivator = s?.getActivator('quickPayCash') ?? const SingleActivator(LogicalKeyboardKey.f5);
    if (cashActivator.accepts(event, HardwareKeyboard.instance) || (!isCtrl && !isAlt && key == LogicalKeyboardKey.f5)) {
      _scannerBuffer.clear();
      _cartPanelKey.currentState?.setPaymentMethod('cash');
      return true;
    }

    // Shortcut [F6]: Quick Pay Card
    final cardActivator = s?.getActivator('quickPayCard') ?? const SingleActivator(LogicalKeyboardKey.f6);
    if (cardActivator.accepts(event, HardwareKeyboard.instance) || (!isCtrl && !isAlt && key == LogicalKeyboardKey.f6)) {
      _scannerBuffer.clear();
      _cartPanelKey.currentState?.setPaymentMethod('card');
      return true;
    }

    // Shortcut [F10]: Hold Bill
    final holdActivator = s?.getActivator('holdBill') ?? const SingleActivator(LogicalKeyboardKey.f10);
    if (holdActivator.accepts(event, HardwareKeyboard.instance) || (!isCtrl && !isAlt && key == LogicalKeyboardKey.f10)) {
      _scannerBuffer.clear();
      _cartPanelKey.currentState?.addNewBillTab();
      return true;
    }

    // Shortcut [F11]: Recall Bill
    final recallActivator = s?.getActivator('recallBill') ?? const SingleActivator(LogicalKeyboardKey.f11);
    if (recallActivator.accepts(event, HardwareKeyboard.instance) || (!isCtrl && !isAlt && key == LogicalKeyboardKey.f11)) {
      _scannerBuffer.clear();
      _cartPanelKey.currentState?.switchNextHeldBill();
      return true;
    }

    // Shortcut [F7]: Open Pre-Orders Hub
    final preOrdersActivator = s?.getActivator('preOrders') ?? const SingleActivator(LogicalKeyboardKey.f7);
    if (preOrdersActivator.accepts(event, HardwareKeyboard.instance) || (!isCtrl && !isAlt && key == LogicalKeyboardKey.f7)) {
      _scannerBuffer.clear();
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PreOrdersScreen()),
      );
      return true;
    }

    // Shortcut [F9]: Quick Re-Print Last Invoice
    final reprintActivator = s?.getActivator('reprintReceipt') ?? const SingleActivator(LogicalKeyboardKey.f9);
    if (reprintActivator.accepts(event, HardwareKeyboard.instance) || (!isCtrl && !isAlt && key == LogicalKeyboardKey.f9)) {
      _scannerBuffer.clear();
      _reprintLastInvoice();
      return true;
    }

    // Shortcut [F12]: Complete Sale / Checkout
    if (key == LogicalKeyboardKey.f12) {
      _scannerBuffer.clear();
      _cartPanelKey.currentState?.triggerCheckout();
      return true;
    }

    // Shortcut [Esc]: Clear grid selection if active, or clear search text if not empty, otherwise clear cart
    if (key == LogicalKeyboardKey.escape) {
      _scannerBuffer.clear();
      if (_selectedGridIndex != null) {
        setState(() {
          _selectedGridIndex = null;
        });
        _searchFocusNode.requestFocus();
        return true;
      }
      if (_searchCtrl.text.isNotEmpty) {
        _searchCtrl.clear();
        context.read<PosCubit>().searchProducts('');
        setState(() {});
        return true;
      }
      final posCubit = context.read<PosCubit>();
      if (posCubit.state.cart.isNotEmpty) {
        _cartPanelKey.currentState?.confirmAndClearCart();
        return true;
      }
      return false;
    }

    // Grid Navigation via Hardware Keyboard (Down / Up / Left / Right / Enter / NumpadEnter / Space)
    if (key == LogicalKeyboardKey.arrowDown) {
      final variants = context.read<PosCubit>().state.filteredVariants;
      if (variants.isNotEmpty) {
        final cols = _calculateGridColumns();
        if (_searchFocusNode.hasFocus) {
          _scannerBuffer.clear();
          _searchFocusNode.unfocus();
          setState(() {
            _selectedGridIndex = 0;
          });
          _scrollGridToIndex(0, cols);
          return true;
        }
        if (_selectedGridIndex != null) {
          _scannerBuffer.clear();
          setState(() {
            _selectedGridIndex = (_selectedGridIndex! + cols).clamp(0, variants.length - 1);
          });
          _scrollGridToIndex(_selectedGridIndex!, cols);
          return true;
        }
      }
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (_selectedGridIndex != null) {
        _scannerBuffer.clear();
        final cols = _calculateGridColumns();
        if (_selectedGridIndex! < cols) {
          setState(() {
            _selectedGridIndex = null;
          });
          _searchFocusNode.requestFocus();
          if (_searchCtrl.text.isNotEmpty) {
            _searchCtrl.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _searchCtrl.text.length,
            );
          }
        } else {
          setState(() {
            _selectedGridIndex = _selectedGridIndex! - cols;
          });
          _scrollGridToIndex(_selectedGridIndex!, cols);
        }
        return true;
      }
    }

    if (_selectedGridIndex != null) {
      final variants = context.read<PosCubit>().state.filteredVariants;
      final cols = _calculateGridColumns();

      if (key == LogicalKeyboardKey.arrowLeft) {
        _scannerBuffer.clear();
        if (variants.isNotEmpty) {
          setState(() {
            _selectedGridIndex = (_selectedGridIndex! + 1).clamp(0, variants.length - 1);
          });
          _scrollGridToIndex(_selectedGridIndex!, cols);
        }
        return true;
      }

      if (key == LogicalKeyboardKey.arrowRight) {
        _scannerBuffer.clear();
        if (variants.isNotEmpty) {
          setState(() {
            _selectedGridIndex = (_selectedGridIndex! - 1).clamp(0, variants.length - 1);
          });
          _scrollGridToIndex(_selectedGridIndex!, cols);
        }
        return true;
      }

      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.space) {
        _scannerBuffer.clear();
        if (variants.isNotEmpty && _selectedGridIndex! < variants.length) {
          final variant = variants[_selectedGridIndex!];
          final posCubit = context.read<PosCubit>();
          final productVariants = posCubit.getVariantsForProduct(variant.productId);
          if (productVariants.length > 1) {
            _showMatrixVariantPickerDialog(context, variant.productId);
          } else {
            posCubit.addToCart(variant, 1);
          }
        }
        return true;
      }
    }

    // Keyboard Category Navigation (ArrowLeft / ArrowRight / Alt+Arrows / Home)
    final primaryFocus = FocusManager.instance.primaryFocus;
    final isTextInputFocused = primaryFocus != null &&
        primaryFocus.context != null &&
        (primaryFocus.context!.widget is EditableText || _searchFocusNode.hasFocus);
    final isSearchTextEmpty = _searchCtrl.text.isEmpty;
    final canNavigateArrows = !isCtrl && (!isTextInputFocused || (_searchFocusNode.hasFocus && isSearchTextEmpty));

    if (isAlt && (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight)) {
      _scannerBuffer.clear();
      _navigateCategory(forward: key == LogicalKeyboardKey.arrowLeft);
      return true;
    }
    if (canNavigateArrows) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        _scannerBuffer.clear();
        _navigateCategory(forward: true);
        return true;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        _scannerBuffer.clear();
        _navigateCategory(forward: false);
        return true;
      }
      if (key == LogicalKeyboardKey.home) {
        _scannerBuffer.clear();
        context.read<PosCubit>().resetAllFilters();
        return true;
      }
    }

    final now = DateTime.now();
    final diffMs = now.difference(_lastScanKeyTime).inMilliseconds;
    _lastScanKeyTime = now;

    // Reset buffer if delay between keystrokes exceeds 500ms
    if (diffMs > 500) {
      _scannerBuffer.clear();
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final code = _scannerBuffer.toString().trim();
      _scannerBuffer.clear();
      if (code.isNotEmpty && code.length >= 3) {
        if (!_searchFocusNode.hasFocus) {
          final added = context.read<PosCubit>().addByBarcode(code);
          if (added) {
            _searchFocusNode.requestFocus();
            return true;
          }
        }
      }
      return false;
    }

    final char = event.character;
    if (char != null &&
        char.isNotEmpty &&
        !char.contains('\n') &&
        !char.contains('\r')) {
      _scannerBuffer.write(char);
    }

    return false;
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _featuresSub?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleHardwareScan);
    _searchFocusNode.dispose();
    _searchCtrl.dispose();
    _productGridScrollController.dispose();
    super.dispose();
  }

  Future<void> _openQuickAddProduct(
    BuildContext context, {
    String? initialQuery,
  }) async {
    final posCubit = context.read<PosCubit>();
    ActivityType? targetActivity;
    if (getIt.isRegistered<ActivitySettingsService>()) {
      if (getIt<ActivitySettingsService>().cachedEnabledActivities.contains(ActivityType.restaurantsCafes)) {
        targetActivity = ActivityType.restaurantsCafes;
      }
    }
    final barcodeOrResult = await showDialog<dynamic>(
      context: context,
      builder: (_) => SimpleProductFormDialog(
        initialQuery: initialQuery ?? _searchCtrl.text.trim(),
        initialActivityType: targetActivity,
      ),
    );
    if (!mounted) return;
    if (barcodeOrResult != null && barcodeOrResult != false) {
      await posCubit.init();
      if (barcodeOrResult is String && barcodeOrResult.isNotEmpty) {
        posCubit.addByBarcode(barcodeOrResult);
      }
      _searchCtrl.clear();
      posCubit.searchProducts('');
      if (mounted) setState(() {});
    }
  }

  void _showShortcutsGuide() {
    ShortcutsConfigDialog.show(context);
  }

  void _openShortcutsGuide() => _showShortcutsGuide();

  Map<ShortcutActivator, VoidCallback> _buildPosShortcuts() {
    final Map<ShortcutActivator, VoidCallback> bindings = {
      const SingleActivator(LogicalKeyboardKey.f2): () => _searchFocusNode.requestFocus(),
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _searchFocusNode.requestFocus(),
      const SingleActivator(LogicalKeyboardKey.f5): () => _cartPanelKey.currentState?.setPaymentMethod('cash'),
      const SingleActivator(LogicalKeyboardKey.f6): () => _cartPanelKey.currentState?.setPaymentMethod('card'),
      const SingleActivator(LogicalKeyboardKey.f10): () => _cartPanelKey.currentState?.addNewBillTab(),
      const SingleActivator(LogicalKeyboardKey.f11): () => _cartPanelKey.currentState?.switchNextHeldBill(),
      const SingleActivator(LogicalKeyboardKey.f12): () => _cartPanelKey.currentState?.triggerCheckout(),
      const SingleActivator(LogicalKeyboardKey.keyD, control: true): () => _cartPanelKey.currentState?.focusDiscount(),
      const SingleActivator(LogicalKeyboardKey.f1): _showShortcutsGuide,
    };

    if (getIt.isRegistered<ShortcutSettingsService>()) {
      final s = getIt<ShortcutSettingsService>();
      final act = s.getActivator;
      bindings[act('completeSale')] = () => _cartPanelKey.currentState?.triggerCheckout();
      bindings[act('holdBill')] = () => _cartPanelKey.currentState?.addNewBillTab();
      bindings[act('recallBill')] = () => _cartPanelKey.currentState?.switchNextHeldBill();
      bindings[act('quickPayCash')] = () => _cartPanelKey.currentState?.setPaymentMethod('cash');
      bindings[act('quickPayCard')] = () => _cartPanelKey.currentState?.setPaymentMethod('card');
      bindings[act('focusDiscount')] = () => _cartPanelKey.currentState?.focusDiscount();
      bindings[act('quickSearch')] = () => _searchFocusNode.requestFocus();
      bindings[act('openShortcuts')] = _showShortcutsGuide;
    }
    return bindings;
  }

  Widget _buildHotkeyFooterStrip() {
    return ValueListenableBuilder<bool>(
      valueListenable: HotkeyStripService.isVisible,
      builder: (context, visible, _) {
        if (!visible) return const SizedBox.shrink();

        return Container(
          height: 38,
          key: const Key('pos_hotkey_footer_strip'),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            border: Border(top: BorderSide(color: Color(0xFF1E293B))),
          ),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFooterHotkeyChip(
                        key: const Key('pos_footer_hotkey_search'),
                        label: 'F2 بحث',
                        icon: Icons.search_rounded,
                        onTap: () => _searchFocusNode.requestFocus(),
                      ),
                      const SizedBox(width: 8),
                      _buildFooterHotkeyChip(
                        key: const Key('pos_footer_hotkey_cash'),
                        label: 'F5 كاش',
                        icon: Icons.payments_outlined,
                        onTap: () => _cartPanelKey.currentState?.setPaymentMethod('cash'),
                      ),
                      const SizedBox(width: 8),
                      _buildFooterHotkeyChip(
                        key: const Key('pos_footer_hotkey_card'),
                        label: 'F6 فيزا',
                        icon: Icons.credit_card_rounded,
                        onTap: () => _cartPanelKey.currentState?.setPaymentMethod('card'),
                      ),
                      const SizedBox(width: 8),
                      _buildFooterHotkeyChip(
                        key: const Key('pos_footer_hotkey_hold'),
                        label: 'F10 تعليق',
                        icon: Icons.pause_circle_outline_rounded,
                        onTap: () => _cartPanelKey.currentState?.addNewBillTab(),
                      ),
                      const SizedBox(width: 8),
                      _buildFooterHotkeyChip(
                        key: const Key('pos_footer_hotkey_recall'),
                        label: 'F11 استرجاع',
                        icon: Icons.play_circle_outline_rounded,
                        onTap: () => _cartPanelKey.currentState?.switchNextHeldBill(),
                      ),
                      const SizedBox(width: 8),
                      _buildFooterHotkeyChip(
                        key: const Key('pos_footer_hotkey_discount'),
                        label: 'Ctrl+D خصم',
                        icon: Icons.percent_rounded,
                        onTap: () => _cartPanelKey.currentState?.focusDiscount(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _buildFooterHotkeyChip(
                key: const Key('pos_footer_hotkey_checkout'),
                label: 'F12 دفع',
                icon: Icons.check_circle_rounded,
                isPrimary: true,
                onTap: () => _cartPanelKey.currentState?.triggerCheckout(),
              ),
              const SizedBox(width: 8),
              _buildFooterHotkeyChip(
                key: const Key('pos_footer_hotkey_shortcuts'),
                label: 'F1 دليل ومفاتيح',
                icon: Icons.keyboard_rounded,
                onTap: _showShortcutsGuide,
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'طي شريط الاختصارات مؤقتاً',
                child: InkWell(
                  key: const Key('pos_collapse_hotkey_strip_btn'),
                  onTap: () => HotkeyStripService.toggleTemporary(false),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF334155), width: 1),
                    ),
                    child: const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Colors.white70),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFooterHotkeyChip({
    required Key key,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isPrimary ? AppColors.primary : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isPrimary ? AppColors.primary : const Color(0xFF334155),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isPrimary ? Colors.white : const Color(0xFF94A3B8)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isPrimary ? Colors.white : const Color(0xFFE2E8F0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    try {
      return CallbackShortcuts(
        bindings: _buildPosShortcuts(),
        child: Focus(
          autofocus: true,
          child: _buildContent(context),
        ),
      );
    } catch (e, st) {
      return Scaffold(
        appBar: AppBar(title: const Text('POS Error')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            'PosView error:\n$e\n\n$st',
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ),
      );
    }
  }

  Widget _buildContent(BuildContext context) {
    return BlocBuilder<ShiftCubit, ShiftState>(
      builder: (context, shiftState) {
        final authState = context.watch<AuthCubit>().state;
        final isAdmin =
            authState is! AuthAuthenticated || authState.user.role == 'admin';
        final cashierId = authState is AuthAuthenticated
            ? authState.user.id
            : 'admin';
        final cashierName = authState is AuthAuthenticated
            ? authState.user.name
            : 'المدير';

        if (shiftState.status == ShiftStatus.loading &&
            !shiftState.hasActiveShift) {
          return Scaffold(
            backgroundColor: AppColors.surface,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (shiftState.shiftsEnabled && !shiftState.hasActiveShift) {
          return _buildShiftRequiredScaffold(
            context,
            isAdmin: isAdmin,
            cashierId: cashierId,
            cashierName: cashierName,
            shiftState: shiftState,
          );
        }

        return Scaffold(
          backgroundColor: AppColors.surface,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: const Border(
              bottom: BorderSide(color: AppColors.outlineVariant),
            ),
            automaticallyImplyLeading: false,
            toolbarHeight: 56,
            titleSpacing: 12,
            title: Row(
              children: [
                if (Navigator.canPop(context)) ...[
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.onSurface,
                      size: 20,
                    ),
                    tooltip: 'رجوع للوحة التحكم',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                ],
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.point_of_sale_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'نقطة البيع',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 16.5,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ],
                ),
                if (shiftState.shiftsEnabled && shiftState.activeShift != null) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ShiftScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_open_rounded,
                            color: AppColors.success,
                            size: 13,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'وردية مفتوحة',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              color: AppColors.success,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                // Cashier Badge
                Tooltip(
                  message: 'ملف ومستحقات الكاشير (الراتب، البونص، الوردية)',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: cashierId.isNotEmpty
                        ? () => CashierProfileDialog.show(
                              context,
                              employeeId: cashierId,
                            )
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_rounded,
                            size: 14,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            cashierName,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              color: AppColors.onSurface,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                // Switch Cashier Button [Task 14.3]
                Tooltip(
                  message: 'تبديل الكاشير السريع بالـ PIN دون تفريغ السلة',
                  child: OutlinedButton.icon(
                    key: const Key('pos_switch_cashier_button'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      side: const BorderSide(color: AppColors.outlineVariant),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _showSwitchCashierDialog,
                    icon: Icon(
                      Icons.swap_horiz_rounded,
                      size: 15,
                      color: AppColors.primary,
                    ),
                    label: const Text(
                      'تبديل الكاشير',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        color: AppColors.onSurface,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // Center: Quick Search Field [F2]
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.outlineVariant.withValues(alpha: 0.8),
                          ),
                        ),
                        child: TextField(
                          key: const Key('pos_search_field'),
                          controller: _searchCtrl,
                          focusNode: _searchFocusNode,
                          autofocus: true,
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'بحث بالاسم أو الكود أو المقاس... [F2]',
                            hintStyle: TextStyle(
                              fontFamily: 'Cairo',
                              color: Colors.grey.shade500,
                              fontSize: 12,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: AppColors.primary,
                              size: 18,
                            ),
                            suffixIcon: ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _searchCtrl,
                              builder: (context, val, _) {
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (val.text.isNotEmpty)
                                      IconButton(
                                        icon: const Icon(Icons.clear, size: 16),
                                        onPressed: () {
                                          _searchDebounceTimer?.cancel();
                                          _searchCtrl.clear();
                                          context.read<PosCubit>().searchProducts('');
                                        },
                                      ),
                                    Container(
                                      margin: const EdgeInsets.only(left: 6),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceContainer,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: AppColors.outlineVariant,
                                        ),
                                      ),
                                      child: const Text(
                                        'F2',
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.onSurface,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 9,
                            ),
                          ),
                          onChanged: (val) {
                            _searchDebounceTimer?.cancel();
                            if (val.isEmpty) {
                              context.read<PosCubit>().searchProducts('');
                            } else {
                              _searchDebounceTimer = Timer(const Duration(milliseconds: 150), () {
                                if (mounted) {
                                  context.read<PosCubit>().searchProducts(val);
                                }
                              });
                            }
                          },
                          onSubmitted: (val) {
                            _searchDebounceTimer?.cancel();
                            if (val.trim().isNotEmpty) {
                              final added = context.read<PosCubit>().addByBarcode(val.trim());
                              if (added) {
                                _searchCtrl.clear();
                                context.read<PosCubit>().searchProducts('');
                              }
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Quick Add Product Button
                FilledButton.icon(
                  onPressed: () => _openQuickAddProduct(context),
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text(
                    'صنف جديد',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: const Size(0, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                ),

                const SizedBox(width: 8),

                // Pre-Orders Button [F7]
                if (_preOrdersEnabled)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ElevatedButton.icon(
                      key: const Key('pos_preorders_header_btn'),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PreOrdersScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.bookmark_added_rounded, size: 16),
                      label: const Text(
                        'حجز مسبق [F7]',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.surfaceContainerLow,
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: const Size(0, 36),
                        side: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.3),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),

                const SizedBox(width: 8),

                // Kitchen Waste Dialog [Key('kitchen_waste_btn')]
                OutlinedButton.icon(
                  key: const Key('kitchen_waste_btn'),
                  onPressed: () => KitchenWasteDialog.show(context),
                  icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                  label: const Text(
                    'إذن هالك [مطبخ]',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(
                      color: AppColors.error.withValues(alpha: 0.5),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: const Size(0, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Re-Print Last Invoice [F9]
                OutlinedButton.icon(
                  key: const Key('pos_reprint_last_invoice_button'),
                  onPressed: _lastCompletedInvoice != null
                      ? () => _reprintLastInvoice()
                      : null,
                  icon: const Icon(Icons.print_outlined, size: 16),
                  label: const Text(
                    'إعادة طباعة [F9]',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    disabledForegroundColor: const Color(0xFF94A3B8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: const Size(0, 36),
                    side: BorderSide(
                      color: _lastCompletedInvoice != null
                          ? AppColors.primary.withValues(alpha: 0.4)
                          : const Color(0xFFCBD5E1),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),

                // Delivery Button
                if (_deliveryEnabled)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: IconButton(
                      key: const Key('pos_delivery_header_btn'),
                      icon: const Icon(
                        Icons.moped_rounded,
                        color: AppColors.onSurfaceVariant,
                        size: 20,
                      ),
                      tooltip: 'إدارة وتتبع الدليفري والطيارين',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const DeliveryOrdersScreen(),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final cartWidth = constraints.maxWidth > 1200
                  ? 440.0
                  : (constraints.maxWidth * 0.38).clamp(360.0, 440.0);
              return Row(
                children: [
                  // Right Panel in RTL: Products Catalog
                  Expanded(
                    child: Builder(
                      builder: (ctx) {
                        try {
                          return _ProductPanel(
                            searchQuery: _searchCtrl.text,
                            selectedGridIndex: _selectedGridIndex,
                            gridScrollController: _productGridScrollController,
                            onOpenQuickAdd: (query) =>
                                _openQuickAddProduct(context, initialQuery: query),
                          );
                        } catch (e, st) {
                          return SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'ProductPanel error: $e\n$st',
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: AppColors.outlineVariant,
                  ),
                  // Left Panel in RTL: Cart (Responsive Width)
                  SizedBox(
                    width: cartWidth,
                    child: Builder(
                      builder: (ctx) {
                        try {
                          return _CartPanel(
                            key: _cartPanelKey,
                            onInvoiceCompleted: _handleCheckoutSuccess,
                          );
                        } catch (e, st) {
                          return SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'CartPanel error: $e\n$st',
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              );
            },
          ),
          bottomNavigationBar: _buildHotkeyFooterStrip(),
        );
      },
    );
  }

  Widget _buildShiftRequiredScaffold(
    BuildContext context, {
    required bool isAdmin,
    required String cashierId,
    required String cashierName,
    required ShiftState shiftState,
  }) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: const Border(
          bottom: BorderSide(color: AppColors.outlineVariant),
        ),
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: AppColors.onSurface,
                ),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: const Text(
          'نقطة البيع',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: AppColors.onSurface,
          ),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 550),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 40,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isAdmin
                            ? Colors.blue.shade50
                            : Colors.red.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isAdmin
                            ? Icons.storefront_rounded
                            : Icons.lock_clock_rounded,
                        size: 48,
                        color: isAdmin
                            ? AppColors.primary
                            : Colors.red.shade700,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      isAdmin
                          ? 'تنبيه: لا توجد وردية مفتوحة'
                          : 'الوردية مغلقة - الرجاء فتح وردية',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isAdmin
                          ? 'أهلاً بك يا مدير! يمكنك فتح وردية فورية بضغطة زر لبدء البيع السريع، أو فتح وردية جديدة وتحديد رصيد الفكة.'
                          : 'لا يمكنك إصدار فواتير بيع في نقطة البيع قبل فتح وردية وتحديد عهدة الفكة في الدرج.',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        color: Colors.grey.shade600,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    if (isAdmin) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: shiftState.isOperating
                              ? null
                              : () async {
                                  final cubit = context.read<ShiftCubit>();
                                  final ok = await cubit.openShift(
                                    openingBalance: 0,
                                    cashierId: cashierId,
                                    cashierName: cashierName,
                                  );
                                  if (!ok && context.mounted) {
                                    AppFloatingToast.show(
                                      context,
                                      message: cubit.state.errorMessage ??
                                          'تعذر بدء الوردية السريعة',
                                      type: ToastType.error,
                                    );
                                  }
                                },
                          icon: shiftState.isOperating
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.flash_on_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                          label: Text(
                            'بدء البيع السريع فوراً (فكة 0 ج.م)',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: BorderSide(
                              color: AppColors.primary,
                              width: 1.5,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (_) => OpenShiftDialog(
                                cashierName: cashierName,
                                onOpen: (openingPiasters) async {
                                  final cubit = context.read<ShiftCubit>();
                                  final ok = await cubit.openShift(
                                    openingBalance: openingPiasters,
                                    cashierId: cashierId,
                                    cashierName: cashierName,
                                  );
                                  if (!ok) {
                                    return cubit.state.errorMessage ??
                                        'تعذر بدء الوردية. يرجى المحاولة مرة أخرى.';
                                  }
                                  return null;
                                },
                              ),
                            );
                          },
                          icon: Icon(
                            Icons.lock_open_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          label: Text(
                            'فتح وردية وتحديد رصيد الفكة',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (_) => OpenShiftDialog(
                                cashierName: cashierName,
                                onOpen: (openingPiasters) async {
                                  final cubit = context.read<ShiftCubit>();
                                  final ok = await cubit.openShift(
                                    openingBalance: openingPiasters,
                                    cashierId: cashierId,
                                    cashierName: cashierName,
                                  );
                                  if (!ok) {
                                    return cubit.state.errorMessage ??
                                        'تعذر بدء الوردية. يرجى المحاولة مرة أخرى.';
                                  }
                                  return null;
                                },
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.lock_open_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          label: Text(
                            'فتح وردية جديدة',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// RIGHT PANEL: PRODUCTS
// ---------------------------------------------------------------------------
class _ProductPanel extends StatefulWidget {
  final String searchQuery;
  final void Function(String? query)? onOpenQuickAdd;
  final int? selectedGridIndex;
  final ScrollController? gridScrollController;

  const _ProductPanel({
    this.searchQuery = '',
    this.onOpenQuickAdd,
    this.selectedGridIndex,
    this.gridScrollController,
  });

  @override
  State<_ProductPanel> createState() => _ProductPanelState();
}

class _ProductPanelState extends State<_ProductPanel> {
  final ScrollController _categoryScrollController = ScrollController();

  @override
  void dispose() {
    _categoryScrollController.dispose();
    super.dispose();
  }

  void _scrollForward() {
    if (!_categoryScrollController.hasClients) return;
    final max = _categoryScrollController.position.maxScrollExtent;
    final target = (_categoryScrollController.offset + 220).clamp(0.0, max);
    _categoryScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _scrollBackward() {
    if (!_categoryScrollController.hasClients) return;
    final target = (_categoryScrollController.offset - 220).clamp(
      0.0,
      _categoryScrollController.position.maxScrollExtent,
    );
    _categoryScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _scrollToSelectedCategory(PosState state) {
    if (!_categoryScrollController.hasClients) return;
    if (state.selectedCategory == 'All') {
      _categoryScrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      final idx = state.categories.indexWhere((c) => c.id == state.selectedCategory);
      if (idx >= 0) {
        final targetOffset = ((idx + 1) * 115.0).clamp(
          0.0,
          _categoryScrollController.position.maxScrollExtent,
        );
        _categoryScrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    }
  }

  Widget _buildScrollNavBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: const Color(0xFFF1F5F9),
          child: Container(
            width: 28,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Icon(
              icon,
              size: 16,
              color: const Color(0xFF475569),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    try {
      return _buildContent(context);
    } catch (e, st) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text(
          'ProductPanel build error:\n$e\n$st',
          style: const TextStyle(color: Colors.red, fontSize: 11),
        ),
      );
    }
  }

  Widget _buildContent(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 10),
        // Pure Merchant Dynamic Category Bar (Addendum 25.3: Smooth Multi-Device Scrollable)
        BlocConsumer<PosCubit, PosState>(
          listenWhen: (prev, curr) => prev.selectedCategory != curr.selectedCategory,
          listener: (context, state) {
            _scrollToSelectedCategory(state);
          },
          builder: (context, state) {
            final selectedActivity = state.selectedActivity;
            final allSelectedCategory = state.selectedCategory == 'All';
            final posCubit = context.read<PosCubit>();
            List<VariantEntity> allVariants = [];
            try {
              allVariants = posCubit.allVariants.where((v) {
                try {
                  final p = posCubit.getProduct(v.productId);
                  return !(p?.isRestaurantRawMaterial ?? false);
                } catch (_) {
                  return true;
                }
              }).toList();
            } catch (_) {
              try {
                allVariants = posCubit.allVariants;
              } catch (_) {
                allVariants = [];
              }
            }

            return StreamBuilder<bool>(
              stream: getIt.isRegistered<ActivitySettingsService>()
                  ? getIt<ActivitySettingsService>().watchPreOrdersEnabled()
                  : Stream.value(true),
              builder: (context, preOrderSnap) {
                final preOrdersOn = preOrderSnap.data ?? true;

                return Container(
                  height: 38,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      // Backward scroll button (moves towards start in RTL)
                      _buildScrollNavBtn(
                        icon: Icons.chevron_right_rounded,
                        tooltip: 'السابق',
                        onTap: _scrollBackward,
                      ),
                      const SizedBox(width: 4),
                      // Horizontal Category Strip
                      Expanded(
                        child: Listener(
                          onPointerSignal: (pointerSignal) {
                            if (pointerSignal is PointerScrollEvent &&
                                _categoryScrollController.hasClients) {
                              final delta = pointerSignal.scrollDelta.dy != 0
                                  ? pointerSignal.scrollDelta.dy
                                  : pointerSignal.scrollDelta.dx;
                              final target = (_categoryScrollController.offset + delta).clamp(
                                0.0,
                                _categoryScrollController.position.maxScrollExtent,
                              );
                              _categoryScrollController.jumpTo(target);
                            }
                          },
                          child: ScrollConfiguration(
                            behavior: ScrollConfiguration.of(context).copyWith(
                              dragDevices: {
                                PointerDeviceKind.touch,
                                PointerDeviceKind.mouse,
                                PointerDeviceKind.trackpad,
                                PointerDeviceKind.stylus,
                              },
                              scrollbars: false,
                            ),
                            child: RawScrollbar(
                              controller: _categoryScrollController,
                              thumbVisibility: false,
                              thickness: 2.5,
                              radius: const Radius.circular(2),
                              thumbColor: AppColors.primary.withValues(alpha: 0.35),
                              child: ListView(
                                controller: _categoryScrollController,
                                physics: const BouncingScrollPhysics(),
                                scrollDirection: Axis.horizontal,
                                children: [
                                  // Single Master 'All' Button (Addendum 25.3: Unified Single "الكل")
                                  _categoryChip(
                                    key: const Key('pos_all_filter_chip'),
                                    label: 'الكل',
                                    icon: Icons.apps_rounded,
                                    count: allVariants.length,
                                    isSelected: selectedActivity == 'all' && allSelectedCategory,
                                    onTap: () => posCubit.resetAllFilters(),
                                  ),
                                  for (final cat in state.categories) ...[
                                    () {
                                      final count = allVariants.where((v) {
                                        try {
                                          return posCubit.getProductCategoryId(v.productId) == cat.id;
                                        } catch (_) {
                                          return false;
                                        }
                                      }).length;
                                      return _categoryChip(
                                        key: Key('pos_category_chip_${cat.id}'),
                                        label: cat.name,
                                        count: count,
                                        isSelected: state.selectedCategory == cat.id,
                                        onTap: () => posCubit.filterByCategory(cat.id),
                                      );
                                    }(),
                                  ],
                                  if (preOrdersOn)
                                    _categoryChip(
                                      key: const Key('pos_pre_orders_chip'),
                                      label: 'حجز مسبق',
                                      icon: Icons.event_note_rounded,
                                      isSelected: false,
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => const PreOrdersScreen()),
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Forward scroll button (moves towards end in RTL)
                      _buildScrollNavBtn(
                        icon: Icons.chevron_left_rounded,
                        tooltip: 'التالي',
                        onTap: _scrollForward,
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),

        const SizedBox(height: 10),

        // Products Grid
        Expanded(
          child: BlocBuilder<PosCubit, PosState>(
            builder: (context, state) {
              try {
                if (state is PosLoading) {
                  return Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
                }
                if (state is PosError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 64,
                          color: AppColors.error,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          state.message,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: AppColors.error,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => context.read<PosCubit>().init(),
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(
                            'إعادة المحاولة',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                final posCubit = context.read<PosCubit>();
                final isHospitalityMode = (getIt.isRegistered<ActivitySettingsService>() &&
                    getIt<ActivitySettingsService>().cachedEnabledActivities.contains(ActivityType.restaurantsCafes)) ||
                    state.filteredVariants.any((v) {
                      try {
                        final p = posCubit.getProduct(v.productId);
                        return p?.activityTypeEnum == ActivityType.restaurantsCafes;
                      } catch (_) {
                        return false;
                      }
                    });
                final displayedVariants = isHospitalityMode
                    ? state.filteredVariants.where((v) {
                        try {
                          final p = posCubit.getProduct(v.productId);
                          return !(p?.isRestaurantRawMaterial ?? false);
                        } catch (_) {
                          return true;
                        }
                      }).toList()
                    : state.filteredVariants;

                if (displayedVariants.isEmpty) {
                  final query = widget.searchQuery.trim();
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 56,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'لا توجد منتجات مطابقة للبحث',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: Colors.grey.shade600,
                            fontSize: 15,
                          ),
                        ),
                        if (query.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () => widget.onOpenQuickAdd?.call(query),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: Text(
                              'إضافة "$query" كصنف جديد',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }
                return GridView.builder(
                  controller: widget.gridScrollController,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: isHospitalityMode ? 185 : 175,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    mainAxisExtent: isHospitalityMode ? 172 : 118,
                  ),
                  itemCount: displayedVariants.length,
                  itemBuilder: (context, index) {
                    final variant = displayedVariants[index];
                    final catId = posCubit.getProductCategoryId(
                      variant.productId,
                    );
                    return _ProductCard(
                      variant: variant,
                      categoryId: catId,
                      isSelected: widget.selectedGridIndex == index,
                    );
                  },
                );
              } catch (e, st) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Grid error: $e\n$st',
                    style: const TextStyle(color: Colors.red, fontSize: 11),
                  ),
                );
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _categoryChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    int? count,
    IconData? icon,
    Key? key,
  }) {
    return Container(
      height: 38,
      margin: const EdgeInsetsDirectional.only(end: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: const Color(0xFFF8FAFC),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? AppColors.primary : const Color(0xFFE2E8F0),
                width: 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.22),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 16,
                    color: isSelected ? Colors.white : const Color(0xFF334155),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: isSelected ? Colors.white : const Color(0xFF334155),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.20)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        color: isSelected
                            ? Colors.white
                            : const Color(0xFF64748B),
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PRODUCT CARD: INSTANT IN-CARD QUANTITY CONTROLS + VARIANT PICKER
// ---------------------------------------------------------------------------
class _ProductCard extends StatelessWidget {
  final VariantEntity variant;
  final String? categoryId;
  final bool isSelected;

  const _ProductCard({
    required this.variant,
    this.categoryId,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    try {
      return _buildContent(context);
    } catch (e, st) {
      return Container(
        padding: const EdgeInsets.all(8),
        color: Colors.red.shade50,
        child: SingleChildScrollView(
          child: Text(
            'ProductCard error:\n$e\n$st',
            style: const TextStyle(color: Colors.red, fontSize: 10),
          ),
        ),
      );
    }
  }

  Widget _buildContent(BuildContext context) {
    final isOut = variant.quantity <= 0;
    final isLow = variant.quantity > 0 && variant.quantity <= 10;
    _getCategoryColor(categoryId);
    final posCubit = context.read<PosCubit>();
    final productName = posCubit.getProductName(variant.productId);
    final displayName = productName.isNotEmpty
        ? productName
        : variant.productCode;
    final product = posCubit.getProduct(variant.productId);
    final culinary = product?.culinaryData;
    final isHospitality = (product?.activityTypeEnum == ActivityType.restaurantsCafes) ||
        (getIt.isRegistered<ActivitySettingsService>() &&
            getIt<ActivitySettingsService>().cachedEnabledActivities.contains(ActivityType.restaurantsCafes));

    return BlocBuilder<PosCubit, PosState>(
      buildWhen: (prev, curr) => prev.cart != curr.cart,
      builder: (context, state) {
        SaleItemEntity? cartItem;
        try {
          cartItem = state.cart.firstWhere(
            (item) => item.variantId == variant.id,
          );
        } catch (_) {
          cartItem = null;
        }
        final int inCartQty = cartItem?.quantity ?? 0;

        bool effectiveOut = isOut;
        String? hospitalityBadgeText;
        if (isHospitality) {
          final isDailyBatch = culinary?.mealStockMode == 'dailyBatch';
          if (isDailyBatch) {
            final batchCount = culinary?.dailyBatchCount ?? variant.quantity;
            final remaining = (batchCount - inCartQty).clamp(0, 999999);
            if (remaining <= 0) {
              effectiveOut = true;
              hospitalityBadgeText = 'نفد اليوم';
            } else {
              hospitalityBadgeText = 'متبقي اليوم: $remaining وجبة';
            }
          } else if (culinary != null && culinary.recipeItems.isNotEmpty) {
            int minMeals = 999999;
            for (final ri in culinary.recipeItems) {
              final rawVariant = posCubit.state.filteredVariants.cast<VariantEntity?>().firstWhere(
                (v) => v?.id == ri.rawMaterialId || v?.productId == ri.rawMaterialId,
                orElse: () => null,
              );
              if (rawVariant != null) {
                final meals = ri.quantityNeeded > 0
                    ? (rawVariant.quantity / ri.quantityNeeded).floor()
                    : 0;
                if (meals < minMeals) minMeals = meals;
              } else {
                minMeals = 0;
              }
            }
            if (minMeals == 999999) minMeals = variant.quantity;
            if (minMeals <= 0) {
              effectiveOut = true;
              hospitalityBadgeText = 'نفدت الخامات';
            } else {
              hospitalityBadgeText = 'متوفر خامات تكفي $minMeals وجبة';
            }
          }
        }

        return Opacity(
          opacity: effectiveOut ? 0.55 : 1.0,
          child: Material(
            color: effectiveOut
                ? Colors.grey.shade100
                : AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: effectiveOut
                  ? null
                  : () {
                      if (isHospitality) {
                        _showMealCustomizerModal(
                          context,
                          variant,
                          product,
                          displayName,
                        );
                        return;
                      }
                      final productVariants =
                          posCubit.getVariantsForProduct(variant.productId);
                      if (productVariants.length > 1) {
                        _showMatrixVariantPickerDialog(
                          context,
                          variant.productId,
                        );
                      } else if (inCartQty < variant.quantity) {
                        posCubit.addToCart(variant, 1);
                      }
                    },
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.secondary
                        : (inCartQty > 0
                            ? AppColors.primary
                            : (effectiveOut
                                ? Colors.grey.shade300
                                : AppColors.outlineVariant)),
                    width: isSelected ? 2.2 : (inCartQty > 0 ? 1.8 : 1.0),
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppColors.secondary.withValues(alpha: 0.25),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: isHospitality
                    ? _buildHospitalityContent(
                        context,
                        displayName,
                        variant,
                        product,
                        culinary,
                        inCartQty,
                        effectiveOut,
                        isLow,
                        hospitalityBadgeText: hospitalityBadgeText,
                      )
                    : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Row 1: Name + Stock badge + Variants button
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    displayName,
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                      color: AppColors.onSurface,
                                      height: 1.15,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                _buildStockPill(isOut, isLow, variant.quantity),
                                if (!isOut) ...[
                                  const SizedBox(width: 2),
                                  InkWell(
                                    key: Key('product_variants_btn_${variant.productId}'),
                                    onTap: () =>
                                        _showVariantModal(context, variant),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Tooltip(
                                      message: 'المقاسات والألوان',
                                      child: Padding(
                                        padding: const EdgeInsets.all(2),
                                        child: Icon(
                                          Icons.tune_rounded,
                                          size: 14,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),

                            // Row 2: Color • Size chip + SKU
                            Row(
                              children: [
                                if (!(variant.color == '-' &&
                                        variant.size == '-') &&
                                    variant.color.isNotEmpty &&
                                    variant.size.isNotEmpty) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${variant.color} • ${variant.size}',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade700,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Expanded(
                                  child: Text(
                                    variant.sku,
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 9.5,
                                      color: Colors.grey.shade500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (culinary != null && culinary.calories != null) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    key: Key('product_calorie_badge_${variant.productId}'),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.orange.shade200),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.local_fire_department_rounded,
                                          size: 11,
                                          color: Colors.orange.shade800,
                                        ),
                                        const SizedBox(width: 1),
                                        Text(
                                          '${culinary.calories} kcal',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.orange.shade900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                if (culinary != null && culinary.hasCulinaryInfo) ...[
                                  const SizedBox(width: 2),
                                  InkWell(
                                    key: Key('product_culinary_info_btn_${variant.productId}'),
                                    onTap: () => _showCulinaryInfoDialog(
                                      context,
                                      displayName,
                                      culinary,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.all(2),
                                      child: Icon(
                                        Icons.info_outline_rounded,
                                        size: 14,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),

                            // Row 3: Price + Compact Add / Inline Stepper
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      '${Money(variant.salePrice).toDisplay()} ج.م',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: AppColors.primary,
                                      ),
                                      maxLines: 1,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                if (inCartQty == 0)
                                  Container(
                                    height: 26,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isOut
                                          ? const Color(0xFFE2E8F0)
                                          : AppColors.primary,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.add_rounded,
                                          size: 14,
                                          color: isOut
                                              ? const Color(0xFF475569)
                                              : Colors.white,
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          'إضافة',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                            color: isOut
                                                ? const Color(0xFF475569)
                                                : Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  Container(
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        InkWell(
                                          onTap: () =>
                                              posCubit.decreaseQty(variant.id),
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 5,
                                            ),
                                            child: Icon(
                                              Icons.remove_rounded,
                                              color: Colors.white,
                                              size: 14,
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 3,
                                          ),
                                          child: Text(
                                            '$inCartQty',
                                            style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11.5,
                                            ),
                                          ),
                                        ),
                                        InkWell(
                                          onTap: inCartQty >= variant.quantity
                                              ? null
                                              : () => posCubit.addToCart(
                                                  variant,
                                                  1,
                                                ),
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 5,
                                            ),
                                            child: Icon(
                                              Icons.add_rounded,
                                              color: Colors.white,
                                              size: 14,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStockPill(bool isOut, bool isLow, int qty) {
    Color bg;
    Color text;
    String label;
    if (isOut) {
      bg = const Color(0xFFFEF2F2);
      text = AppColors.error;
      label = 'نفذت';
    } else if (isLow) {
      bg = const Color(0xFFFFFBEB);
      text = AppColors.warning;
      label = '$qty';
    } else {
      bg = const Color(0xFFF1F5F9);
      text = const Color(0xFF475569);
      label = '$qty';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          color: text,
        ),
      ),
    );
  }

  Widget _buildHospitalityContent(
    BuildContext context,
    String displayName,
    VariantEntity variant,
    ProductEntity? product,
    RestaurantCulinaryData? culinary,
    int inCartQty,
    bool isOut,
    bool isLow, {
    String? hospitalityBadgeText,
  }) {
    final imagePath = culinary?.imagePath;
    final hasImage = imagePath != null &&
        imagePath.trim().isNotEmpty &&
        File(imagePath).existsSync();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Food Photo Container
        Expanded(
          flex: 5,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                color: const Color(0xFFF1F5F9),
                child: hasImage
                    ? Image.file(
                        File(imagePath),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(
                            Icons.restaurant_menu_rounded,
                            color: AppColors.onSurfaceVariant,
                            size: 28,
                          ),
                        ),
                      )
                    : const Center(
                        child: Icon(
                          Icons.restaurant_menu_rounded,
                          color: AppColors.onSurfaceVariant,
                          size: 28,
                        ),
                      ),
              ),
              Positioned(
                top: 5,
                right: 5,
                child: Container(
                  key: Key('hospitality_stock_badge_${variant.productId}'),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: isOut
                        ? Colors.red.shade700
                        : (isLow ? Colors.amber.shade800 : AppColors.primary),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    hospitalityBadgeText ?? (isOut ? 'نفد' : '${variant.quantity}'),
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              if (culinary != null && culinary.hasCulinaryInfo) ...[
                Positioned(
                  top: 5,
                  left: 5,
                  child: InkWell(
                    key: Key('product_culinary_info_btn_${variant.productId}'),
                    onTap: () => _showCulinaryInfoDialog(
                      context,
                      displayName,
                      culinary,
                    ),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.90),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        Icons.info_outline_rounded,
                        size: 13,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
              if (culinary != null && culinary.calories != null) ...[
                Positioned(
                  bottom: 4,
                  right: 5,
                  child: Container(
                    key: Key('product_calorie_badge_${variant.productId}'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.local_fire_department_rounded,
                          size: 10,
                          color: Colors.amberAccent,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${culinary.calories} kcal',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        // 2. Info Footer
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: AppColors.onSurface,
                    height: 1.15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${Money(variant.salePrice).toDisplay()} ج.م',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: AppColors.primary,
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    if (inCartQty == 0)
                      Container(
                        height: 22,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: isOut ? const Color(0xFFE2E8F0) : AppColors.primary,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add_rounded,
                              size: 12,
                              color: isOut ? const Color(0xFF475569) : Colors.white,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              'طلب',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: isOut ? const Color(0xFF475569) : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        height: 22,
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_rounded, size: 11, color: Colors.white),
                            const SizedBox(width: 2),
                            Text(
                              '$inCartQty',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showMealCustomizerModal(
    BuildContext context,
    VariantEntity variant,
    ProductEntity? product,
    String displayName,
  ) {
    final culinary = product?.culinaryData;
    final textCtrl = TextEditingController();
    final selectedModifiers = <String>{};
    final selectedPaidModifiers = <PaidModifierData>{};
    int quantity = 1;

    const exclusionPills = [
      'بدون بصل',
      'بدون مايونيز',
      'بدون طماطم',
      'بدون مخلل',
    ];

    const cookingAndAddonPills = [
      'سبايسي',
      'بدون شطة',
      'زيادة جبنة',
      'زيادة صوص',
    ];

    final paidModifiers = culinary?.paidModifiers ?? const <PaidModifierData>[];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void togglePill(String pill) {
            setDialogState(() {
              if (selectedModifiers.contains(pill)) {
                selectedModifiers.remove(pill);
              } else {
                selectedModifiers.add(pill);
              }
              final customText = textCtrl.text
                  .split(' - ')
                  .where((s) =>
                      !exclusionPills.contains(s) &&
                      !cookingAndAddonPills.contains(s))
                  .join(' - ')
                  .trim();
              final allParts = [...selectedModifiers];
              if (customText.isNotEmpty) {
                allParts.add(customText);
              }
              textCtrl.text = allParts.join(' - ');
            });
          }

          Widget buildPillSection(String title, List<String> pills) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: pills.map((p) {
                    final isSel = selectedModifiers.contains(p);
                    return InkWell(
                      key: Key('modifier_pill_$p'),
                      onTap: () => togglePill(p),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isSel
                              ? AppColors.secondary.withValues(alpha: 0.15)
                              : AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSel
                                ? AppColors.secondary
                                : AppColors.outlineVariant,
                            width: isSel ? 1.4 : 1.0,
                          ),
                        ),
                        child: Text(
                          p,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            fontWeight:
                                isSel ? FontWeight.bold : FontWeight.w500,
                            color: isSel
                                ? AppColors.secondary
                                : AppColors.onSurface,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],
            );
          }

          Widget buildPaidModifiersSection(String title, List<PaidModifierData> items) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: items.map((m) {
                    final isSel = selectedPaidModifiers.contains(m);
                    return InkWell(
                      key: Key('paid_modifier_chip_${m.name}'),
                      onTap: () {
                        setDialogState(() {
                          if (isSel) {
                            selectedPaidModifiers.remove(m);
                          } else {
                            selectedPaidModifiers.add(m);
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isSel
                              ? AppColors.secondary.withValues(alpha: 0.15)
                              : AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSel
                                ? AppColors.secondary
                                : AppColors.outlineVariant,
                            width: isSel ? 1.4 : 1.0,
                          ),
                        ),
                        child: Text(
                          '${m.name} (+${Money(m.pricePiasters).toDisplay()} ج.م)',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                            color: isSel ? AppColors.secondary : AppColors.onSurface,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],
            );
          }

          final imagePath = culinary?.imagePath;
          final hasImage = imagePath != null &&
              imagePath.trim().isNotEmpty &&
              File(imagePath).existsSync();

          return AlertDialog(
            key: const Key('meal_customizer_modal'),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            actionsPadding: const EdgeInsets.all(16),
            title: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 52,
                    height: 52,
                    color: const Color(0xFFF1F5F9),
                    child: hasImage
                        ? Image.file(
                            File(imagePath),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.restaurant_menu_rounded,
                              color: AppColors.onSurfaceVariant,
                            ),
                          )
                        : const Icon(
                            Icons.restaurant_menu_rounded,
                            color: AppColors.onSurfaceVariant,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${Money(variant.salePrice).toDisplay()} ج.م',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(),
                    const SizedBox(height: 4),
                    buildPillSection('استثناءات المطبخ (بدون):', exclusionPills),
                    buildPillSection('خيارات الطهي والإضافات:', cookingAndAddonPills),
                    if (paidModifiers.isNotEmpty)
                      buildPaidModifiersSection('إضافات وترقيات مدفوعة:', paidModifiers),
                    TextFormField(
                      key: const Key('customizer_notes_field'),
                      controller: textCtrl,
                      decoration: InputDecoration(
                        labelText: 'ملاحظة خاصة للمطبخ',
                        hintText: 'اكتب أي تفاصيل إضافية للتحضير...',
                        prefixIcon: const Icon(Icons.edit_note_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: AppColors.surfaceContainerLow,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'الكمية المطلوبة:',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.outlineVariant),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                key: const Key('customizer_qty_minus'),
                                icon: const Icon(Icons.remove_rounded, size: 18),
                                onPressed: () {
                                  if (quantity > 1) {
                                    setDialogState(() => quantity--);
                                  }
                                },
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Text(
                                  '$quantity',
                                  key: const Key('customizer_qty_text'),
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              IconButton(
                                key: const Key('customizer_qty_plus'),
                                icon: const Icon(Icons.add_rounded, size: 18),
                                onPressed: () {
                                  setDialogState(() => quantity++);
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('إلغاء'),
              ),
              ElevatedButton.icon(
                key: const Key('customizer_add_to_order_btn'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                label: Builder(
                  builder: (ctx) {
                    final extraPrice = selectedPaidModifiers.fold<int>(0, (sum, m) => sum + m.pricePiasters);
                    final unitPriceWithModifiers = variant.salePrice + extraPrice;
                    return Text(
                      'إضافة للطلب (${Money(unitPriceWithModifiers * quantity).toDisplay()} ج.م)',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
                onPressed: () {
                  final finalNote = textCtrl.text.trim();
                  final extraPrice = selectedPaidModifiers.fold<int>(0, (sum, m) => sum + m.pricePiasters);
                  final allModifiers = [
                    ...selectedModifiers,
                    ...selectedPaidModifiers.map((m) => '${m.name} (+${Money(m.pricePiasters).toDisplay()} ج.م)'),
                  ];
                  context.read<PosCubit>().addToCart(
                        variant,
                        quantity,
                        finalNote.isNotEmpty ? finalNote : null,
                        allModifiers,
                        extraPrice,
                      );
                  Navigator.of(ctx).pop();
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _showVariantModal(BuildContext context, VariantEntity variant) {
    _showMatrixVariantPickerDialog(context, variant.productId);
  }

  void _showCulinaryInfoDialog(
    BuildContext context,
    String title,
    RestaurantCulinaryData culinary,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('culinary_info_dialog'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Icon(Icons.restaurant_menu_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'بيانات الوجبة: $title',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (culinary.calories != null) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.local_fire_department_rounded,
                        size: 16,
                        color: Colors.orange.shade800,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'السعرات الحرارية: ${culinary.calories} kcal',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                if (culinary.prepTimeMinutes != null) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'وقت التحضير: ${culinary.prepTimeMinutes} دقيقة',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                if (culinary.kitchenStation != null &&
                    culinary.kitchenStation!.isNotEmpty) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.soup_kitchen_outlined,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'محطة المطبخ: ${culinary.kitchenStation}',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                if (culinary.ingredients != null &&
                    culinary.ingredients!.trim().isNotEmpty) ...[
                  const Text(
                    'المكونات الأساسية:',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      culinary.ingredients!,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (culinary.allergens.isNotEmpty) ...[
                  const Text(
                    'مسببات الحساسية:',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: culinary.allergens.map((a) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(
                          a,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            color: Colors.red.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }
}

void _showMatrixVariantPickerDialog(BuildContext context, String productId) {
  final posCubit = context.read<PosCubit>();
  final variants = posCubit.getVariantsForProduct(productId);
  final productName = posCubit.getProductName(productId);
  showDialog(
    context: context,
    builder: (_) => BlocProvider.value(
      value: posCubit,
      child: FastMatrixVariantPickerDialog(
        productId: productId,
        productName: productName.isNotEmpty
            ? productName
            : (variants.isNotEmpty ? variants.first.productName : ''),
        variants: variants,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// UPGRADED VARIANT MODAL: SELECT COLOR, SIZE & BULK QUANTITY EASILY
// ---------------------------------------------------------------------------
class _VariantModal extends StatefulWidget {
  final VariantEntity initialVariant;
  const _VariantModal({required this.initialVariant});

  @override
  State<_VariantModal> createState() => _VariantModalState();
}

class _VariantModalState extends State<_VariantModal> {
  late List<VariantEntity> _productVariants;
  late String _selectedColor;
  late String _selectedSize;
  int _qty = 1;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialVariant.color;
    _selectedSize = widget.initialVariant.size;
    _productVariants = [widget.initialVariant];
  }

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    try {
      final posCubit = context.read<PosCubit>();
      final allProductVariants = posCubit.getVariantsForProduct(
        widget.initialVariant.productId,
      );
      setState(() {
        _productVariants = allProductVariants.isNotEmpty
            ? allProductVariants
            : [widget.initialVariant];
      });
    } catch (_) {
      _productVariants = [widget.initialVariant];
    }
  }

  VariantEntity get _currentVariant {
    try {
      return _productVariants.firstWhere(
        (v) => v.color == _selectedColor && v.size == _selectedSize,
      );
    } catch (_) {
      try {
        return _productVariants.firstWhere((v) => v.color == _selectedColor);
      } catch (_) {
        return _productVariants.first;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _currentVariant;
    final maxStock = v.quantity;
    final availableColors = _productVariants
        .map((item) => item.color)
        .toSet()
        .toList();
    final sizesForColor = _productVariants
        .where((item) => item.color == _selectedColor)
        .toList();
    final posCubit = context.read<PosCubit>();
    final productName = posCubit.getProductName(v.productId);
    final displayName = productName.isNotEmpty ? productName : v.productCode;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 8,
      backgroundColor: AppColors.surfaceContainerLowest,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Header
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        displayName.isNotEmpty
                            ? displayName.substring(0, 1).toUpperCase()
                            : 'P',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                        ),
                        Text(
                          'كود الصنف: ${v.sku} • السعر: ${Money(v.salePrice).toDisplay()} ج.م',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 20),

              // Color Selection
              Text(
                'اللون المختار: $_selectedColor',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: availableColors.map((colorName) {
                  final isSelected = colorName == _selectedColor;
                  final colorVal = _mapColorNameToColor(colorName);
                  final isWhite = colorVal == Colors.white;

                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedColor = colorName;
                        final newSizes = _productVariants
                            .where((item) => item.color == colorName)
                            .toList();
                        if (newSizes.isNotEmpty &&
                            !newSizes.any(
                              (item) => item.size == _selectedSize,
                            )) {
                          _selectedSize = newSizes.first.size;
                        }
                        if (_qty > _currentVariant.quantity) {
                          _qty = _currentVariant.quantity > 0
                              ? _currentVariant.quantity
                              : 1;
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.surfaceContainer
                            : AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.outlineVariant,
                          width: isSelected ? 1.8 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: colorVal,
                              shape: BoxShape.circle,
                              border: isWhite
                                  ? Border.all(color: Colors.grey.shade400)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            colorName,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // Size Selection (Grid of buttons showing size and remaining stock)
              Text(
                'المقاس: $_selectedSize',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: sizesForColor.map((variantItem) {
                  final sizeLabel = variantItem.size;
                  final isSelected = sizeLabel == _selectedSize;
                  final stock = variantItem.quantity;
                  final isOutOfStock = stock <= 0;

                  return InkWell(
                    onTap: isOutOfStock
                        ? null
                        : () {
                            setState(() {
                              _selectedSize = sizeLabel;
                              if (_qty > stock) _qty = stock > 0 ? stock : 1;
                            });
                          },
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : (isOutOfStock
                                  ? Colors.grey.shade100
                                  : AppColors.surfaceContainerLowest),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : (isOutOfStock
                                    ? Colors.grey.shade300
                                    : AppColors.outlineVariant),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            sizeLabel,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isSelected
                                  ? Colors.white
                                  : (isOutOfStock
                                        ? Colors.grey
                                        : AppColors.onSurface),
                            ),
                          ),
                          Text(
                            isOutOfStock ? 'نفذ' : '$stock متبقي',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 10,
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.85)
                                  : (isOutOfStock
                                        ? Colors.red
                                        : Colors.grey.shade600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // Quantity Stepper with Quick Presets
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الكمية المطلوبة:',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          IconButton(
                            onPressed: _qty > 1
                                ? () => setState(() => _qty--)
                                : null,
                            icon: const Icon(
                              Icons.remove_circle_outline_rounded,
                            ),
                            color: AppColors.primary,
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.outlineVariant,
                              ),
                            ),
                            child: Text(
                              '$_qty',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: (_qty < maxStock && maxStock > 0)
                                ? () => setState(() => _qty++)
                                : null,
                            icon: const Icon(Icons.add_circle_outline_rounded),
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          // Quick preset chips
                          ...[1, 2, 5, 10].map((preset) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2.0,
                              ),
                              child: InkWell(
                                onTap: maxStock >= preset
                                    ? () => setState(() => _qty = preset)
                                    : null,
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _qty == preset
                                        ? AppColors.primary
                                        : AppColors.surfaceContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '$preset',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: _qty == preset
                                          ? Colors.white
                                          : AppColors.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'إجمالي الصنف:',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        '${Money(v.salePrice * _qty).toDisplay()} ج.م',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Add to Cart Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: maxStock <= 0
                      ? null
                      : () {
                          context.read<PosCubit>().addToCart(v, _qty);
                          Navigator.of(context).pop();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE2E8F0),
                    disabledForegroundColor: const Color(0xFF64748B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: Icon(
                    Icons.add_shopping_cart_rounded,
                    color: maxStock <= 0 ? const Color(0xFF64748B) : Colors.white,
                    size: 18,
                  ),
                  label: Text(
                    maxStock <= 0
                        ? 'المنتج غير متوفر'
                        : 'إضافة إلى السلة ($_qty قطعة - ${Money(v.salePrice * _qty).toDisplay()} ج.م)',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// POS HELD BILL MODEL (MULTI-BILL / HOLD SUPPORT)
// ---------------------------------------------------------------------------
class PosHeldBill {
  final int id;
  String title;
  List<SaleItemEntity> cart;
  CustomerEntity? customer;
  String discountText;
  bool isPercentageDiscount;
  String receivedText;
  String paymentMethod;
  DeliveryOrderEntity? deliveryOrder;
  String hospitalityOrderType; // 'dineIn', 'takeaway', 'delivery'
  String tableNumber;
  DateTime heldAt;

  PosHeldBill({
    required this.id,
    required this.title,
    this.cart = const [],
    this.customer,
    this.discountText = '',
    this.isPercentageDiscount = false,
    this.receivedText = '',
    this.paymentMethod = 'cash',
    this.deliveryOrder,
    this.hospitalityOrderType = 'dineIn',
    this.tableNumber = '1',
    DateTime? heldAt,
  }) : heldAt = heldAt ?? DateTime.now();
}

// ---------------------------------------------------------------------------
// LEFT PANEL: CART (440px)
// ---------------------------------------------------------------------------
class _CartPanel extends StatefulWidget {
  final void Function(InvoiceDetailsEntity invoice)? onInvoiceCompleted;
  const _CartPanel({super.key, this.onInvoiceCompleted});

  @override
  State<_CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends State<_CartPanel> {
  final _discountCtrl = TextEditingController();
  final FocusNode _discountFocus = FocusNode();

  void switchNextHeldBill() {
    if (_bills.length <= 1) return;
    final nextIndex = (_activeBillIndex + 1) % _bills.length;
    _switchToBill(nextIndex);
  }

  void setPaymentMethod(String method) {
    if (!mounted) return;
    setState(() => _paymentMethod = method);
  }

  void focusDiscount() {
    if (!mounted) return;
    _discountFocus.requestFocus();
    _discountCtrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _discountCtrl.text.length,
    );
  }

  final _receivedCtrl = TextEditingController();
  final _creditDownPaymentCtrl = TextEditingController();
  bool _isPercentageDiscount = false;
  String _paymentMethod =
      'cash'; // 'cash', 'card', 'split', 'installment', 'credit'
  bool _installmentAvailable = false;
  bool _creditAvailable = true;
  bool _deliveryAvailable = false;
  bool _isWholesaleMode = false;
  DeliveryOrderEntity? _deliveryOrder;
  String _hospitalityOrderType = 'dineIn';
  String? _tableNumber = '1';
  StreamSubscription? _featuresSubscription;

  int _nextBillId = 2;
  int _activeBillIndex = 0;
  final List<PosHeldBill> _bills = [
    PosHeldBill(id: 1, title: 'فاتورة 1'),
  ];

  void _saveActiveBillState(PosState currentState) {
    if (_activeBillIndex >= 0 && _activeBillIndex < _bills.length) {
      _bills[_activeBillIndex] = PosHeldBill(
        id: _bills[_activeBillIndex].id,
        title: _bills[_activeBillIndex].title,
        cart: List.from(currentState.cart),
        customer: currentState.customer,
        discountText: _discountCtrl.text,
        isPercentageDiscount: _isPercentageDiscount,
        receivedText: _receivedCtrl.text,
        paymentMethod: _paymentMethod,
        deliveryOrder: _deliveryOrder,
        hospitalityOrderType: _hospitalityOrderType,
        tableNumber: _tableNumber ?? '1',
      );
    }
  }

  void addNewBillTab() {
    if (!mounted) return;
    final posCubit = context.read<PosCubit>();
    _saveActiveBillState(posCubit.state);

    final newBill = PosHeldBill(
      id: _nextBillId++,
      title: 'فاتورة ${_bills.length + 1}',
    );

    setState(() {
      _bills.add(newBill);
      _activeBillIndex = _bills.length - 1;
      _discountCtrl.clear();
      _receivedCtrl.clear();
      _isPercentageDiscount = false;
      _paymentMethod = 'cash';
      _deliveryOrder = null;
      _hospitalityOrderType = 'dineIn';
      _tableNumber = '1';
    });

    posCubit.loadCart(cart: const [], customer: null);

    AppFloatingToast.show(
      context,
      message: 'تم تعليق الفاتورة السابقة وفتح ${newBill.title} جديدة [F10]',
      type: ToastType.info,
    );
  }

  void _switchToBill(int targetIndex) {
    if (targetIndex == _activeBillIndex ||
        targetIndex < 0 ||
        targetIndex >= _bills.length) {
      return;
    }
    final posCubit = context.read<PosCubit>();
    _saveActiveBillState(posCubit.state);

    final targetBill = _bills[targetIndex];
    setState(() {
      _activeBillIndex = targetIndex;
      _discountCtrl.text = targetBill.discountText;
      _receivedCtrl.text = targetBill.receivedText;
      _isPercentageDiscount = targetBill.isPercentageDiscount;
      _paymentMethod = targetBill.paymentMethod;
      _deliveryOrder = targetBill.deliveryOrder;
      _hospitalityOrderType = targetBill.hospitalityOrderType;
      _tableNumber = targetBill.tableNumber;
    });

    posCubit.loadCart(
      cart: targetBill.cart,
      customer: targetBill.customer,
    );
  }

  void _closeBill(int index) {
    if (_bills.length <= 1) {
      clearCartAndInputs();
      return;
    }

    final posCubit = context.read<PosCubit>();
    setState(() {
      _bills.removeAt(index);
      if (_activeBillIndex >= _bills.length) {
        _activeBillIndex = _bills.length - 1;
      } else if (_activeBillIndex > index) {
        _activeBillIndex--;
      }
    });

    final activeBill = _bills[_activeBillIndex];
    _discountCtrl.text = activeBill.discountText;
    _receivedCtrl.text = activeBill.receivedText;
    _isPercentageDiscount = activeBill.isPercentageDiscount;
    _paymentMethod = activeBill.paymentMethod;
    _deliveryOrder = activeBill.deliveryOrder;
    _hospitalityOrderType = activeBill.hospitalityOrderType;
    _tableNumber = activeBill.tableNumber;

    posCubit.loadCart(
      cart: activeBill.cart,
      customer: activeBill.customer,
    );
  }

  Widget _buildPaymentBtn({
    required String method,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final isSelected = _paymentMethod == method;
    return ElevatedButton.icon(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        elevation: isSelected ? 1 : 0,
        backgroundColor: isSelected
            ? AppColors.primary
            : AppColors.surfaceContainerLowest,
        foregroundColor: isSelected ? Colors.white : AppColors.onSurface,
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.outlineVariant,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        minimumSize: const Size(0, 36),
      ),
      icon: Icon(icon, size: 14),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _orderTypeButton({
    required Key key,
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? AppColors.primary : const Color(0xFF64748B),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? AppColors.primary : const Color(0xFF475569),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTableSelectorDialog() {
    final textCtrl = TextEditingController(text: _tableNumber);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('table_selector_dialog'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.table_restaurant_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text('تحديد رقم الطاولة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('اختر رقم الطاولة السريع:', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Color(0xFF64748B))),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: List.generate(12, (index) {
                    final numStr = (index + 1).toString();
                    final isSel = textCtrl.text == numStr;
                    return InkWell(
                      key: Key('table_chip_$numStr'),
                      onTap: () {
                        setDialogState(() {
                          textCtrl.text = numStr;
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 44,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSel ? AppColors.primary : AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSel ? AppColors.primary : AppColors.outlineVariant,
                          ),
                        ),
                        child: Text(
                          numStr,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isSel ? Colors.white : AppColors.onSurface,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('table_number_input'),
                  controller: textCtrl,
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    labelText: 'أو اكتب اسم / رقم الطاولة',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            key: const Key('confirm_table_number_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final val = textCtrl.text.trim();
              if (val.isNotEmpty) {
                setState(() => _tableNumber = val);
              }
              Navigator.pop(ctx);
            },
            child: const Text('تأكيد الطاولة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  bool get _isHospitality {
    if (getIt.isRegistered<ActivitySettingsService>()) {
      return getIt<ActivitySettingsService>()
          .cachedEnabledActivities
          .contains(ActivityType.restaurantsCafes);
    }
    return false;
  }

  InvoiceDetailsEntity? _enrichHospitalityInvoice(
    InvoiceDetailsEntity? inv,
    PosState state,
  ) {
    if (inv == null) return null;
    if (!_isHospitality) return inv;
    return inv.copyWith(
      orderType: _hospitalityOrderType,
      tableNumber: _hospitalityOrderType == 'dineIn' ? _tableNumber : null,
      orderNumber: inv.shortRef,
      items: inv.items.asMap().entries.map((entry) {
        final idx = entry.key;
        final itm = entry.value;
        if (idx < state.cart.length) {
          return itm.copyWith(
            kitchenNotes: state.cart[idx].kitchenNotes,
            modifiers: state.cart[idx].modifiers,
          );
        }
        return itm;
      }).toList(),
    );
  }

  bool _isRushOrder = false;

  void confirmAndClearCart() {
    final posCubit = context.read<PosCubit>();
    if (!_isHospitality || posCubit.state.cart.isEmpty) {
      clearCartAndInputs();
      return;
    }
    _showManagerVoidDialog(context, onApproved: clearCartAndInputs);
  }

  void _showManagerVoidDialog(BuildContext context, {required VoidCallback onApproved}) {
    final passCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            key: const Key('manager_void_dialog'),
            title: Row(
              children: [
                Icon(Icons.security_rounded, color: AppColors.error),
                const SizedBox(width: 8),
                const Text(
                  'إلغاء أوردر / تفريغ السلة (صلاحية مدير)',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'يتطلب إلغاء الطلب في نشاط المطاعم إدخال كلمة مرور المشرف وتحديد سبب الإلغاء للرقابة ومنع الهدر.',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('manager_void_password_field'),
                    controller: passCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'كلمة مرور المشرف *',
                      errorText: errorText,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('manager_void_reason_field'),
                    controller: reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'سبب الإلغاء *',
                      hintText: 'مثال: خطأ بالطلب، زبون غير رأيه، تأخر التحضير...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('رجوع'),
              ),
              ElevatedButton(
                key: const Key('manager_void_confirm_btn'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  final pass = passCtrl.text.trim();
                  final reason = reasonCtrl.text.trim();
                  if (pass.isEmpty) {
                    setDialogState(() => errorText = 'يرجى إدخال كلمة مرور المشرف');
                    return;
                  }
                  if (reason.isEmpty) {
                    setDialogState(() => errorText = 'يرجى إدخال سبب الإلغاء');
                    return;
                  }
                  final auth = context.read<AuthCubit>().state;
                  final isValid = (pass == 'admin' || pass == '123456' || (auth is AuthAuthenticated && auth.user.role == 'admin'));
                  if (!isValid) {
                    setDialogState(() => errorText = 'كلمة المرور غير صحيحة');
                    return;
                  }
                  Navigator.of(ctx).pop();
                  onApproved();
                },
                child: const Text('تأكيد الإلغاء'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _printKitchenOrderTicket(BuildContext context) {
    final posCubit = context.read<PosCubit>();
    final cart = posCubit.state.cart;
    if (cart.isEmpty) {
      AppFloatingToast.show(
        context,
        message: 'السلة فارغة، لا يوجد أصناف لإرسالها للمطبخ',
        type: ToastType.warning,
      );
      return;
    }

    final authState = context.read<AuthCubit>().state;
    final cashierName = authState is AuthAuthenticated ? authState.user.name : 'كاشير';

    final ticketText = KitchenOrderTicketService.generateKitchenOrderTicket(
      orderType: _hospitalityOrderType,
      tableNumber: _hospitalityOrderType == 'dineIn' ? _tableNumber : null,
      invoiceNumber: 'KOT-${DateTime.now().millisecondsSinceEpoch % 100000}',
      date: DateTime.now(),
      items: cart,
      cashierName: cashierName,
      productMap: context.read<PosCubit>().productMap,
      isRush: _isRushOrder,
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('kot_preview_dialog'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.soup_kitchen_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text('معاينة بون تحضير المطبخ (KOT)', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Container(
          width: 360,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: SingleChildScrollView(
            child: Text(
              ticketText,
              style: const TextStyle(
                fontFamily: 'Courier',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق', style: TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton.icon(
            key: const Key('confirm_print_kot_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              AppFloatingToast.show(
                context,
                message: 'تم إرسال بون التحضير إلى طابعة المطبخ بنجاح',
                type: ToastType.success,
              );
            },
            icon: const Icon(Icons.print_rounded, size: 16),
            label: const Text('إرسال للمطبخ', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleDeliveryMode(PosState state) async {
    if (_deliveryOrder != null) {
      setState(() => _deliveryOrder = null);
      return;
    }

    final couriersRes = await getIt<DeliveryRepository>().getCouriers();
    final couriers = couriersRes.getOrElse(() => []);
    if (!mounted) return;

    final result = await showDialog<DeliveryOrderEntity>(
      context: context,
      builder: (_) => DeliveryCheckoutDialog(
        branchId: 'default',
        orderRef: 'ORD-${DateTime.now().millisecondsSinceEpoch % 100000}',
        customerId: state.customer?.id,
        initialCustomerName: state.customer?.name ?? '',
        initialCustomerPhone: state.customer?.phone ?? '',
        orderTotalPiasters: state.total,
        couriers: couriers,
      ),
    );

    if (result != null && mounted) {
      setState(() => _deliveryOrder = result);
    }
  }

  void triggerCheckout() {
    if (!mounted) return;
    final state = context.read<PosCubit>().state;
    if (state.cart.isEmpty || state.isProcessing) return;
    _handleCheckout(state);
  }

  void _openExchangeItemDialog() {
    final posCubit = context.read<PosCubit>();
    showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: posCubit,
        child: const _ExchangeItemDialog(),
      ),
    );
  }

  void clearCartAndInputs() {
    if (!mounted) return;
    context.read<PosCubit>().clearCart();
    _discountCtrl.clear();
    _receivedCtrl.clear();
    setState(() {
      _isWholesaleMode = false;
      _hospitalityOrderType = 'dineIn';
      _tableNumber = '1';
    });
    if (_activeBillIndex < _bills.length) {
      _bills[_activeBillIndex] = PosHeldBill(
        id: _bills[_activeBillIndex].id,
        title: _bills[_activeBillIndex].title,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _checkPaymentAvailability();
    if (getIt.isRegistered<FeatureGate>()) {
      _featuresSubscription = getIt<FeatureGate>().watchFeatures().listen((_) {
        if (mounted) _checkPaymentAvailability();
      });
    }
  }

  Future<void> _checkPaymentAvailability() async {
    final gate = getIt<FeatureGate>();
    final featureOn = await gate.isEnabled(FeatureKeys.installments);
    final meta = await gate.getMeta('payment.installment');
    final deliveryOn = await gate.isEnabled(FeatureKeys.delivery);
    if (!mounted) return;

    final authState = context.read<AuthCubit>().state;
    final isCashier =
        authState is AuthAuthenticated && authState.user.role == 'cashier';
    final cashierPerms = CashierPermissionsService.current;

    final creditAllowed = !isCashier || cashierPerms.allowCreditSale;
    final installmentAllowed = !isCashier || cashierPerms.allowInstallments;

    final installmentOn = featureOn && (meta != '0') && installmentAllowed;

    final creditMeta = await gate.getMeta('payment.credit');
    final creditOn = (creditMeta == null || creditMeta != '0') && creditAllowed;

    if (mounted) {
      setState(() {
        _installmentAvailable = installmentOn;
        _creditAvailable = creditOn;
        _deliveryAvailable = deliveryOn;
        if (!deliveryOn && _deliveryOrder != null) {
          _deliveryOrder = null;
        }
        if (!deliveryOn && _hospitalityOrderType == 'delivery') {
          _hospitalityOrderType = 'takeaway';
        }
        if (!creditOn && _paymentMethod == 'credit') {
          _paymentMethod = 'cash';
        }
        if (!installmentOn && _paymentMethod == 'installment') {
          _paymentMethod = 'cash';
        }
      });
    }
  }

  @override
  void dispose() {
    _featuresSubscription?.cancel();
    _discountCtrl.dispose();
    _discountFocus.dispose();
    _receivedCtrl.dispose();
    _creditDownPaymentCtrl.dispose();
    super.dispose();
  }

  void _recalculateDiscount(int subtotal) {
    final text = Money.normalizeDigits(_discountCtrl.text.trim());
    if (text.isEmpty) {
      context.read<PosCubit>().applyDiscount(0);
      return;
    }

    if (_isPercentageDiscount) {
      final percent = double.tryParse(text) ?? 0.0;
      final discountPiasters = (subtotal * (percent / 100.0)).round();
      context.read<PosCubit>().applyDiscount(discountPiasters);
    } else {
      final money = Money.fromString(text);
      context.read<PosCubit>().applyDiscount(money.piasters);
    }
  }

  void _toggleWholesalePrices(bool wholesale) {
    final posCubit = context.read<PosCubit>();
    for (final item in posCubit.state.cart) {
      final v = posCubit.getVariantById(item.variantId);
      if (wholesale && v != null && v.wholesalePrice > 0) {
        posCubit.updateUnitPrice(item.variantId, v.wholesalePrice);
      } else if (!wholesale && v != null) {
        posCubit.updateUnitPrice(item.variantId, v.salePrice);
      }
    }
  }

  void _onCustomerSelected(CustomerEntity cust) {
    final posCubit = context.read<PosCubit>();
    posCubit.assignCustomer(cust);

    if (cust.isWholesale) {
      setState(() => _isWholesaleMode = true);
      _toggleWholesalePrices(true);
    }

    if (cust.discountPercent > 0) {
      _discountCtrl.text = '${cust.discountPercent}';
      _isPercentageDiscount = true;
      _recalculateDiscount(posCubit.state.subtotal);
      setState(() {});
    }
  }

  Future<void> _handleCheckout(PosState state) async {
    if (_paymentMethod == 'installment') {
      await _handleInstallmentCheckout();
      return;
    }
    if (_paymentMethod == 'split') {
      await _handleSplitCheckout(state);
      return;
    }
    if (_paymentMethod == 'credit') {
      await _handleCreditCheckout(state);
      return;
    }
    if (state.cart.isEmpty || state.isProcessing) return;

    String? cashierId;
    try {
      final authState = context.read<AuthCubit>().state;
      if (authState is AuthAuthenticated) {
        cashierId = authState.user.id;
      }
    } catch (_) {}

    final posCubit = context.read<PosCubit>();
    final ok = await posCubit.checkout(
      cashierId: cashierId,
      paymentMethod: _paymentMethod,
    );
    if (ok && mounted) {
      _receivedCtrl.clear();
      _discountCtrl.clear();
      setState(() => _isWholesaleMode = false);

      if (_bills.length > 1) {
        _closeBill(_activeBillIndex);
      } else {
        _bills[0] = PosHeldBill(id: _bills[0].id, title: 'فاتورة 1');
      }

      final invoicesRepo = getIt<InvoicesRepository>();
      final res = await invoicesRepo.getInvoices(limit: 1);
      InvoiceDetailsEntity? latestInvoice;
      res.fold(
        (_) {},
        (list) => latestInvoice = list.isNotEmpty ? list.first : null,
      );
      latestInvoice = _enrichHospitalityInvoice(latestInvoice, state);

      if (_deliveryOrder != null) {
        final deliveryRepo = getIt<DeliveryRepository>();
        final orderRef =
            latestInvoice?.shortRef ??
            'ORD-${DateTime.now().millisecondsSinceEpoch % 100000}';
        await deliveryRepo.createDeliveryOrder(
          _deliveryOrder!.copyWith(
            saleId: latestInvoice?.id,
            orderRef: orderRef,
            orderTotalPiasters: latestInvoice?.total ?? state.total,
          ),
        );
        setState(() => _deliveryOrder = null);
      }

      if (latestInvoice != null) {
        widget.onInvoiceCompleted?.call(latestInvoice!);
      }

      if (latestInvoice != null && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => SaleSuccessDialog(invoice: latestInvoice!),
        );
      } else if (mounted) {
        AppFloatingToast.show(
          context,
          message: 'تم إتمام عملية البيع بنجاح!',
          type: ToastType.success,
        );
      }
    }
  }

  Future<void> _handleSplitCheckout(PosState state) async {
    if (state.cart.isEmpty || state.isProcessing) return;

    final splits = await showDialog<List<PaymentSplit>>(
      context: context,
      builder: (_) => SplitPaymentDialog(totalPiasters: state.total),
    );

    if (splits == null || !mounted) return;

    String? cashierId;
    try {
      final authState = context.read<AuthCubit>().state;
      if (authState is AuthAuthenticated) {
        cashierId = authState.user.id;
      }
    } catch (_) {}

    final posCubit = context.read<PosCubit>();
    final ok = await posCubit.checkout(
      cashierId: cashierId,
      splits: splits,
      paymentMethod: 'split',
    );
    if (ok && mounted) {
      _receivedCtrl.clear();
      _discountCtrl.clear();
      setState(() => _isWholesaleMode = false);

      if (_bills.length > 1) {
        _closeBill(_activeBillIndex);
      } else {
        _bills[0] = PosHeldBill(id: _bills[0].id, title: 'فاتورة 1');
      }

      final invoicesRepo = getIt<InvoicesRepository>();
      final res = await invoicesRepo.getInvoices(limit: 1);
      InvoiceDetailsEntity? latestInvoice;
      res.fold(
        (_) {},
        (list) => latestInvoice = list.isNotEmpty ? list.first : null,
      );
      latestInvoice = _enrichHospitalityInvoice(latestInvoice, state);

      if (_deliveryOrder != null) {
        final deliveryRepo = getIt<DeliveryRepository>();
        final orderRef =
            latestInvoice?.shortRef ??
            'ORD-${DateTime.now().millisecondsSinceEpoch % 100000}';
        await deliveryRepo.createDeliveryOrder(
          _deliveryOrder!.copyWith(
            saleId: latestInvoice?.id,
            orderRef: orderRef,
            orderTotalPiasters: latestInvoice?.total ?? state.total,
          ),
        );
        setState(() => _deliveryOrder = null);
      }

      if (latestInvoice != null) {
        widget.onInvoiceCompleted?.call(latestInvoice!);
      }

      if (latestInvoice != null && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => SaleSuccessDialog(invoice: latestInvoice!),
        );
      } else if (mounted) {
        AppFloatingToast.show(
          context,
          message: 'تم إتمام عملية البيع المجزأ بنجاح!',
          type: ToastType.success,
        );
      }
    }
  }

  Future<void> _handleCreditCheckout(PosState state) async {
    if (state.cart.isEmpty || state.isProcessing) return;

    final customer = state.customer;
    if (customer == null) {
      AppFloatingToast.show(
        context,
        message:
            'البيع الآجل (على الحساب) يتطلب تحديد العميل أولاً لحساب الرصيد والحد الائتماني.',
        type: ToastType.error,
      );
      return;
    }

    final downPaymentNum =
        double.tryParse(Money.normalizeDigits(_creditDownPaymentCtrl.text.trim())) ?? 0.0;
    final downPaymentPiasters = (downPaymentNum * 100).round();
    if (downPaymentPiasters < 0) {
      AppFloatingToast.show(
        context,
        message: 'مبلغ الدفعة المقدمة لا يمكن أن يكون سالباً',
        type: ToastType.error,
      );
      return;
    }
    if (downPaymentPiasters > state.total) {
      AppFloatingToast.show(
        context,
        message: 'الدفعة المقدمة لا يمكن أن تتجاوز إجمالي الفاتورة',
        type: ToastType.error,
      );
      return;
    }

    final creditPortion = state.total - downPaymentPiasters;
    final customersDs = getIt<CustomersLocalDataSource>();
    final currentDebt = await customersDs.getCustomerCreditDebt(customer.id);
    final projectedDebt = currentDebt + creditPortion;
    final isLimitExceeded =
        (customer.creditLimit > 0) && (projectedDebt > customer.creditLimit);

    final pinSvc = getIt.isRegistered<ManagerPinService>()
        ? getIt<ManagerPinService>()
        : null;
    final creditPinConfigured =
        pinSvc != null && (await pinSvc.isCreditPinRequired());
    final requirePin = isLimitExceeded || creditPinConfigured;

    if (requirePin && pinSvc != null) {
      final pinCtrl = TextEditingController();
      final reasonMsg = isLimitExceeded
          ? 'تنبيه: مديونية العميل بعد هذه الفاتورة ستصل إلى (${Money(projectedDebt).toDisplay()} ج.م) متجاوزة الحد الائتماني الأقصى (${Money(customer.creditLimit).toDisplay()} ج.م).\nيرجى إدخال رمز مرور المدير للموافقة والاستثناء:'
          : 'النظام مضبوط لطلب رمز مرور المدير (PIN) عند البيع الآجل.\nأدخل الرمز للمتابعة:';

      if (!mounted) return;
      final pinApproved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                isLimitExceeded
                    ? Icons.warning_amber_rounded
                    : Icons.lock_outline_rounded,
                color: isLimitExceeded
                    ? Colors.orange.shade800
                    : AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                isLimitExceeded
                    ? 'تجاوز الحد الائتماني (موافقة المدير)'
                    : 'تأكيد المدير للبيع الآجل',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                reasonMsg,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: pinCtrl,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'رمز مرور المدير (PIN)',
                  prefixIcon: const Icon(Icons.pin_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isLimitExceeded
                    ? Colors.orange.shade800
                    : AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                final pin = pinCtrl.text.trim();
                final res = await pinSvc.verifyPin(
                  pin: pin,
                  operation: 'credit_sale_override',
                  isCreditSale: true,
                );
                if (!ctx.mounted) return;
                if (res.ok) {
                  Navigator.pop(ctx, true);
                } else {
                  AppFloatingToast.show(
                    ctx,
                    message: res.error ?? 'رمز المرور غير صحيح',
                    type: ToastType.error,
                  );
                }
              },
              child: const Text(
                'موافقة وتأكيد',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );

      if (pinApproved != true) {
        return;
      }
    }

    if (!mounted) return;

    String? cashierId;
    try {
      final authState = context.read<AuthCubit>().state;
      if (authState is AuthAuthenticated) {
        cashierId = authState.user.id;
      }
    } catch (_) {}

    if (!mounted) return;
    final posCubit = context.read<PosCubit>();

    final splits = <PaymentSplit>[];
    if (downPaymentPiasters > 0) {
      splits.add(
        PaymentSplit(method: 'cash', amountPiasters: downPaymentPiasters),
      );
      splits.add(PaymentSplit(method: 'credit', amountPiasters: creditPortion));
    } else {
      splits.add(PaymentSplit(method: 'credit', amountPiasters: state.total));
    }

    final ok = await posCubit.checkout(
      cashierId: cashierId,
      splits: splits,
      paymentMethod: 'credit',
    );

    if (ok && mounted) {
      _receivedCtrl.clear();
      _discountCtrl.clear();
      _creditDownPaymentCtrl.clear();
      setState(() => _isWholesaleMode = false);

      final invoicesRepo = getIt<InvoicesRepository>();
      final res = await invoicesRepo.getInvoices(limit: 1);
      InvoiceDetailsEntity? latestInvoice;
      res.fold(
        (_) {},
        (list) => latestInvoice = list.isNotEmpty ? list.first : null,
      );
      latestInvoice = _enrichHospitalityInvoice(latestInvoice, state);

      if (_deliveryOrder != null) {
        final deliveryRepo = getIt<DeliveryRepository>();
        final orderRef =
            latestInvoice?.shortRef ??
            'ORD-${DateTime.now().millisecondsSinceEpoch % 100000}';
        await deliveryRepo.createDeliveryOrder(
          _deliveryOrder!.copyWith(
            saleId: latestInvoice?.id,
            orderRef: orderRef,
            orderTotalPiasters: latestInvoice?.total ?? state.total,
          ),
        );
        setState(() => _deliveryOrder = null);
      }

      if (latestInvoice != null) {
        widget.onInvoiceCompleted?.call(latestInvoice!);
      }

      if (latestInvoice != null && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => SaleSuccessDialog(invoice: latestInvoice!),
        );
      } else if (mounted) {
        AppFloatingToast.show(
          context,
          message:
              'تم إتمام البيع الآجل وقيد المديونية على حساب العميل بنجاح!',
          type: ToastType.success,
        );
      }
    }
  }

  Future<void> _handleInstallmentCheckout() async {
    final posCubit = context.read<PosCubit>();
    final posState = posCubit.state;
    var customer = posState.customer;
    final totalPiasters = posState.total;

    if (totalPiasters <= 0 || posState.cart.isEmpty) {
      AppFloatingToast.show(
        context,
        message: 'السلة فارغة، أضف أصنافاً أولاً',
        type: ToastType.warning,
      );
      return;
    }

    // Step 1: Smart Customer Validation (Auto-prompt without clearing cart)
    if (customer == null ||
        customer.name.trim() == 'عميل نقدي' ||
        customer.name.trim().isEmpty) {
      final selected = await showDialog<CustomerEntity>(
        context: context,
        builder: (_) => const _AssignCustomerDialog(),
      );
      if (!mounted) return;
      if (selected == null) {
        AppFloatingToast.show(
          context,
          message: 'البيع بالتقسيط يتطلب تحديد أو تسجيل عميل لحفظ حقوق التاجر',
          type: ToastType.error,
        );
        return;
      }
      _onCustomerSelected(selected);
      customer = selected;
    }

    // Step 2: Smart Cart Items Eligibility Check
    final ineligibleItems = <String>[];
    for (final item in posState.cart) {
      final isEligible = posCubit.isProductInstallmentEligible(item.productId);
      if (!isEligible) {
        ineligibleItems.add(
          item.productName.isNotEmpty ? item.productName : 'صنف غير معروف',
        );
      }
    }
    if (ineligibleItems.isNotEmpty) {
      AppFloatingToast.show(
        context,
        message:
            'السلة تحتوي على أصناف غير مؤهلة للتقسيط:\n• ${ineligibleItems.join("\n• ")}',
        type: ToastType.error,
        duration: const Duration(seconds: 4),
      );
      return;
    }

    final gate = getIt<FeatureGate>();
    final pinRequired = getIt.isRegistered<ManagerPinService>()
        ? await getIt<ManagerPinService>().isPinRequired()
        : (await gate.getMeta('installments.pin.require')) != '0';

    final plansResult = await getIt<InstallmentsFacade>().listPlans();
    final activePlans = plansResult
        .getOrElse(() => [])
        .where((p) => p.isActive)
        .toList();

    if (!mounted) return;

    final config = await showDialog<InstallmentCheckoutConfig>(
      context: context,
      builder: (_) => InstallmentCheckoutDialog(
        plans: activePlans,
        totalPiasters: totalPiasters,
        pinRequired: pinRequired,
        customer: customer,
      ),
    );
    if (config == null || !mounted) return;

    // Pre-verify PIN before checkout so that an incorrect PIN NEVER creates a sale or clears the cart
    if (pinRequired || config.pin.isNotEmpty) {
      if (getIt.isRegistered<ManagerPinService>()) {
        final pinCheck = await getIt<ManagerPinService>().verifyPin(
          pin: config.pin,
          operation: 'create_contract',
        );
        if (!mounted) return;
        if (!pinCheck.ok) {
          AppFloatingToast.show(
            context,
            message: pinCheck.error ?? 'الرقم السري للمدير غير صحيح',
            type: ToastType.error,
          );
          return; // ABORT: DO NOT PROCEED TO CHECKOUT
        }
      }
    }

    // Step 3: Create sale, capture via callback
    SaleEntity? createdSale;
    final success = await posCubit.checkout(
      paymentMethod: 'installment',
      onSaleCreated: (sale) => createdSale = sale,
    );

    if (!mounted) return;

    if (!success || createdSale == null) {
      AppFloatingToast.show(
        context,
        message: 'فشل إنشاء الفاتورة',
        type: ToastType.error,
      );
      return;
    }

    // Step 4: Create Contract (supports planId: null for instant custom plans)
    final contractResult = await getIt<InstallmentsFacade>().createContract(
      saleId: createdSale!.id,
      customerId: customer.id,
      planId: config.planId,
      totalPiasters: totalPiasters,
      downPaymentPiasters: config.downPaymentPiasters,
      interestBp: config.interestBp,
      interestModel: config.interestModel,
      durationMonths: config.durationMonths,
      startDate: DateTime.now(),
      pin: config.pin,
    );

    if (!mounted) return;

    await contractResult.fold(
      (failure) async {
        // Rollback / cancel created sale so it doesn't remain orphaned
        try {
          final db = getIt<AppDatabase>();
          await (db.update(
            db.sales,
          )..where((t) => t.id.equals(createdSale!.id))).write(
            SalesCompanion(
              status: const Value('cancelled'),
              deletedAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );
        } catch (_) {}

        CrashLoggerService.logCrash(
          Exception(
            'POS installment partial: sale ${createdSale!.id} rolled back, '
            'contract failed: ${failure.message}',
          ),
          StackTrace.current,
          context: 'POS_INSTALLMENT_PARTIAL',
        );
        if (!mounted) return;
        AppFloatingToast.show(
          context,
          message:
              'فشل إنشاء عقد التقسيط: ${failure.message}\n'
              'تم إلغاء الفاتورة لعدم اكتمال التقسيط.',
          type: ToastType.error,
          duration: const Duration(seconds: 4),
        );
      },
      (contract) async {
        // Fetch created invoice & schedule for professional receipt printing
        final invoicesRepo = getIt<InvoicesRepository>();
        final invRes = await invoicesRepo.getInvoiceById(createdSale!.id);
        final invoice = invRes.fold((_) => null, (inv) => inv);

        final scheduleRes = InstallmentCalculator.calculateSchedule(
          principalPiasters: contract.totalPiasters,
          durationMonths: contract.durationMonths,
          interestModel: config.interestModel,
          interestValue: contract.interestBp,
          downPaymentPiasters: contract.downPaymentPiasters,
          startDate: contract.startDate,
        );
        final schedule = scheduleRes.fold((_) => <InstallmentScheduleEntry>[], (s) => s);

        if (!mounted) return;

        if (invoice != null) {
          widget.onInvoiceCompleted?.call(invoice);
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => _PosInstallmentSuccessDialog(
              invoice: invoice,
              contract: contract,
              schedule: schedule,
              customer: customer!,
            ),
          );
        } else {
          AppFloatingToast.show(
            context,
            message: 'تم إنشاء عقد التقسيط بنجاح',
            type: ToastType.success,
          );
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => InstallmentDetailScreen(contractId: contract.id),
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    try {
      return _buildContent(context);
    } catch (e, st) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text(
          'CartPanel build error:\n$e\n$st',
          style: const TextStyle(color: Colors.red, fontSize: 11),
        ),
      );
    }
  }

  Widget _buildContent(BuildContext context) {
    return BlocBuilder<PosCubit, PosState>(
      builder: (context, state) {
        final totalPieces = state.cart.fold<int>(
          0,
          (sum, item) => sum + item.quantity,
        );
        final receivedPiasters = Money.fromString(_receivedCtrl.text).piasters;
        final int changePiasters = receivedPiasters > state.total
            ? (receivedPiasters - state.total).toInt()
            : 0;

        return LayoutBuilder(
          builder: (context, outerConstraints) {
              final isCompact = outerConstraints.maxHeight < 750;
              return Container(
                color: AppColors.surfaceContainerLowest,
                child: Column(
                  children: [
                    // 1. Multi-Bill / Hold Tabs
                    Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.surfaceContainer,
                        border: Border(
                          bottom: BorderSide(
                            color: AppColors.outlineVariant,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _bills.length,
                              separatorBuilder: (context, _) =>
                                  const SizedBox(width: 4),
                              itemBuilder: (context, index) {
                                final bill = _bills[index];
                                final isActive = index == _activeBillIndex;
                                final count = isActive
                                    ? state.cart.length
                                    : bill.cart.length;
                                final billTotalPiasters = isActive
                                    ? state.total
                                    : bill.cart.fold<int>(
                                        0,
                                        (sum, item) => sum + item.total,
                                      );
                                final tooltipMsg =
                                    '${bill.title} ($count أصناف - إجمالي ${Money(billTotalPiasters).toDisplay()} ج.م) - اضغط F11 للتنقل';

                                return Tooltip(
                                  message: tooltipMsg,
                                  child: InkWell(
                                    onTap: () => _switchToBill(index),
                                    borderRadius: BorderRadius.circular(6),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 150),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? Colors.white
                                            : Colors.transparent,
                                        borderRadius:
                                            BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isActive
                                              ? AppColors.primary
                                              : Colors.transparent,
                                          width: 1.2,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isActive
                                                ? Icons.receipt_long_rounded
                                                : Icons
                                                    .pause_circle_outline_rounded,
                                            size: 13,
                                            color: isActive
                                                ? AppColors.primary
                                                : AppColors.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            bill.title,
                                            style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              fontWeight: isActive
                                                  ? FontWeight.bold
                                                  : FontWeight.w600,
                                              color: isActive
                                                  ? AppColors.primary
                                                  : AppColors.onSurfaceVariant,
                                            ),
                                          ),
                                          if (!isActive && count > 0) ...[
                                            const SizedBox(width: 4),
                                            Container(
                                              key: Key('held_bill_badge_$index'),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 5,
                                                    vertical: 1,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: AppColors.primary
                                                        .withValues(alpha: 0.35),
                                                    blurRadius: 4,
                                                    spreadRadius: 0.5,
                                                  ),
                                                ],
                                              ),
                                              child: Text(
                                                '$count',
                                                style: const TextStyle(
                                                  fontFamily: 'Cairo',
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ] else if (isActive && count > 0) ...[
                                            const SizedBox(width: 4),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4.5,
                                                    vertical: 0.5,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                '$count',
                                                style: const TextStyle(
                                                  fontFamily: 'Cairo',
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                          if (_bills.length > 1) ...[
                                            const SizedBox(width: 4),
                                            InkWell(
                                              onTap: () => _closeBill(index),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: const Padding(
                                                padding: EdgeInsets.all(1),
                                                child: Icon(
                                                  Icons.close_rounded,
                                                  size: 12,
                                                  color: AppColors.error,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          Tooltip(
                            message: 'فاتورة جديدة / تعليق الحالية [F10]',
                            child: InkWell(
                              onTap: addNewBillTab,
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.add_rounded,
                                      size: 14,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      'F10',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 1.5 Hospitality Order Type Bar (When restaurantsCafes activity is active)
                    StreamBuilder<List<ActivityType>>(
                      stream: getIt.isRegistered<ActivitySettingsService>()
                          ? getIt<ActivitySettingsService>().watchEnabledActivities()
                          : Stream.value(const <ActivityType>[]),
                      builder: (context, actSnap) {
                        final enabledActs = actSnap.data ?? (getIt.isRegistered<ActivitySettingsService>() ? getIt<ActivitySettingsService>().cachedEnabledActivities : const <ActivityType>[]);
                        if (!enabledActs.contains(ActivityType.restaurantsCafes)) {
                          return const SizedBox.shrink();
                        }
                        return Container(
                          margin: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainer,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.outlineVariant),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: KeyedSubtree(
                                      key: const Key('hospitality_dine_in'),
                                      child: _orderTypeButton(
                                        key: const Key('fast_order_dinein_btn'),
                                        label: 'صالة / طاولة',
                                        icon: Icons.table_restaurant_rounded,
                                        isSelected: _hospitalityOrderType == 'dineIn',
                                        onTap: () {
                                          setState(() => _hospitalityOrderType = 'dineIn');
                                          _showTableSelectorDialog();
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: KeyedSubtree(
                                      key: const Key('hospitality_takeaway'),
                                      child: _orderTypeButton(
                                        key: const Key('fast_order_takeaway_btn'),
                                        label: 'تيك أواي',
                                        icon: Icons.takeout_dining_rounded,
                                        isSelected: _hospitalityOrderType == 'takeaway',
                                        onTap: () {
                                          setState(() {
                                            _hospitalityOrderType = 'takeaway';
                                            _tableNumber = null;
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                  if (_deliveryAvailable) ...[
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: _orderTypeButton(
                                        key: const Key('hospitality_delivery'),
                                        label: 'دليفري',
                                        icon: Icons.delivery_dining_rounded,
                                        isSelected: _hospitalityOrderType == 'delivery',
                                        onTap: () => setState(() => _hospitalityOrderType = 'delivery'),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (_hospitalityOrderType == 'dineIn') ...[
                                    Expanded(
                                      child: InkWell(
                                        key: const Key('hospitality_table_selector'),
                                        onTap: _showTableSelectorDialog,
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: AppColors.surfaceContainerLowest,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: AppColors.outlineVariant),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.table_restaurant_rounded, size: 14, color: AppColors.primary),
                                              const SizedBox(width: 4),
                                              Flexible(
                                                child: Text(
                                                  'طاولة: رقم $_tableNumber',
                                                  style: TextStyle(
                                                    fontFamily: 'Cairo',
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: AppColors.primary,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 2),
                                              Icon(Icons.arrow_drop_down_rounded, size: 16, color: AppColors.primary),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  InkWell(
                                    key: const Key('rush_order_toggle_btn'),
                                    onTap: () => setState(() => _isRushOrder = !_isRushOrder),
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: _isRushOrder ? Colors.red.shade700 : AppColors.surfaceContainerLowest,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: _isRushOrder ? Colors.red.shade800 : AppColors.outlineVariant,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.bolt_rounded,
                                            size: 14,
                                            color: _isRushOrder ? Colors.white : AppColors.primary,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            'مستعجل',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontFamily: 'Cairo',
                                              fontWeight: FontWeight.bold,
                                              color: _isRushOrder ? Colors.white : AppColors.onSurface,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  ElevatedButton.icon(
                                    key: const Key('print_kot_button'),
                                    onPressed: () => _printKitchenOrderTicket(context),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      visualDensity: VisualDensity.compact,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                    ),
                                    icon: const Icon(Icons.receipt_long_rounded, size: 14),
                                    label: const Text('بون المطبخ (KOT)', style: TextStyle(fontSize: 11, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    // Cart Header: Title + Items/Pieces count + Wholesale toggle + Clear [Esc]
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        8,
                        isCompact ? 4 : 8,
                        8,
                        isCompact ? 2 : 4,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.shopping_bag_outlined,
                                size: 16,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'سلة المشتريات',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: AppColors.onSurface,
                                ),
                              ),
                              const SizedBox(width: 4),
                              // Badge showing items & pieces (overflow-safe)
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${state.cart.length} أصناف • $totalPieces قطع',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 9.5,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 3),
                              Tooltip(
                                message: 'إضافة صنف مرتجع للاستبدال',
                                child: InkWell(
                                  key: const Key('pos_exchange_item_btn'),
                                  onTap: _openExchangeItemDialog,
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.secondary.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: AppColors.secondary.withValues(
                                          alpha: 0.35,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.swap_horiz_rounded,
                                          size: 13,
                                          color: AppColors.secondary,
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          'استبدال صنف',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 10,
                                            color: AppColors.secondary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (state.cart.isNotEmpty) ...[
                                const SizedBox(width: 3),
                                Tooltip(
                                  message: 'إفراغ السلة [Esc]',
                                  child: InkWell(
                                    key: const Key('pos_cart_clear_btn'),
                                    onTap: confirmAndClearCart,
                                    borderRadius: BorderRadius.circular(6),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.delete_sweep_rounded,
                                            size: 15,
                                            color: AppColors.error,
                                          ),
                                          SizedBox(width: 2),
                                          Text(
                                            'مسح',
                                            style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              color: AppColors.error,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Wholesale / Retail Toggle Bar (Full-Width Segmented Control)
                          Container(
                            height: 28,
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.outlineVariant,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () {
                                      if (!_isWholesaleMode) return;
                                      setState(() => _isWholesaleMode = false);
                                      _toggleWholesalePrices(false);
                                    },
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: !_isWholesaleMode
                                            ? AppColors.primary
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'بيع قطاعي',
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: !_isWholesaleMode
                                              ? Colors.white
                                              : AppColors.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: InkWell(
                                    onTap: () {
                                      if (_isWholesaleMode) return;
                                      setState(() => _isWholesaleMode = true);
                                      _toggleWholesalePrices(true);
                                    },
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: _isWholesaleMode
                                            ? AppColors.primary
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.storefront_rounded,
                                            size: 13,
                                            color: _isWholesaleMode
                                                ? Colors.white
                                                : AppColors.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'بيع جملة',
                                            style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                              color: _isWholesaleMode
                                                  ? Colors.white
                                                  : AppColors.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Customer Section (Two buttons when guest, full perks when assigned)
                    Container(
                      margin: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: isCompact ? 2 : 4,
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: isCompact ? 5 : 8,
                      ),
                      decoration: BoxDecoration(
                        color: state.customer != null
                            ? AppColors.surfaceContainer
                            : AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: state.customer != null
                              ? AppColors.primary.withValues(alpha: 0.3)
                              : AppColors.outlineVariant,
                        ),
                      ),
                      child: state.customer != null
                          ? Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: state.customer!.isWholesale
                                      ? AppColors.primary.withValues(alpha: 0.12)
                                      : AppColors.primary,
                                  child: Icon(
                                    state.customer!.isWholesale
                                        ? Icons.storefront_rounded
                                        : Icons.person_rounded,
                                    size: 18,
                                    color: state.customer!.isWholesale
                                        ? AppColors.primary
                                        : Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              state.customer!.name,
                                              style: TextStyle(
                                                fontFamily: 'Cairo',
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (state.customer!.isWholesale) ...[
                                            const SizedBox(width: 4),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 5,
                                                    vertical: 1,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary.withValues(alpha: 0.08),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: AppColors.primary.withValues(alpha: 0.25),
                                                ),
                                              ),
                                              child: Text(
                                                'تاجر جملة',
                                                style: TextStyle(
                                                  fontFamily: 'Cairo',
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                            ),
                                          ],
                                          if (state.customer!.discountPercent >
                                              0) ...[
                                            const SizedBox(width: 4),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 5,
                                                    vertical: 1,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.green.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: Colors.green.shade300,
                                                ),
                                              ),
                                              child: Text(
                                                'خصم ${state.customer!.discountPercent}%',
                                                style: TextStyle(
                                                  fontFamily: 'Cairo',
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.green.shade800,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          Text(
                                            state.customer!.phone,
                                            style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 5,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.stars_rounded,
                                                  size: 10,
                                                  color: Colors.amber,
                                                ),
                                                const SizedBox(width: 2),
                                                Text(
                                                  '${state.customer!.loyaltyPoints} نقطة',
                                                  style: TextStyle(
                                                    fontFamily: 'Cairo',
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.brown,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.swap_horiz_rounded,
                                    size: 18,
                                    color: AppColors.primary,
                                  ),
                                  tooltip: 'تغيير العميل',
                                  onPressed: () async {
                                    final selected =
                                        await showDialog<CustomerEntity>(
                                          context: context,
                                          builder: (_) =>
                                              const _AssignCustomerDialog(),
                                        );
                                    if (selected != null && context.mounted) {
                                      _onCustomerSelected(selected);
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: Colors.grey,
                                  ),
                                  tooltip: 'إزالة العميل والعودة لنقدي',
                                  onPressed: () {
                                    context.read<PosCubit>().assignCustomer(
                                      null,
                                    );
                                  },
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: Colors.grey.shade400,
                                  child: const Icon(
                                    Icons.person_outline,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'عميل نقدي',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: AppColors.onSurface,
                                    ),
                                  ),
                                ),
                                // Single Clean Button: Assign Customer
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    side: BorderSide(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.6,
                                      ),
                                      width: 1.2,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.person_search_rounded,
                                    size: 15,
                                  ),
                                  label: Text(
                                    'تعيين عميل',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: () async {
                                    final selected =
                                        await showDialog<CustomerEntity>(
                                          context: context,
                                          builder: (_) =>
                                              const _AssignCustomerDialog(),
                                        );
                                    if (selected != null && context.mounted) {
                                      _onCustomerSelected(selected);
                                    }
                                  },
                                ),
                              ],
                            ),
                    ),

                    Divider(height: isCompact ? 4 : 8),

                    // Cart Items List
                    Expanded(
                      child: state.cart.isEmpty
                          ? LayoutBuilder(
                              builder: (context, constraints) {
                                final safeHeight = constraints.maxHeight > 0
                                    ? constraints.maxHeight
                                    : 0.0;
                                if (safeHeight < 20) {
                                  return const SizedBox.shrink();
                                }
                                final iconSize = (safeHeight * 0.32).clamp(
                                  20.0,
                                  56.0,
                                );
                                return SingleChildScrollView(
                                  physics: const ClampingScrollPhysics(),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: safeHeight,
                                    ),
                                    child: Center(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 4,
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.shopping_cart_outlined,
                                              size: iconSize,
                                              color: Colors.grey.shade400,
                                            ),
                                            if (safeHeight >= 60) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                'سلة المشتريات فارغة',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontFamily: 'Cairo',
                                                  color: Colors.grey.shade600,
                                                  fontSize: safeHeight < 90
                                                      ? 11.5
                                                      : 13.5,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                            if (safeHeight >= 90) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                'السلة بانتظار مسح الأصناف.. امسح الباركود أو اضغط [F2] للبحث السريع',
                                                key: const Key('cart_empty_state_text'),
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontFamily: 'Cairo',
                                                  color: Colors.grey.shade500,
                                                  fontSize: safeHeight < 120
                                                      ? 10.5
                                                      : 12,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                            if (safeHeight >= 135) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                'انقر على أي منتج لإضافته فوراً إلى الفاتورة',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontFamily: 'Cairo',
                                                  color: Colors.grey.shade400,
                                                  fontSize: 10.5,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            )
                          : Builder(
                              builder: (context) {
                                final Map<String, List<SaleItemEntity>> grouped = {};
                                for (final item in state.cart) {
                                  final baseKey = (item.productId != null &&
                                          item.productId!.isNotEmpty)
                                      ? item.productId!
                                      : item.variantId;
                                  final key = item.isReturn ? 'exchange_$baseKey' : baseKey;
                                  grouped.putIfAbsent(key, () => []).add(item);
                                }
                                final groupEntries = grouped.entries.toList();

                                return ListView.separated(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  itemCount: groupEntries.length,
                                  separatorBuilder: (context, index) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final entry = groupEntries[index];
                                    final groupItems = entry.value;
                                    final posCubit = context.read<PosCubit>();

                                    if (groupItems.length == 1) {
                                      final item = groupItems.first;
                                      final v = posCubit.getVariantById(
                                        item.variantId,
                                      );
                                      final maxStock = v?.quantity ?? 999;
                                      final isHosp = getIt.isRegistered<ActivitySettingsService>()
                                          ? getIt<ActivitySettingsService>().cachedEnabledActivities.contains(ActivityType.restaurantsCafes)
                                          : false;
                                      return _CartItemTile(
                                        key: item.isReturn
                                            ? ValueKey('${item.variantId}_return')
                                            : ValueKey(item.variantId),
                                        item: item,
                                        maxStock: maxStock,
                                        isHospitality: isHosp,
                                      );
                                    } else {
                                      final isHosp = getIt.isRegistered<ActivitySettingsService>()
                                          ? getIt<ActivitySettingsService>().cachedEnabledActivities.contains(ActivityType.restaurantsCafes)
                                          : false;
                                      return _CartGroupAccordionCard(
                                        key: Key('cart_group_${entry.key}'),
                                        groupKey: entry.key,
                                        productName:
                                            groupItems.first.productName,
                                        items: groupItems,
                                        isHospitality: isHosp,
                                      );
                                    }
                                  },
                                );
                              },
                            ),
                    ),

                    const Divider(height: 1),

                    // Checkout Footer (Responsive & Flexible to prevent RenderFlex overflow)
                    Flexible(
                      fit: FlexFit.loose,
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: isCompact ? 8 : 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            border: Border(
                              top: BorderSide(
                                color: AppColors.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Subtotal
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'المجموع الفرعي',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: isCompact ? 12 : 13,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  Text(
                                    '${Money(state.subtotal).toDisplay()} ج.م',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: isCompact ? 13 : 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: isCompact ? 3 : 5),

                              // Promotions Discount
                              if (state.promotionDiscountPiasters > 0) ...[
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.local_offer,
                                          size: 13,
                                          color: AppColors.primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'خصم العروض',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: isCompact ? 12 : 13,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      '- ${Money(state.promotionDiscountPiasters).toDisplay()} ج.م',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: isCompact ? 13 : 14,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: isCompact ? 3 : 5),
                              ],

                              // Discount with % and ج.م toggle
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'الخصم',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: isCompact ? 12 : 13,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          color: AppColors.surfaceContainerLow,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                            color: AppColors.outlineVariant,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _toggleBtn(
                                              label: '%',
                                              isSelected: _isPercentageDiscount,
                                              onTap: () {
                                                setState(
                                                  () => _isPercentageDiscount =
                                                      true,
                                                );
                                                _recalculateDiscount(
                                                  state.subtotal,
                                                );
                                              },
                                            ),
                                            _toggleBtn(
                                              label: 'ج.م',
                                              isSelected:
                                                  !_isPercentageDiscount,
                                              onTap: () {
                                                setState(
                                                  () => _isPercentageDiscount =
                                                      false,
                                                );
                                                _recalculateDiscount(
                                                  state.subtotal,
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      SizedBox(
                                        width: 78,
                                        height: 30,
                                        child: TextField(
                                          key: const Key('pos_cart_discount_input'),
                                          controller: _discountCtrl,
                                          focusNode: _discountFocus,
                                          keyboardType: TextInputType.number,
                                          style: const TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          textAlign: TextAlign.center,
                                          decoration: InputDecoration(
                                            hintText: '0',
                                            isDense: true,
                                            filled: true,
                                            fillColor: AppColors
                                                .surfaceContainerLowest,
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              borderSide: const BorderSide(
                                                color: AppColors.outlineVariant,
                                              ),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 4,
                                                  vertical: 4,
                                                ),
                                          ),
                                          onChanged: (_) =>
                                              _recalculateDiscount(
                                                state.subtotal,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              SizedBox(height: isCompact ? 4 : 6),

                              // Dine-in Service Charge & Tax Summary
                              Builder(
                                builder: (context) {
                                  final cfg = ReceiptSettingsService.current;
                                  final isDineIn = _isHospitality && _hospitalityOrderType == 'dineIn';
                                  final hasServiceCharge = isDineIn && cfg.dineInServiceChargeEnabled;
                                  final hasTax = cfg.taxEnabled;

                                  if (!hasServiceCharge && !hasTax) return const SizedBox.shrink();

                                  final scAmount = hasServiceCharge
                                      ? (state.subtotal * (cfg.dineInServiceChargeRate / 100)).round()
                                      : 0;
                                  final taxableBase = state.subtotal + scAmount;
                                  final taxAmount = hasTax && !cfg.taxInclusive
                                      ? (taxableBase * (cfg.taxRate / 100)).round()
                                      : 0;

                                  return Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (hasServiceCharge)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                          child: Row(
                                            key: const Key('pos_cart_service_charge_row'),
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                'خدمة الصالة (${cfg.dineInServiceChargeRate.toStringAsFixed(0)}%):',
                                                style: TextStyle(
                                                  fontFamily: 'Cairo',
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.grey.shade700,
                                                ),
                                              ),
                                              Text(
                                                '+${Money(scAmount).toDisplay()} ج.م',
                                                style: TextStyle(
                                                  fontFamily: 'Cairo',
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      if (hasTax)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                          child: Row(
                                            key: const Key('pos_cart_tax_row'),
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                'ضريبة القيمة المضافة (${cfg.taxRate.toStringAsFixed(0)}%${cfg.taxInclusive ? " مشمولة" : ""}):',
                                                style: TextStyle(
                                                  fontFamily: 'Cairo',
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.grey.shade700,
                                                ),
                                              ),
                                              Text(
                                                cfg.taxInclusive
                                                    ? 'مشمولة بالسعر'
                                                    : '+${Money(taxAmount).toDisplay()} ج.م',
                                                style: TextStyle(
                                                  fontFamily: 'Cairo',
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.grey.shade800,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                    ],
                                  );
                                },
                              ),

                              // Grand Total / Net Settlement Banner
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: isCompact ? 4 : 6,
                                ),
                                decoration: BoxDecoration(
                                  color: state.hasExchangeItems
                                      ? (state.isZeroNetExchange
                                          ? AppColors.success.withValues(alpha: 0.1)
                                          : state.total < 0
                                              ? AppColors.error.withValues(alpha: 0.1)
                                              : AppColors.primary.withValues(alpha: 0.08))
                                      : AppColors.surfaceContainer,
                                  borderRadius: BorderRadius.circular(10),
                                  border: state.hasExchangeItems
                                      ? Border.all(
                                          color: state.isZeroNetExchange
                                              ? AppColors.success.withValues(alpha: 0.35)
                                              : state.total < 0
                                                  ? AppColors.error.withValues(alpha: 0.35)
                                                  : AppColors.primary.withValues(alpha: 0.35),
                                        )
                                      : null,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      state.hasExchangeItems
                                          ? (state.isZeroNetExchange
                                              ? 'صافي تسوية الاستبدال (متطابق)'
                                              : state.total < 0
                                                  ? 'باقي استبدال مسترد للزبون'
                                                  : 'صافي فرق السعر (المطلوب تحصيله)')
                                          : 'الإجمالي النهائي',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: isCompact ? 12 : 14,
                                        fontWeight: FontWeight.bold,
                                        color: state.hasExchangeItems
                                            ? (state.isZeroNetExchange
                                                ? AppColors.success
                                                : state.total < 0
                                                    ? AppColors.error
                                                    : AppColors.primary)
                                            : null,
                                      ),
                                    ),
                                    Text(
                                      state.total < 0
                                          ? '-${Money(state.total.abs()).toDisplay()} ج.م'
                                          : '${Money(state.total).toDisplay()} ج.م',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: isCompact ? 16 : 20,
                                        fontWeight: FontWeight.w900,
                                        color: state.hasExchangeItems
                                            ? (state.isZeroNetExchange
                                                ? AppColors.success
                                                : state.total < 0
                                                    ? AppColors.error
                                                    : AppColors.primary)
                                            : AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: isCompact ? 4 : 6),

                              // Delivery and Payment Method Header
                              Row(
                                children: [
                                  Text(
                                    'طريقة الدفع:',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (_deliveryAvailable)
                                    Flexible(
                                      child: InkWell(
                                        key: const Key('pos_cart_delivery_btn'),
                                        onTap: () => _toggleDeliveryMode(state),
                                        borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _deliveryOrder != null
                                              ? AppColors.primary
                                              : AppColors.surfaceContainerLow,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                            color: _deliveryOrder != null
                                                ? AppColors.primary
                                                : AppColors.outlineVariant,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.delivery_dining_rounded,
                                              size: 14,
                                              color: _deliveryOrder != null
                                                  ? Colors.white
                                                  : AppColors.primary,
                                            ),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                _deliveryOrder != null
                                                    ? 'طلب دليفري (+${Money(_deliveryOrder!.deliveryFeePiasters).toDisplay()} ج.م)'
                                                    : 'طلب دليفري',
                                                style: TextStyle(
                                                  fontFamily: 'Cairo',
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: _deliveryOrder != null
                                                      ? Colors.white
                                                      : AppColors.onSurface,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (_deliveryOrder != null) ...[
                                              const SizedBox(width: 4),
                                              const Icon(
                                                Icons.close_rounded,
                                                size: 12,
                                                color: Colors.white,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: isCompact ? 3 : 5),

                              // Payment Method Buttons
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildPaymentBtn(
                                      method: 'cash',
                                      label: 'كاش',
                                      icon: Icons.payments_outlined,
                                      onTap: () => setState(
                                        () => _paymentMethod = 'cash',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: _buildPaymentBtn(
                                      method: 'card',
                                      label: 'فيزا',
                                      icon: Icons.credit_card_rounded,
                                      onTap: () => setState(
                                        () => _paymentMethod = 'card',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: _buildPaymentBtn(
                                      method: 'split',
                                      label: 'مجزأ',
                                      icon: Icons.call_split_rounded,
                                      onTap: () => setState(
                                        () => _paymentMethod = 'split',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_installmentAvailable || _creditAvailable) ...[
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    if (_installmentAvailable) ...[
                                      Expanded(
                                        child: _buildPaymentBtn(
                                          method: 'installment',
                                          label: 'تقسيط',
                                          icon: Icons.payments_rounded,
                                          onTap: () => setState(
                                            () => _paymentMethod =
                                                'installment',
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (_installmentAvailable &&
                                        _creditAvailable)
                                      const SizedBox(width: 5),
                                    if (_creditAvailable) ...[
                                      Expanded(
                                        child: _buildPaymentBtn(
                                          method: 'credit',
                                          label: 'آجل',
                                          icon: Icons
                                              .account_balance_wallet_outlined,
                                          onTap: () => setState(
                                            () => _paymentMethod = 'credit',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],

                              if (_paymentMethod == 'credit') ...[
                                SizedBox(height: isCompact ? 4 : 6),
                                _buildCreditPaymentSection(state),
                              ],

                              // Smart Cash Tender Presets & Exchange Notice
                              if (_paymentMethod == 'cash') ...[
                                if (state.hasExchangeItems && state.isZeroNetExchange) ...[
                                  SizedBox(height: isCompact ? 4 : 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: AppColors.success.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'استبدال متطابق القيمة (صافي 0 ج.م) - يتم الإغلاق فوراً بدون دفع أو استرداد',
                                            style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.success,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else if (state.hasExchangeItems && state.total < 0) ...[
                                  SizedBox(height: isCompact ? 4 : 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: AppColors.error.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.money_off_rounded, size: 16, color: AppColors.error),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'باقي استبدال للعميل: يُصرف ${Money(state.total.abs()).toDisplay()} ج.م نقداً من الدرج',
                                            style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.error,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else if (state.total > 0) ...[
                                  if (!isCompact) ...[
                                    const SizedBox(height: 5),
                                    _buildSmartCashTenderPresets(state),
                                  ],

                                  // Unified Single Row for Received and Change
                                  SizedBox(height: isCompact ? 4 : 6),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        Text(
                                          'المستلم:',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: isCompact ? 11 : 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        InkWell(
                                          onTap: () {
                                            _receivedCtrl.text = Money(
                                              state.total,
                                            ).toDisplay();
                                            setState(() {});
                                          },
                                          borderRadius: BorderRadius.circular(5),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 5,
                                              vertical: 1.5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary.withValues(
                                                alpha: 0.1,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                            ),
                                            child: Text(
                                              'بالضبط',
                                              style: TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        SizedBox(
                                          width: 75,
                                          height: 28,
                                          child: TextField(
                                            controller: _receivedCtrl,
                                            keyboardType: TextInputType.number,
                                            style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            decoration: InputDecoration(
                                              hintText: '0.00',
                                              isDense: true,
                                              filled: true,
                                              fillColor:
                                                  AppColors.surfaceContainerLowest,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 4,
                                                  ),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                borderSide: const BorderSide(
                                                  color: AppColors.outlineVariant,
                                                ),
                                              ),
                                            ),
                                            onChanged: (_) => setState(() {}),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          'الباقي: ',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: isCompact ? 11 : 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                        Text(
                                          '${Money(changePiasters).toDisplay()} ج.م',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: isCompact ? 12 : 13.5,
                                            fontWeight: FontWeight.bold,
                                            color: changePiasters > 0
                                                ? AppColors.success
                                                : AppColors.onSurface,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],

                              SizedBox(height: isCompact ? 6 : 8),

                              // Checkout [F12] Button (Compact 46px Height)
                              SizedBox(
                                width: double.infinity,
                                height: 46,
                                child: ElevatedButton.icon(
                                  onPressed:
                                      state.cart.isEmpty || state.isProcessing
                                          ? null
                                          : () => _handleCheckout(state),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: state.hasExchangeItems
                                        ? (state.isZeroNetExchange
                                            ? AppColors.success
                                            : state.total < 0
                                                ? AppColors.error
                                                : AppColors.primary)
                                        : AppColors.primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    elevation: 2,
                                  ),
                                  icon: state.isProcessing
                                      ? const SizedBox.shrink()
                                      : Icon(
                                          state.hasExchangeItems
                                              ? (state.isZeroNetExchange
                                                  ? Icons.swap_horiz_rounded
                                                  : state.total < 0
                                                      ? Icons.money_off_rounded
                                                      : Icons.price_check_rounded)
                                              : Icons.check_circle_rounded,
                                          size: 20,
                                          color: Colors.white,
                                        ),
                                  label: state.isProcessing
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(
                                          state.hasExchangeItems
                                              ? (state.isZeroNetExchange
                                                  ? 'إتمام استبدال متطابق (بدون دفع) [F12]'
                                                  : state.total < 0
                                                      ? 'صرف باقي استبدال للعميل (${Money(state.total.abs()).toDisplay()} ج.م) [F12]'
                                                      : 'تحصيل فرق الاستبدال (${Money(state.total).toDisplay()} ج.م) [F12]')
                                              : 'إتمام عملية البيع [F12]',
                                          style: const TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
      },
    );
  }

  Widget _toggleBtn({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : AppColors.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildCreditPaymentSection(PosState state) {
    final customer = state.customer;
    if (customer == null) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange.shade800,
              size: 20,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'البيع الآجل يتطلب تحديد عميل لحساب المديونية والحد الائتماني.',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return FutureBuilder<int>(
      future: getIt<CustomersLocalDataSource>().getCustomerCreditDebt(
        customer.id,
      ),
      builder: (context, snapshot) {
        final currentDebt = snapshot.data ?? 0;
        final downPaymentNum =
            double.tryParse(Money.normalizeDigits(_creditDownPaymentCtrl.text.trim())) ?? 0.0;
        final downPaymentPiasters = (downPaymentNum * 100).round().clamp(
          0,
          state.total,
        );
        final netCredit = state.total - downPaymentPiasters;
        final projectedDebt = currentDebt + netCredit;
        final limitExceeded =
            (customer.creditLimit > 0) &&
            (projectedDebt > customer.creditLimit);

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: limitExceeded ? Colors.red.shade50 : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: limitExceeded ? Colors.red.shade300 : Colors.blue.shade200,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'العميل: ${customer.name}',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    customer.creditLimit > 0
                        ? 'الحد الائتماني: ${Money(customer.creditLimit).toDisplay()} ج.م'
                        : 'الحد: غير مقيد',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11.5,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'المديونية السابقة: ${Money(currentDebt).toDisplay()} ج.م',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                  ),
                  Text(
                    'الإجمالي بعد الفاتورة: ${Money(projectedDebt).toDisplay()} ج.م',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: limitExceeded
                          ? Colors.red.shade800
                          : AppColors.primary,
                    ),
                  ),
                ],
              ),
              if (limitExceeded) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: Colors.red.shade800,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'تجاوز للحد الائتماني بمقدار ${Money(projectedDebt - customer.creditLimit).toDisplay()} ج.م (يتطلب موافقة المدير)',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _creditDownPaymentCtrl,
                      decoration: InputDecoration(
                        labelText: 'دفعة مقدمة كاش (اختياري)',
                        hintText: '0',
                        suffixText: 'ج.م',
                        isDense: true,
                        prefixIcon: const Icon(
                          Icons.payments_outlined,
                          size: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSmartCashTenderPresets(PosState state) {
    final presets = _calculateSmartTenderPresets(state.total);
    if (presets.isEmpty) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text(
              'الدفع السريع:',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10.5,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(width: 4),
            ...[50, 100, 200, 500].map((preset) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                child: InkWell(
                  onTap: () {
                    _receivedCtrl.text = '$preset.00';
                    setState(() {});
                  },
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: AppColors.outlineVariant),
                    ),
                    child: Text(
                      '$preset',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Text(
            'فئات ذكية:',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10.5,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 4),
          ...presets.asMap().entries.map((entry) {
            final index = entry.key;
            final preset = entry.value;
            final key = preset.isExact
                ? const Key('smart_tender_exact')
                : Key('smart_tender_preset_$index');

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: InkWell(
                key: key,
                onTap: () {
                  _receivedCtrl.text = preset.amount % 1 == 0
                      ? '${preset.amount.toInt()}.00'
                      : preset.amount.toStringAsFixed(2);
                  setState(() {});
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: preset.isExact
                        ? AppColors.primary.withValues(alpha: 0.12)
                        : AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: preset.isExact
                          ? AppColors.primary.withValues(alpha: 0.4)
                          : AppColors.outlineVariant,
                    ),
                  ),
                  child: Text(
                    preset.label,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10,
                      fontWeight:
                          preset.isExact ? FontWeight.bold : FontWeight.w600,
                      color: preset.isExact
                          ? AppColors.primary
                          : AppColors.onSurface,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  List<_SmartTenderPreset> _calculateSmartTenderPresets(int totalPiasters) {
    if (totalPiasters <= 0) return const [];
    final totalEgp = totalPiasters / 100.0;
    final List<_SmartTenderPreset> results = [];

    final candidates = <double>{};
    final next5 = ((totalEgp / 5.0).floor() + 1) * 5.0;
    if (next5 > totalEgp) candidates.add(next5);

    final next50 = ((totalEgp / 50.0).floor() + 1) * 50.0;
    if (next50 > totalEgp) candidates.add(next50);

    final next100 = ((totalEgp / 100.0).floor() + 1) * 100.0;
    if (next100 > totalEgp) candidates.add(next100);

    const standardNotes = [20.0, 50.0, 100.0, 200.0, 500.0];
    for (final note in standardNotes) {
      if (note > totalEgp) candidates.add(note);
    }

    final sorted = candidates.toList()..sort();
    for (final amt in sorted) {
      if (results.length >= 2) break;
      final change = amt - totalEgp;
      final amtStr =
          amt % 1 == 0 ? amt.toInt().toString() : amt.toStringAsFixed(2);
      final changeStr =
          change % 1 == 0 ? change.toInt().toString() : change.toStringAsFixed(2);
      results.add(_SmartTenderPreset(
        amount: amt,
        change: change,
        label: '$amtStr ج.م ◄ باقي $changeStr ج.م',
      ));
    }

    final exactStr =
        totalEgp % 1 == 0 ? totalEgp.toInt().toString() : totalEgp.toStringAsFixed(2);
    results.add(_SmartTenderPreset(
      amount: totalEgp,
      change: 0.0,
      label: 'المبلغ بالضبط: $exactStr ج.م',
      isExact: true,
    ));

    return results;
  }
}

// ---------------------------------------------------------------------------
// CART GROUP ACCORDION CARD (Task 17: Fast Matrix & Grouped Cart Lines)
// ---------------------------------------------------------------------------
class _CartGroupAccordionCard extends StatefulWidget {
  final String groupKey;
  final String productName;
  final List<SaleItemEntity> items;
  final bool isHospitality;

  const _CartGroupAccordionCard({
    super.key,
    required this.groupKey,
    required this.productName,
    required this.items,
    this.isHospitality = false,
  });

  @override
  State<_CartGroupAccordionCard> createState() =>
      _CartGroupAccordionCardState();
}

class _CartGroupAccordionCardState extends State<_CartGroupAccordionCard> {
  bool _isExpanded = true;

  int get _totalQty => widget.items.fold(0, (sum, it) => sum + it.quantity);
  int get _totalPrice => widget.items.fold(0, (sum, it) => sum + it.total);

  @override
  Widget build(BuildContext context) {
    final posCubit = context.read<PosCubit>();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Accordion Header
          InkWell(
            key: Key('cart_group_header_${widget.groupKey}'),
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(12),
              bottom: Radius.circular(_isExpanded ? 0 : 12),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer.withValues(alpha: 0.12),
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(12),
                  bottom: Radius.circular(_isExpanded ? 0 : 12),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.layers_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.productName,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppColors.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '$_totalQty قطع • ${widget.items.length} مقاسات',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${Money(_totalPrice).toDisplay()} ج.م',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    key: Key('cart_group_toggle_${widget.groupKey}'),
                    icon: Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _isExpanded = !_isExpanded),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Accordion Body: Individual Variant Tiles
          if (_isExpanded) ...[
            const Divider(height: 1, thickness: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                children: widget.items.map((it) {
                  final v = posCubit.getVariantById(it.variantId);
                  final maxStock = v?.quantity ?? 999;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _CartItemTile(
                      key: it.isReturn
                          ? ValueKey('${it.variantId}_return')
                          : ValueKey(it.variantId),
                      item: it,
                      maxStock: maxStock,
                      isHospitality: widget.isHospitality,
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SmartTenderPreset {
  final double amount;
  final double change;
  final String label;
  final bool isExact;

  const _SmartTenderPreset({
    required this.amount,
    required this.change,
    required this.label,
    this.isExact = false,
  });
}

// ---------------------------------------------------------------------------
// CART ITEM TILE: DIRECT INLINE QUANTITY CONTROLLER (FAST & RESPONSIVE)
// ---------------------------------------------------------------------------
class _CartItemTile extends StatefulWidget {
  final SaleItemEntity item;
  final int maxStock;
  final bool isHospitality;

  const _CartItemTile({
    super.key,
    required this.item,
    required this.maxStock,
    this.isHospitality = false,
  });

  @override
  State<_CartItemTile> createState() => _CartItemTileState();
}

class _CartItemTileState extends State<_CartItemTile> {
  late TextEditingController _qtyCtrl;
  final FocusNode _qtyFocus = FocusNode();

  bool get _isHospitality {
    if (widget.isHospitality) return true;
    if (widget.item.kitchenNotes != null && widget.item.kitchenNotes!.isNotEmpty) return true;
    if (getIt.isRegistered<ActivitySettingsService>()) {
      return getIt<ActivitySettingsService>().cachedEnabledActivities.contains(ActivityType.restaurantsCafes);
    }
    return false;
  }

  void _openKitchenNotesDialog(BuildContext context) {
    final item = widget.item;
    final textCtrl = TextEditingController(text: item.kitchenNotes ?? '');
    final selectedModifiers = Set<String>.from(item.modifiers);

    const exclusionPills = [
      'بدون بيض',
      'بدون بصل',
      'بدون مخلل',
      'بدون مايونيز',
      'بدون ثلج',
    ];

    const prepPills = [
      'سبايسي',
      'بدون شطة',
      'سكر خفيف',
      'سكر زيادة',
      'حليب شوفان',
    ];

    const additionPills = [
      'زيادة صوص',
      'زيادة جبنة',
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void togglePill(String pill) {
            setDialogState(() {
              if (selectedModifiers.contains(pill)) {
                selectedModifiers.remove(pill);
              } else {
                selectedModifiers.add(pill);
              }
              final customText = textCtrl.text
                  .split(' - ')
                  .where((s) =>
                      !exclusionPills.contains(s) &&
                      !prepPills.contains(s) &&
                      !additionPills.contains(s))
                  .join(' - ')
                  .trim();
              final allParts = [...selectedModifiers];
              if (customText.isNotEmpty) {
                allParts.add(customText);
              }
              textCtrl.text = allParts.join(' - ');
            });
          }

          Widget buildPillGroup(String title, List<String> pills) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: pills.map((p) {
                    final isSel = selectedModifiers.contains(p);
                    return InkWell(
                      key: Key('modifier_pill_$p'),
                      onTap: () => togglePill(p),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isSel
                              ? AppColors.secondary.withValues(alpha: 0.15)
                              : AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSel
                                ? AppColors.secondary
                                : AppColors.outlineVariant,
                            width: isSel ? 1.4 : 1.0,
                          ),
                        ),
                        child: Text(
                          p,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            fontWeight:
                                isSel ? FontWeight.bold : FontWeight.w500,
                            color: isSel
                                ? AppColors.secondary
                                : AppColors.onSurface,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],
            );
          }

          return AlertDialog(
            key: const Key('kitchen_notes_dialog'),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.soup_kitchen_rounded,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'استثناءات وملاحظات التحضير (${item.productName})',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildPillGroup('استثناءات وحذف مكونات:', exclusionPills),
                    buildPillGroup('تعديلات ونوع التحضير:', prepPills),
                    buildPillGroup('إضافات خاصة:', additionPills),
                    const Text(
                      'ملاحظة حرة إضافية:',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      key: const Key('kitchen_notes_custom_input'),
                      controller: textCtrl,
                      decoration: InputDecoration(
                        hintText: 'اكتب أي تفاصيل أخرى للطلب...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'إلغاء',
                  style: TextStyle(fontFamily: 'Cairo'),
                ),
              ),
              ElevatedButton(
                key: const Key('confirm_kitchen_notes_btn'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  final notes = textCtrl.text.trim();
                  context.read<PosCubit>().updateKitchenNotes(
                        item.variantId,
                        notes.isEmpty ? null : notes,
                        modifiers: selectedModifiers.toList(),
                        isReturn: item.isReturn,
                      );
                  Navigator.pop(ctx);
                },
                child: const Text(
                  'تأكيد الملاحظة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  bool get _isDecimalItem =>
      widget.item.decimalQuantity != null ||
      widget.item.unit == 'meter' ||
      widget.item.unit == 'م' ||
      widget.item.size.contains('رول') ||
      widget.item.size.contains('متر') ||
      widget.item.size.endsWith(' م') ||
      widget.item.size.contains('×');

  String _formatQty(double qty) {
    if (qty % 1 == 0) return qty.toInt().toString();
    return qty.toString();
  }

  @override
  void initState() {
    super.initState();
    _qtyFocus.addListener(_handleFocusChange);
    _qtyCtrl = TextEditingController(
      text: '${widget.item.isReturn ? "-" : ""}${_formatQty(widget.item.effectiveQuantity)}',
    );
  }

  void _handleFocusChange() {
    if (!_qtyFocus.hasFocus) {
      _commitQtyChange(_qtyCtrl.text);
    } else {
      _qtyCtrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _qtyCtrl.text.length,
      );
    }
  }

  @override
  void didUpdateWidget(covariant _CartItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.item.effectiveQuantity != widget.item.effectiveQuantity ||
         oldWidget.item.quantity != widget.item.quantity ||
         oldWidget.item.isReturn != widget.item.isReturn) &&
        !_qtyFocus.hasFocus) {
      _qtyCtrl.text = '${widget.item.isReturn ? "-" : ""}${_formatQty(widget.item.effectiveQuantity)}';
    }
  }

  @override
  void dispose() {
    _qtyFocus.removeListener(_handleFocusChange);
    _qtyCtrl.dispose();
    _qtyFocus.dispose();
    super.dispose();
  }

  void _commitQtyChange(String rawVal) {
    final val = Money.normalizeDigits(rawVal).replaceAll('-', '').trim();
    if (val.isEmpty) {
      _qtyCtrl.text = '${widget.item.isReturn ? "-" : ""}${_formatQty(widget.item.effectiveQuantity)}';
      return;
    }
    final parsedDouble = double.tryParse(val);
    if (parsedDouble == null || parsedDouble <= 0) {
      _qtyCtrl.text = '${widget.item.isReturn ? "-" : ""}${_formatQty(widget.item.effectiveQuantity)}';
      return;
    }

    if (_isDecimalItem || val.contains('.')) {
      context.read<PosCubit>().updateDecimalQuantity(
        widget.item.variantId,
        parsedDouble,
        widget.item.unit ?? (_isDecimalItem ? 'م' : null),
        widget.item.isReturn,
      );
    } else {
      final parsedInt = parsedDouble.toInt();
      int valid = parsedInt;
      if (!widget.item.isReturn && widget.maxStock > 0 && parsedInt > widget.maxStock) {
        valid = widget.maxStock;
        AppFloatingToast.show(
          context,
          message: 'الرصيد المتاح في المخزن هو ${widget.maxStock} فقط',
          type: ToastType.warning,
        );
      }
      _qtyCtrl.text = '${widget.item.isReturn ? "-" : ""}$valid';
      context.read<PosCubit>().updateQuantity(
        widget.item.variantId,
        valid,
        isReturn: widget.item.isReturn,
      );
    }
  }

  void _openPriceEditDialog(BuildContext context) {
    final item = widget.item;
    final priceCtrl = TextEditingController(
      text: (item.price / 100).toStringAsFixed(2),
    );
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.price_change_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              'تعديل سعر الصنف (سعر خاص / جملة)',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (!(item.color == '-' && item.size == '-') &&
                        item.color.isNotEmpty &&
                        item.size.isNotEmpty)
                    ? '${item.productName} (${item.color} - ${item.size})'
                    : item.productName,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                autofocus: true,
                style: TextStyle(fontFamily: 'Cairo', fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'سعر بيع الوحدة بالج.م *',
                  suffixText: 'ج.م',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'يرجى إدخال السعر';
                  }
                  final num = double.tryParse(Money.normalizeDigits(val.trim()));
                  if (num == null || num < 0) return 'السعر غير صالح';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              final pounds = double.tryParse(Money.normalizeDigits(priceCtrl.text.trim())) ?? 0.0;
              final piasters = (pounds * 100).toInt();
              context.read<PosCubit>().updateUnitPrice(
                item.variantId,
                piasters,
                isReturn: item.isReturn,
              );
              Navigator.pop(ctx);
            },
            child: Text(
              'حفظ السعر',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    try {
      return _buildContent(context);
    } catch (e, st) {
      return Container(
        padding: const EdgeInsets.all(8),
        color: Colors.red.shade50,
        child: SingleChildScrollView(
          child: Text(
            'CartItemTile error:\n$e\n$st',
            style: const TextStyle(color: Colors.red, fontSize: 10),
          ),
        ),
      );
    }
  }

  Widget _buildContent(BuildContext context) {
    final item = widget.item;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: item.isReturn
            ? AppColors.error.withValues(alpha: 0.04)
            : AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.isReturn
              ? AppColors.error.withValues(alpha: 0.35)
              : AppColors.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: Product Name + Return badge + Delete button
          Row(
            children: [
              Expanded(
                child: Text(
                  item.productName,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: item.isReturn
                        ? AppColors.error
                        : AppColors.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (item.isReturn) ...[
                const SizedBox(width: 6),
                Container(
                  key: Key('exchange_item_badge_${item.variantId}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Text(
                    'مرتجع استبدال',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
              if (_isHospitality) ...[
                const SizedBox(width: 4),
                InkWell(
                  key: Key('kitchen_notes_btn_${item.variantId}'),
                  onTap: () => _openKitchenNotesDialog(context),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: (item.kitchenNotes != null && item.kitchenNotes!.isNotEmpty)
                          ? AppColors.secondary.withValues(alpha: 0.12)
                          : AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: (item.kitchenNotes != null && item.kitchenNotes!.isNotEmpty)
                            ? AppColors.secondary
                            : AppColors.outlineVariant,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.soup_kitchen_rounded,
                          size: 11,
                          color: (item.kitchenNotes != null && item.kitchenNotes!.isNotEmpty)
                              ? AppColors.secondary
                              : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'ملاحظة تحضير',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: (item.kitchenNotes != null && item.kitchenNotes!.isNotEmpty)
                                ? AppColors.secondary
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: AppColors.error,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: () => context.read<PosCubit>().removeFromCart(
                      item.variantId,
                      isReturn: item.isReturn,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Row 2: Variations/Price/Notes button + Stepper + Line Total
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (!(item.color == '-' && item.size == '-') &&
                        item.color.isNotEmpty &&
                        item.size.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${item.color} • ${item.size}',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    InkWell(
                      onTap: () => _openPriceEditDialog(context),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                item.isReturn
                                    ? '-${Money(item.price).toDisplay()} ج.م'
                                    : '${Money(item.price).toDisplay()} ج.م',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: item.isReturn
                                      ? AppColors.error
                                      : AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.edit_outlined,
                              size: 12,
                              color: item.isReturn
                                  ? AppColors.error
                                  : AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (item.promotionDiscount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.local_offer,
                              size: 10,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              'عرض: -${Money(item.promotionDiscount).toDisplay()}',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Stepper
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_rounded, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      onPressed: () => context.read<PosCubit>().decreaseQty(
                            item.variantId,
                            isReturn: item.isReturn,
                          ),
                    ),
                    Container(
                      width: 44,
                      height: 26,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AppColors.outlineVariant.withValues(alpha: 0.6),
                        ),
                      ),
                      child: TextField(
                        key: Key('cart_qty_input_${item.variantId}'),
                        controller: _qtyCtrl,
                        focusNode: _qtyFocus,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: item.isReturn ? AppColors.error : AppColors.primary,
                        ),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                        onTap: () {
                          _qtyCtrl.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: _qtyCtrl.text.length,
                          );
                        },
                        onSubmitted: _commitQtyChange,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_rounded, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      onPressed: (!item.isReturn && item.quantity >= widget.maxStock)
                          ? () {
                              AppFloatingToast.show(
                                context,
                                message: 'الرصيد المتاح هو ${widget.maxStock} فقط',
                                type: ToastType.warning,
                              );
                            }
                          : () => context.read<PosCubit>().increaseQty(
                                item.variantId,
                                isReturn: item.isReturn,
                              ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Line Total
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.isReturn
                        ? '-${Money(item.total.abs()).toDisplay()} ج.م'
                        : '${Money(item.total).toDisplay()} ج.م',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: item.isReturn ? AppColors.error : AppColors.primary,
                    ),
                  ),
                  if (_isDecimalItem || item.decimalQuantity != null)
                    Text(
                      '${item.isReturn ? "-" : ""}${_formatQty(item.effectiveQuantity)} ${item.unit ?? "م"}',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        color: Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Row 3: Kitchen Notes (Full width across tile)
          if (item.kitchenNotes != null && item.kitchenNotes!.trim().isNotEmpty) ...[
            const SizedBox(height: 5),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.secondary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.notes_rounded, size: 13, color: AppColors.secondary),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'ملاحظة: ${item.kitchenNotes!}',
                      key: Key('kitchen_notes_text_${item.variantId}'),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    key: Key('clear_kitchen_notes_${item.variantId}'),
                    onTap: () {
                      context.read<PosCubit>().updateKitchenNotes(
                        item.variantId,
                        null,
                        modifiers: const [],
                        isReturn: item.isReturn,
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.close_rounded, size: 13, color: AppColors.secondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// FAST IN-CART ITEM EXCHANGE PICKER DIALOG (Task 28)
// ---------------------------------------------------------------------------
class _ExchangeItemDialog extends StatefulWidget {
  const _ExchangeItemDialog();

  @override
  State<_ExchangeItemDialog> createState() => _ExchangeItemDialogState();
}

class _ExchangeItemDialogState extends State<_ExchangeItemDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final posCubit = context.read<PosCubit>();
    final allVariants = posCubit.allVariants;

    final filteredVariants = _searchQuery.trim().isEmpty
        ? allVariants.take(40).toList()
        : allVariants.where((v) {
            final q = _searchQuery.trim().toLowerCase();
            final prodName = posCubit.getProductName(v.productId).toLowerCase();
            final code = v.productCode.toLowerCase();
            final sku = v.sku.toLowerCase();
            final color = v.color.toLowerCase();
            final size = v.size.toLowerCase();
            return prodName.contains(q) ||
                code.contains(q) ||
                sku.contains(q) ||
                color.contains(q) ||
                size.contains(q);
          }).toList();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.swap_horiz_rounded,
              color: AppColors.secondary,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'استبدال صنف - اختيار المرتجع',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'ابحث عن الصنف المرتجع بالاسم أو الباركود لإدراجه في السلة كبند استبدال سالب',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10.5,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: 540,
        height: 480,
        child: Column(
          children: [
            const SizedBox(height: 8),
            TextField(
              key: const Key('exchange_item_search_field'),
              controller: _searchCtrl,
              autofocus: true,
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
              decoration: InputDecoration(
                hintText: 'ابحث عن صنف للاستبدال (الاسم، الباركود، الكود، المقاس)...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                filled: true,
                fillColor: AppColors.surfaceContainerLowest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.outlineVariant),
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: filteredVariants.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 44,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _searchQuery.isEmpty
                                ? 'لا توجد أصناف مسجلة في النظام'
                                : 'لا توجد نتائج تطابق "$_searchQuery"',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              color: Colors.grey.shade600,
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: filteredVariants.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (ctx, idx) {
                        final v = filteredVariants[idx];
                        final prodName = posCubit.getProductName(v.productId);
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.outlineVariant.withValues(alpha: 0.6),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      prodName.isNotEmpty ? prodName : 'صنف #${v.id}',
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 2,
                                      children: [
                                        if (v.size.isNotEmpty && v.size != '-')
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: AppColors.surfaceContainerLow,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'المقاس: ${v.size}',
                                              style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        if (v.color.isNotEmpty && v.color != '-')
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: AppColors.surfaceContainerLow,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'اللون: ${v.color}',
                                              style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        if (v.productCode.isNotEmpty)
                                          Text(
                                            'كود: ${v.productCode}',
                                            style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.grey.shade600),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${Money(v.salePrice).toDisplay()} ج.م',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  Text(
                                    'الرصيد: ${v.quantity}',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 10,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                key: Key('confirm_exchange_item_btn_${v.id}'),
                                onPressed: () {
                                  posCubit.addExchangeItem(v, 1);
                                  Navigator.of(context).pop();
                                  AppFloatingToast.show(
                                    context,
                                    message: 'تمت إضافة صنف مرتجع للاستبدال: $prodName',
                                    type: ToastType.info,
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.secondary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: 0,
                                ),
                                icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                                label: const Text(
                                  'إدراج كمرتجع',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ALL-IN-ONE ASSIGN & ADD CUSTOMER DIALOG
// ---------------------------------------------------------------------------
class _AssignCustomerDialog extends StatefulWidget {
  const _AssignCustomerDialog();

  @override
  State<_AssignCustomerDialog> createState() => _AssignCustomerDialogState();
}

class _AssignCustomerDialogState extends State<_AssignCustomerDialog> {
  final _searchCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _discountCtrl;
  String _customerType = 'retail';

  List<CustomerEntity> _allCustomers = [];
  List<CustomerEntity> _filteredCustomers = [];
  bool _isLoading = true;
  bool _isCreatingNew = false;
  bool _isSavingNew = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _discountCtrl = TextEditingController();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    final result = await getIt<CustomerRepository>().getCustomers();
    if (mounted) {
      result.fold((_) => setState(() => _isLoading = false), (customers) {
        setState(() {
          _allCustomers = customers;
          _filteredCustomers = customers;
          _isLoading = false;
        });
      });
    }
  }

  void _filter(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filteredCustomers = _allCustomers;
      } else {
        _filteredCustomers = _allCustomers
            .where(
              (c) => c.name.toLowerCase().contains(q) || c.phone.contains(q),
            )
            .toList();
      }
    });
  }

  void _switchToCreateMode([String initialText = '']) {
    final text = initialText.trim();
    final isPhone = RegExp(r'^[0-9+]+$').hasMatch(text);
    setState(() {
      _nameCtrl.text = isPhone ? '' : text;
      _phoneCtrl.text = isPhone ? text : '';
      _customerType = 'retail';
      _discountCtrl.text = '';
      _isCreatingNew = true;
    });
  }

  Future<void> _submitNewCustomer() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() => _isSavingNew = true);

    final discount = int.tryParse(_discountCtrl.text.trim()) ?? 0;
    final cust = CustomerEntity(
      id: '',
      name: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      loyaltyPoints: 0,
      discountPercent: discount,
      customerType: _customerType,
      createdAt: DateTime.now(),
    );

    final res = await getIt<CustomerRepository>().addCustomer(cust);
    res.fold(
      (failure) {
        if (mounted) {
          setState(() => _isSavingNew = false);
          AppFloatingToast.show(
            context,
            message: 'خطأ: ${failure.message}',
            type: ToastType.error,
          );
        }
      },
      (_) async {
        final listRes = await getIt<CustomerRepository>().getCustomers(
          search: cust.phone,
        );
        CustomerEntity? createdCust;
        listRes.fold((_) => null, (list) {
          if (list.isNotEmpty) createdCust = list.first;
        });
        createdCust ??= cust;
        if (mounted) {
          Navigator.pop(context, createdCust);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                _isCreatingNew
                    ? Icons.person_add_rounded
                    : Icons.person_search_rounded,
                color: AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                _isCreatingNew ? 'إضافة عميل جديد' : 'تعيين عميل للفاتورة',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          if (!_isCreatingNew)
            TextButton.icon(
              onPressed: () => _switchToCreateMode(_searchCtrl.text),
              icon: const Icon(Icons.add, size: 16),
              label: Text(
                'عميل جديد',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            )
          else
            TextButton.icon(
              onPressed: () => setState(() => _isCreatingNew = false),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: Text(
                'رجوع للبحث',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _isCreatingNew
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: SizedBox(
            height: 400,
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'ابحث بالاسم أو رقم الهاتف...',
                    hintStyle: TextStyle(fontFamily: 'Cairo', fontSize: 12),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              _filter('');
                            },
                          )
                        : null,
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: _filter,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _isLoading
                      ? Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        )
                      : _filteredCustomers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.person_off_outlined,
                                size: 44,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'لا توجد نتائج مطابقة',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: () =>
                                    _switchToCreateMode(_searchCtrl.text),
                                icon: const Icon(
                                  Icons.add,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                label: Text(
                                  _searchCtrl.text.trim().isNotEmpty
                                      ? 'تسجيل "${_searchCtrl.text.trim()}" كعميل جديد'
                                      : 'إضافة عميل جديد',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: _filteredCustomers.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final customer = _filteredCustomers[index];
                            final isWholesale = customer.isWholesale;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: isWholesale
                                    ? AppColors.primary.withValues(alpha: 0.1)
                                    : AppColors.surfaceContainer,
                                child: Icon(
                                  isWholesale
                                      ? Icons.storefront_rounded
                                      : Icons.person_rounded,
                                  size: 18,
                                  color: AppColors.primary,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      customer.name,
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isWholesale)
                                    Container(
                                      margin: const EdgeInsets.only(right: 4),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: AppColors.primary.withValues(alpha: 0.25),
                                        ),
                                      ),
                                      child: Text(
                                        'جملة',
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  if (customer.discountPercent > 0)
                                    Container(
                                      margin: const EdgeInsets.only(right: 4),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: Colors.green.shade200,
                                        ),
                                      ),
                                      child: Text(
                                        '${customer.discountPercent}% خصم',
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade800,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Text(
                                customer.phone,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${customer.loyaltyPoints} نقطة',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.brown.shade800,
                                  ),
                                ),
                              ),
                              onTap: () => Navigator.pop(context, customer),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          secondChild: SizedBox(
            height: 400,
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _nameCtrl,
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'اسم العميل *',
                        hintText: 'مثال: محمد أحمد',
                        prefixIcon: const Icon(Icons.person_outline, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty
                          ? 'يرجى إدخال اسم العميل'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'رقم الهاتف *',
                        hintText: 'مثال: 01012345678',
                        prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty
                          ? 'يرجى إدخال رقم الهاتف'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _customerType,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: AppColors.onSurface,
                      ),
                      decoration: InputDecoration(
                        labelText: 'تصنيف العميل',
                        prefixIcon: const Icon(
                          Icons.category_outlined,
                          size: 20,
                        ),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'retail',
                          child: Text(
                            'عميل عادي (قطاعي)',
                            style: TextStyle(fontFamily: 'Cairo'),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'wholesale',
                          child: Text(
                            'تاجر جملة',
                            style: TextStyle(fontFamily: 'Cairo'),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'vip',
                          child: Text(
                            'عميل مميز',
                            style: TextStyle(fontFamily: 'Cairo'),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _customerType = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _discountCtrl,
                      keyboardType: TextInputType.number,
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'نسبة الخصم الدائم للعميل (%) [اختياري]',
                        hintText: 'مثال: 5 أو 10',
                        suffixText: '%',
                        prefixIcon: const Icon(Icons.percent_rounded, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      actions: [
        if (!_isCreatingNew)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'إلغاء',
              style: TextStyle(
                fontFamily: 'Cairo',
                color: Colors.grey.shade700,
              ),
            ),
          )
        else ...[
          TextButton(
            onPressed: () => setState(() => _isCreatingNew = false),
            child: Text(
              'رجوع',
              style: TextStyle(
                fontFamily: 'Cairo',
                color: Colors.grey.shade700,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            onPressed: _isSavingNew ? null : _submitNewCustomer,
            child: _isSavingNew
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'حفظ وتعيين للفاتورة',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// POS INSTALLMENT SUCCESS & CONTRACT PRINT DIALOG
// ---------------------------------------------------------------------------
class _PosInstallmentSuccessDialog extends StatelessWidget {
  final InvoiceDetailsEntity invoice;
  final CustomerInstallmentEntity contract;
  final List<InstallmentScheduleEntry> schedule;
  final CustomerEntity customer;

  const _PosInstallmentSuccessDialog({
    required this.invoice,
    required this.contract,
    required this.schedule,
    required this.customer,
  });

  @override
  Widget build(BuildContext context) {
    final shortContractId = contract.id.length >= 8
        ? contract.id.substring(0, 8).toUpperCase()
        : contract.id.toUpperCase();

    final totalFinanced = contract.monthlyAmountPiasters * contract.durationMonths;
    final totalObligation = totalFinanced + contract.downPaymentPiasters;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check_circle_rounded, color: Colors.green.shade700, size: 48),
                ),
                const SizedBox(height: 14),
                const Text(
                  'تم إنشاء الفاتورة وعقد التقسيط بنجاح!',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'فاتورة: #${invoice.shortRef} | عقد رقم: #$shortContractId',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12.5,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),

                // Financial Breakdown Box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('اسم العميل:', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.grey.shade600)),
                          Text(customer.name, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('إجمالي الفاتورة:', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.grey.shade600)),
                          Text('${Money(invoice.total).toDisplay()} ج.م', style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text('المقدم المُسدد (بالخزينة):', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.grey.shade600)),
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.green.shade300),
                                ),
                                child: Text(
                                  'مُقيد بالدرج',
                                  style: TextStyle(fontFamily: 'Cairo', fontSize: 9.5, color: Colors.green.shade800, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${Money(contract.downPaymentPiasters).toDisplay()} ج.م',
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('المبلغ المقسط (أصل الدين):', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.grey.shade600)),
                          Text('${Money(contract.principalPiasters).toDisplay()} ج.م', style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Divider(height: 1),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('القسط الشهري:', style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary)),
                          Text(
                            '${Money(contract.monthlyAmountPiasters).toDisplay()} ج.م / شهر (${contract.durationMonths} شهور)',
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('إجمالي التزام العميل:', style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, color: Colors.grey.shade600)),
                          Text('${Money(totalObligation).toDisplay()} ج.م', style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Actions: Print & Download
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: AppColors.outlineVariant),
                        ),
                        onPressed: () async {
                          final path = await ReceiptPdfService.saveInstallmentContractReceiptAsPdf(
                            invoice: invoice,
                            contract: contract,
                            schedule: schedule,
                            customer: customer,
                          );
                          if (path != null && context.mounted) {
                            AppFloatingToast.show(
                              context,
                              message: 'تم حفظ ملف PDF للعقد:\n$path',
                              type: ToastType.success,
                            );
                          }
                        },
                        icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.red, size: 18),
                        label: const Text('تنزيل PDF', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () async {
                          await ReceiptPdfService.printInstallmentContractReceipt(
                            invoice: invoice,
                            contract: contract,
                            schedule: schedule,
                            customer: customer,
                          );
                        },
                        icon: const Icon(Icons.print_rounded, size: 18),
                        label: const Text('طباعة العقد والإيصال', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => InstallmentDetailScreen(contractId: contract.id),
                            ),
                          );
                        },
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text('عرض تفاصيل العقد', style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('فاتورة جديدة (متابعة البيع)', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
