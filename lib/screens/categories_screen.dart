/// Categories Screen — view, add, and delete categories.
///
/// Displays system categories (read-only) and user categories (deletable).
/// Includes a form to add new categories with icon and color pickers.
import '../widgets/morph_text.dart';
import 'package:flutter/material.dart';
import '../theme/motion.dart';
import '../utils/app_toast.dart';
import '../theme/app_theme.dart';
import '../widgets/spring_menu.dart';
import '../widgets/espere_action_button.dart';
import '../widgets/espere_header.dart';
import '../widgets/espere_filter_chip.dart';
import '../widgets/espere_swipe_action.dart';
import '../widgets/thanos_snap_widget.dart';
import '../models/category.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/connectivity_service.dart';
import '../services/sync_service.dart';
import '../services/widget_service.dart';
import '../utils/icon_mapper.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  List<CategoryModel> _categories = [];
  bool _isLoading = true;
  String _typeFilter = 'all';
  final Map<int, GlobalKey<ThanosSnapWidgetState>> _snapKeys = {};

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    // 1. Load from cache first
    final cachedCats = await CacheService.getCachedCategories();
    if (cachedCats != null && mounted) {
      final List catsRaw = cachedCats['categories'] ?? [];
      setState(() {
        _categories =
            catsRaw
                .map<CategoryModel>((c) => CategoryModel.fromJson(Map<String, dynamic>.from(c)))
                .toList()
              ..sort((a, b) {
                int cmp = a.name.compareTo(b.name);
                if (cmp != 0) return cmp;
                return b.id.compareTo(a.id);
              });
        _isLoading = false;
      });
      WidgetService.syncQuickAddCategories(
        _categories,
        currencySymbol: cachedCats['currency_symbol'] as String? ?? '₹',
      );
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRefresh() async {
    await SyncService.syncAll();
    await _loadCategories();
  }

  Future<void> _deleteCategory(CategoryModel cat, {GlobalKey<ThanosSnapWidgetState>? snapKey}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xxl),
        ),
        title: const Text('Delete Category'),
        content: Text('Are you sure you want to delete "${cat.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Thanos snap effect (respects the Delete Animation setting)
      await snapKey?.currentState?.startSnap();

      // Offline mode: queue deletion
      await SyncService.queueOperation(
        action: 'delete',
        entity: 'category',
        entityId: cat.id,
      );
      
      // Remove from cache
      final cached = await CacheService.getCachedCategories();
      if (cached != null) {
        final list = List<Map<String, dynamic>>.from(cached['categories'] ?? []);
        list.removeWhere((c) => c['id'] == cat.id);
        await CacheService.cacheCategories({
          'categories': list,
        });
      }
      
      setState(() {
        _categories.removeWhere((c) => c.id == cat.id);
      });

      // Trigger sync if online
      if (ConnectivityService.isOnline) {
        SyncService.syncAll();
      }
    }
  }

  void _showCategoryForm({CategoryModel? category}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _CategoryFormSheet(
        category: category,
        onSaved: () {
          Navigator.pop(ctx);
          _loadCategories();
        },
      ),
    );
  }

  Widget _buildTypePickerOption(String title, String value) {
    final isSelected = _typeFilter == value;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          color: AppColors.text,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check_rounded, color: AppColors.dark, size: 20)
          : null,
      onTap: () {
        Navigator.pop(context);
        setState(() => _typeFilter = value);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredCats = _categories.where((c) {
      if (_typeFilter == 'all') return true;
      return c.type == _typeFilter;
    }).toList();

    final systemCats = filteredCats.where((c) => c.isSystem).toList();
    final userCats = filteredCats.where((c) => !c.isSystem).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Top Bar ────────────────────────────────────
            EspereHeader(
              title: 'Categories',
              onBack: () => Navigator.pop(context),
              trailing: EspereActionButton(
                icon: Icons.add_rounded,
                primary: true,
                tooltip: 'New category',
                onPressed: () => _showCategoryForm(),
              ),
            ),

            // ─── Filter Bar ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              // Single filter: stretch to the full width (label left, arrow right).
              child: Row(
                children: [
                  for (final (value, label) in const [('all', 'All'), ('expense', 'Expense'), ('income', 'Income')])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: EspereFilterChip(
                        label: label,
                        dropdown: false,
                        active: _typeFilter == value,
                        onTap: () => setState(() => _typeFilter = value),
                      ),
                    ),
                ],
              ),
            ),

            // ─── Content ────────────────────────────────────
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.dark))
                  : RefreshIndicator(
                          onRefresh: _handleRefresh,
                          color: AppColors.dark,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(
                                16, 8, 16, 100),
                            children: [
                              // User categories
                              if (userCats.isNotEmpty) ...[
                                _SectionHeader(
                                  title: 'Your Categories',
                                  count: userCats.length,
                                ),
                                const SizedBox(height: 8),
                                ...userCats.map((cat) {
                                  final snapKey = _snapKeys.putIfAbsent(
                                      cat.id, () => GlobalKey<ThanosSnapWidgetState>());
                                  return ThanosSnapWidget(
                                    key: snapKey,
                                    child: _CategoryTile(
                                      category: cat,
                                      canEdit: true,
                                      onEdit: () => _showCategoryForm(category: cat),
                                      onDelete: () =>
                                          _deleteCategory(cat, snapKey: snapKey),
                                    ),
                                  );
                                }),
                                const SizedBox(height: 20),
                              ],

                              // System categories
                              _SectionHeader(
                                title: 'System Categories',
                                count: systemCats.length,
                              ),
                              const SizedBox(height: 8),
                              ...systemCats.map((cat) => _CategoryTile(
                                    category: cat,
                                    canEdit: false,
                                  )),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Section Header ─────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 8, bottom: 4),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppColors.dark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Category Tile ──────────────────────────────────────────────────────────

class _CategoryTile extends StatelessWidget {
  final CategoryModel category;
  final bool canEdit;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _CategoryTile({
    required this.category,
    required this.canEdit,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Container(
      padding: EdgeInsets.fromLTRB(14, 12, canEdit ? 2 : 14, 12),
      color: AppColors.card,
      child: Row(
        children: [
          // Icon badge
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: AppColors.categoryFill,
              shape: BoxShape.circle,
            ),
            child: MorphIcon(
              id: category.id,
              IconMapper.map(category.icon),
              size: 21,
              color: AppColors.categoryInk,
            ),
          ),
          const SizedBox(width: 12),

          // Name + type badge
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MorphText(id: category.id, 
                  category.name,
                  style: AppText.rowTitle,
                ),
                const SizedBox(height: 2),
                MorphText(id: category.id, 
                  '${category.type == 'income' ? 'Income' : 'Expense'} · ${category.isSystem ? 'Built-in' : 'Yours'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          if (canEdit)
            SpringMenuButton<String>(
              items: SpringMenuButton.editDelete(),
              onSelected: (v) => v == 'edit' ? onEdit?.call() : onDelete?.call(),
            ),
        ],
      ),
    );

    // Same swipe pattern as transactions: right = delete, left = edit
    // (only for user categories).
    if (canEdit) {
      content = EspereSwipeAction(
        dismissKey: ValueKey('category_${category.id}'),
        direction: DismissDirection.horizontal,
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            onDelete?.call();
          } else if (direction == DismissDirection.endToStart) {
            onEdit?.call();
          }
          return false;
        },
        bgIcon: Icons.delete_rounded,
        bgColor: AppColors.dark,
        bgIconColor: AppColors.accent,
        secBgIcon: Icons.edit_rounded,
        secBgColor: AppColors.accent,
        secBgIconColor: AppColors.dark,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        child: content,
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        boxShadow: AppShadows.soft,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        child: content,
      ),
    );
  }
}

