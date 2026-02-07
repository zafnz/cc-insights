import 'package:flutter/material.dart';

/// Keys for testing BranchSelectorDialog widgets.
class BranchSelectorDialogKeys {
  BranchSelectorDialogKeys._();

  /// The dialog itself.
  static const dialog = Key('branch_selector_dialog');

  /// The cancel button.
  static const cancelButton = Key('branch_selector_cancel');

  /// The empty state text.
  static const emptyText = Key('branch_selector_empty');

  /// The search field.
  static const searchField = Key('branch_selector_search');
}

/// Shows a dialog to select a branch from the given list.
///
/// Returns the selected branch name or null if cancelled.
Future<String?> showBranchSelectorDialog({
  required BuildContext context,
  required List<String> branches,
}) async {
  return showDialog<String>(
    context: context,
    builder: (context) => _BranchSelectorDialog(branches: branches),
  );
}

/// Dialog for selecting a branch from a filtered list.
class _BranchSelectorDialog extends StatefulWidget {
  const _BranchSelectorDialog({required this.branches});

  final List<String> branches;

  @override
  State<_BranchSelectorDialog> createState() => _BranchSelectorDialogState();
}

class _BranchSelectorDialogState extends State<_BranchSelectorDialog> {
  final _searchController = TextEditingController();
  late List<String> _filteredBranches;

  @override
  void initState() {
    super.initState();
    _filteredBranches = widget.branches;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredBranches = widget.branches;
      } else {
        final lower = query.toLowerCase();
        _filteredBranches = widget.branches
            .where((b) => b.toLowerCase().contains(lower))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      key: BranchSelectorDialogKeys.dialog,
      title: Row(
        children: [
          Icon(
            Icons.list_alt,
            size: 20,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          const Text('Select Branch'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Search field
            TextField(
              key: BranchSelectorDialogKeys.searchField,
              controller: _searchController,
              autofocus: true,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Filter branches...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Branch list
            if (widget.branches.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Text(
                  'No branches available',
                  key: BranchSelectorDialogKeys.emptyText,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else if (_filteredBranches.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Text(
                  'No branches match filter',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _filteredBranches.length,
                  itemBuilder: (context, index) {
                    final branch = _filteredBranches[index];
                    return InkWell(
                      key: Key('branch_selector_item_$index'),
                      onTap: () => Navigator.of(context).pop(branch),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8.0,
                          vertical: 10.0,
                        ),
                        child: Text(
                          branch,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: BranchSelectorDialogKeys.cancelButton,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
