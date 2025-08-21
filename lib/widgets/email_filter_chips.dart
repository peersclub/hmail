import 'package:flutter/material.dart';
import '../models/email.dart';

class EmailFilterChips extends StatefulWidget {
  final Function(EmailFilter) onFilterChanged;

  const EmailFilterChips({super.key, required this.onFilterChanged});

  @override
  State<EmailFilterChips> createState() => _EmailFilterChipsState();
}

class _EmailFilterChipsState extends State<EmailFilterChips> {
  bool _unread = false;
  bool _starred = false;
  bool _important = false;
  bool _hasAttachments = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          FilterChip(
            label: const Text('Unread'),
            selected: _unread,
            onSelected: (selected) {
              setState(() => _unread = selected);
              _updateFilter();
            },
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Starred'),
            selected: _starred,
            onSelected: (selected) {
              setState(() => _starred = selected);
              _updateFilter();
            },
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Important'),
            selected: _important,
            onSelected: (selected) {
              setState(() => _important = selected);
              _updateFilter();
            },
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Has Attachments'),
            selected: _hasAttachments,
            onSelected: (selected) {
              setState(() => _hasAttachments = selected);
              _updateFilter();
            },
          ),
          const SizedBox(width: 8),
          ActionChip(
            label: const Text('Date Range'),
            onPressed: _selectDateRange,
          ),
          const SizedBox(width: 8),
          if (_hasActiveFilters())
            ActionChip(
              label: const Text('Clear All'),
              onPressed: _clearFilters,
            ),
        ],
      ),
    );
  }

  bool _hasActiveFilters() {
    return _unread || _starred || _important || _hasAttachments;
  }

  void _updateFilter() {
    widget.onFilterChanged(EmailFilter(
      isUnread: _unread ? true : null,
      isStarred: _starred ? true : null,
      isImportant: _important ? true : null,
      hasAttachments: _hasAttachments ? true : null,
    ));
  }

  void _clearFilters() {
    setState(() {
      _unread = false;
      _starred = false;
      _important = false;
      _hasAttachments = false;
    });
    _updateFilter();
  }

  void _selectDateRange() async {
    final dateRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );

    if (dateRange != null) {
      widget.onFilterChanged(EmailFilter(
        startDate: dateRange.start,
        endDate: dateRange.end,
      ));
    }
  }
}