// ─── Category Form Bottom Sheet ──────────────────────────────────────────────

/// Available icon choices matching Django's Category.ICON_CHOICES.
const _iconChoices = [
  ('restaurant', 'Food'),
  ('directions_car', 'Transport'),
  ('home', 'Housing'),
  ('movie', 'Entertainment'),
  ('shopping_bag', 'Shopping'),
  ('local_hospital', 'Healthcare'),
  ('school', 'Education'),
  ('payments', 'Salary'),
  ('work', 'Freelance'),
  ('trending_up', 'Investment'),
  ('redeem', 'Gift'),
  ('category', 'Other'),
  ('receipt_long', 'Bills'),
  ('flight', 'Travel'),
  ('checkroom', 'Clothing'),
  ('fitness_center', 'Fitness'),
  ('pets', 'Pets'),
  ('coffee', 'Coffee'),
  ('medical_services', 'Medical'),
  ('sports_esports', 'Gaming'),
  ('sports_soccer', 'Sports'),
  ('brush', 'Art'),
  ('music_note', 'Music'),
  ('science', 'Science'),
  ('build', 'Tools'),
  ('celebration', 'Party'),
  ('fastfood', 'Fast Food'),
  ('local_gas_station', 'Fuel'),
  ('electric_bolt', 'Electric'),
  ('water_drop', 'Water'),
  ('family_restroom', 'Family'),
  ('child_care', 'Baby'),
];


class _CategoryFormSheet extends StatefulWidget {
  final CategoryModel? category;
  final VoidCallback onSaved;

  const _CategoryFormSheet({this.category, required this.onSaved});

