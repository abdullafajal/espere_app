/// Categories Screen — view, add, and delete categories.
///
/// Displays system categories (read-only) and user categories (deletable).
/// Includes a form to add new categories with icon and color pickers.
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/category.dart';
import '../services/api_service.dart';
import '../utils/icon_mapper.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  List<CategoryModel> _categories = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _isLoading = true);
    final result = await ApiService.getCategories();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result.isSuccess) {
        _categories = result.data!;
      } else {
        _error = result.error;
      }
    });
  }

  Future<void> _deleteCategory(CategoryModel cat) async {
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
      final result = await ApiService.deleteCategory(cat.id);
      if (!mounted) return;
      if (result.isSuccess) {
        _loadCategories();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error ?? 'Failed to delete.')),
        );
      }
    }
  }

  void _showAddCategorySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _AddCategorySheet(
        onCreated: () {
          Navigator.pop(ctx);
          _loadCategories();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final systemCats = _categories.where((c) => c.isSystem).toList();
    final userCats = _categories.where((c) => !c.isSystem).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Top Bar ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        boxShadow: AppShadows.soft,
                      ),
                      child: const Icon(Icons.arrow_back,
                          color: AppColors.text),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Categories',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _showAddCategorySheet,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        boxShadow: AppShadows.soft,
                      ),
                      child:
                          const Icon(Icons.add, color: AppColors.dark),
                    ),
                  ),
                ],
              ),
            ),

            // ─── Content ────────────────────────────────────
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accent))
                  : _error != null
                      ? Center(
                          child: Text(_error!,
                              style:
                                  const TextStyle(color: AppColors.muted)))
                      : RefreshIndicator(
                          onRefresh: _loadCategories,
                          color: AppColors.accent,
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
                                ...userCats.map((cat) => _CategoryTile(
                                      category: cat,
                                      canDelete: true,
                                      onDelete: () =>
                                          _deleteCategory(cat),
                                    )),
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
                                    canDelete: false,
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
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(8),
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
  final bool canDelete;
  final VoidCallback? onDelete;

  const _CategoryTile({
    required this.category,
    required this.canDelete,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          // Icon badge
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: category.colorValue,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(
              IconMapper.map(category.icon),
              size: 22,
              color: AppColors.dark,
            ),
          ),
          const SizedBox(width: 12),

          // Name + type badge
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  category.isSystem ? 'System' : 'Custom',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),

          // Delete button (only for user categories)
          if (canDelete)
            GestureDetector(
              onTap: onDelete,
              child: Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(shape: BoxShape.circle),
                child: const Icon(Icons.delete_outline,
                    size: 18, color: AppColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Add Category Bottom Sheet ──────────────────────────────────────────────

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
];

/// Preset color palette for categories.
const _colorChoices = [
  '#C8E64A', '#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4',
  '#FFEAA7', '#DDA0DD', '#FF8C42', '#98D8C8', '#F7DC6F',
  '#BB8FCE', '#85C1E9', '#F0B27A', '#82E0AA', '#F1948A',
  '#AED6F1', '#D7BDE2', '#A3E4D7',
];

class _AddCategorySheet extends StatefulWidget {
  final VoidCallback onCreated;

  const _AddCategorySheet({required this.onCreated});

  @override
  State<_AddCategorySheet> createState() => _AddCategorySheetState();
}

class _AddCategorySheetState extends State<_AddCategorySheet> {
  final _nameController = TextEditingController();
  String _selectedIcon = 'category';
  String _selectedColor = '#C8E64A';
  bool _isSaving = false;
  String? _error;

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Category name is required.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    final result = await ApiService.createCategory({
      'name': name,
      'icon': _selectedIcon,
      'color': _selectedColor,
    });

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result.isSuccess) {
      widget.onCreated();
    } else {
      setState(() => _error = result.error ?? 'Failed to create.');
    }
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
            const Center(
              child: Text(
                'New Category',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Error
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(_error!,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.error)),
              ),

            // Name field
            const Text('Name',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text)),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
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
                        borderRadius:
                            BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.dark
                              : AppColors.border,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Icon(
                        IconMapper.map(choice.$1),
                        size: 20,
                        color: isSelected
                            ? AppColors.dark
                            : AppColors.muted,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Color picker
            const Text('Color',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _colorChoices.map((hex) {
                final isSelected = _selectedColor == hex;
                final color = Color(int.parse(
                    'FF${hex.replaceFirst('#', '')}',
                    radix: 16));
                return GestureDetector(
                  onTap: () =>
                      setState(() => _selectedColor = hex),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? AppColors.dark
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check,
                            size: 18, color: AppColors.dark)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Preview
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.xxl),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Color(int.parse(
                          'FF${_selectedColor.replaceFirst('#', '')}',
                          radix: 16)),
                      borderRadius:
                          BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(
                      IconMapper.map(_selectedIcon),
                      size: 22,
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _nameController.text.isEmpty
                        ? 'Preview'
                        : _nameController.text,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Save button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.accent,
                        ),
                      )
                    : const Text('Create Category'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
