import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';

class CommandPaletteItem {
  final String id;
  final String title;
  final String category;
  final IconData icon;
  final String? subtitle;
  final VoidCallback onSelect;

  const CommandPaletteItem({
    required this.id,
    required this.title,
    required this.category,
    required this.icon,
    this.subtitle,
    required this.onSelect,
  });
}

class CommandPaletteDialog extends StatefulWidget {
  final List<CommandPaletteItem> items;

  const CommandPaletteDialog({
    super.key,
    required this.items,
  });

  @override
  State<CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<CommandPaletteDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _scrollCtrl = ScrollController();
  int _selectedIndex = 0;
  List<CommandPaletteItem> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filteredItems = widget.items;
      } else {
        _filteredItems = widget.items.where((it) {
          return it.title.toLowerCase().contains(q) ||
              it.category.toLowerCase().contains(q) ||
              (it.subtitle?.toLowerCase().contains(q) ?? false);
        }).toList();
      }
      _selectedIndex = 0;
    });
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_filteredItems.isNotEmpty && _selectedIndex < _filteredItems.length - 1) {
        setState(() => _selectedIndex++);
        _scrollToSelected();
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_filteredItems.isNotEmpty && _selectedIndex > 0) {
        setState(() => _selectedIndex--);
        _scrollToSelected();
      }
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_filteredItems.isNotEmpty && _selectedIndex < _filteredItems.length) {
        _executeItem(_filteredItems[_selectedIndex]);
      }
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
    }
  }

  void _scrollToSelected() {
    if (!_scrollCtrl.hasClients) return;
    const itemHeight = 60.0;
    final targetOffset = _selectedIndex * itemHeight;
    _scrollCtrl.animateTo(
      targetOffset.clamp(0.0, _scrollCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  void _executeItem(CommandPaletteItem item) {
    Navigator.pop(context);
    item.onSelect();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('command_palette_dialog'),
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 60, left: 24, right: 24, bottom: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 16,
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
        child: KeyboardListener(
          focusNode: FocusNode(),
          onKeyEvent: _handleKeyEvent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Search Input Box
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  key: const Key('command_palette_search_field'),
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'اكتب أمراً أو ابحث عن شاشة أو إجراء... (Esc للإغلاق)',
                    hintStyle: const TextStyle(fontSize: 14, color: Colors.grey),
                    prefixIcon: Icon(Icons.search_rounded, color: AppColors.primary, size: 22),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              _onSearchChanged('');
                            },
                          )
                        : Container(
                            margin: const EdgeInsets.all(8),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: const Text('ESC', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                          ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.primary, width: 1.8),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),

              // Filtered List
              Expanded(
                child: _filteredItems.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off_rounded, size: 44, color: Colors.grey.shade300),
                            const SizedBox(height: 8),
                            const Text('لا توجد شاشات أو أوامر مطابقة', style: TextStyle(color: Colors.grey, fontSize: 13)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                        itemCount: _filteredItems.length,
                        itemBuilder: (context, idx) {
                          final item = _filteredItems[idx];
                          final isSelected = idx == _selectedIndex;

                          return InkWell(
                            key: Key('command_palette_item_${item.id}'),
                            onTap: () => _executeItem(item),
                            borderRadius: BorderRadius.circular(8),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 100),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected ? AppColors.primary.withValues(alpha: 0.4) : Colors.transparent,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color: isSelected ? AppColors.primary : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      item.icon,
                                      size: 18,
                                      color: isSelected ? Colors.white : Colors.grey.shade700,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.title,
                                          style: TextStyle(
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                            fontSize: 13.5,
                                            color: isSelected ? AppColors.primary : Colors.black87,
                                          ),
                                        ),
                                        if (item.subtitle != null)
                                          Text(
                                            item.subtitle!,
                                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      item.category,
                                      style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  if (isSelected) ...[
                                    const SizedBox(width: 8),
                                    const Icon(Icons.keyboard_return_rounded, size: 16, color: Colors.grey),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),

              // Palette Bottom Helper Strip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.keyboard_outlined, size: 15, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'التنقل بالأسهم [↑ / ↓] • التنفيذ بـ [Enter] • الإغلاق بـ [Esc]',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