  @override
  State<_CategoryFormSheet> createState() => _CategoryFormSheetState();
}

class _CategoryFormSheetState extends State<_CategoryFormSheet> {
  late TextEditingController _nameController;
  late String _selectedIcon;
  late String _selectedColor;
  late String _selectedType;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name ?? '');
    _selectedIcon = widget.category?.icon ?? 'category';
    _selectedColor = widget.category?.color ?? '#C8E64A';
    _selectedType = widget.category?.type ?? 'expense';
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      AppToast.error(context, 'Category name is required.');
      return;
    }

    setState(() {
      _isSaving = true;
    });
    AppHaptics.confirm();

    final catData = {
      'name': name,
      'icon': _selectedIcon,
      'color': _selectedColor,
      'type': _selectedType,
    };

    // Always queue operation
    final tempId = DateTime.now().millisecondsSinceEpoch;
    await SyncService.queueOperation(
      action: widget.category != null ? 'update' : 'create',
      entity: 'category',
      data: catData,
      entityId: widget.category?.id ?? tempId,
    );

    // ─── Optimistic Update ──────────────────────────────────────────
    if (widget.category == null) {
      final newCatJson = {
        'id': tempId,
        'name': name,
        'icon': _selectedIcon,
        'color': _selectedColor,
        'is_system': false,
        'type': _selectedType,
      };
      await CacheService.addCategoryToCache(newCatJson);
    } else {
      final cached = await CacheService.getCachedCategories();
      if (cached != null) {
        final list = List<Map<String, dynamic>>.from(cached['categories'] ?? []);
        final idx = list.indexWhere((c) => c['id'] == widget.category!.id);
        if (idx != -1) {
          list[idx]['name'] = name;
          list[idx]['icon'] = _selectedIcon;
          list[idx]['color'] = _selectedColor;
          list[idx]['type'] = _selectedType;
          await CacheService.cacheCategories({
            'categories': list,
          });
        }
      }
    }
    // ───────────────────────────────────────────────────────────────
    
    // Trigger sync if online
    if (ConnectivityService.isOnline) {
      SyncService.syncAll();
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    widget.onSaved();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Center(
              child: Text(
                widget.category != null ? 'Edit Category' : 'New Category',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Type field
            const Text('Type',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text)),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: AppColors.card,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  builder: (ctx) => _CategoryTypePickerSheet(
                    selectedType: _selectedType,
                    onSelected: (type) {
                      setState(() => _selectedType = type);
                      Navigator.pop(ctx);
                    },
                  ),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.border, width: 1.5),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _selectedType == 'income' ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        size: 18,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selectedType == 'income' ? 'Income' : 'Expense',
                        style: const TextStyle(fontSize: 14, color: AppColors.text),
                      ),
                    ),
                    const Icon(Icons.expand_more_rounded, color: AppColors.muted),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Name field
            const Text('Name',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text)),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              onChanged: (_) => setState(() {}),
              style:
                  const TextStyle(fontSize: 14, color: AppColors.text),
              decoration: InputDecoration(
                hintText: 'e.g. Groceries',
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  borderSide: const BorderSide(
                      color: AppColors.border, width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  borderSide: const BorderSide(
                      color: AppColors.border, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
            ),
            const SizedBox(height: 20),

            // Icon picker
            const Text('Icon',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _iconChoices.map((choice) {
                final isSelected = _selectedIcon == choice.$1;
                return GestureDetector(
                  onTap: () =>
                      setState(() => _selectedIcon = choice.$1),
                  child: Tooltip(
                    message: choice.$2,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.accent
                            : AppColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? AppColors.dark
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        IconMapper.map(choice.$1),
                        size: 21,
                        color: AppColors.dark,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Save button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.accent,
                        ),
                      )
                    : Text(widget.category != null ? 'Update Category' : 'Create Category'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet for picking category type.
class _CategoryTypePickerSheet extends StatelessWidget {
  final String selectedType;
  final ValueChanged<String> onSelected;

  const _CategoryTypePickerSheet({
    required this.selectedType,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Select Type',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 12),
          _buildItem(
            context,
            'income',
            'Income',
            Icons.arrow_upward_rounded,
          ),
          _buildItem(
            context,
            'expense',
            'Expense',
            Icons.arrow_downward_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    String value,
    String label,
    IconData icon,
  ) {
    final isSelected = selectedType == value;
    return GestureDetector(
      onTap: () => onSelected(value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accentSoft
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: AppColors.dark),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: AppColors.text,
              ),
            ),
            if (isSelected) ...[
              const Spacer(),
              const Icon(Icons.check_circle_rounded, color: AppColors.dark),
            ],
          ],
        ),
      ),
    );
  }
}
