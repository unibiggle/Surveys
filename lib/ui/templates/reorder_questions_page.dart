import 'package:flutter/material.dart';

import '../../models/template_schema.dart';

class ReorderQuestionsPage extends StatefulWidget {
  const ReorderQuestionsPage({super.key, required this.initial});
  final List<QuestionItem> initial;

  @override
  State<ReorderQuestionsPage> createState() => _ReorderQuestionsPageState();
}

class _ReorderQuestionsPageState extends State<ReorderQuestionsPage> {
  late List<QuestionItem> _items;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.initial);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reorder Questions'),
        actions: [
          IconButton(
            tooltip: 'Done',
            icon: const Icon(Icons.check),
            onPressed: () => Navigator.pop(context, _items),
          ),
        ],
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _items.length,
        onReorder: (oldIndex, newIndex) {
          setState(() {
            if (newIndex > oldIndex) newIndex -= 1;
            final moved = _items.removeAt(oldIndex);
            _items.insert(newIndex, moved);
          });
        },
        itemBuilder: (context, index) {
          final q = _items[index];
          return ListTile(
            key: ValueKey(q.id),
            title: Text(q.label),
            subtitle: Text(q.type.toString().split('.').last),
            trailing: const Icon(Icons.drag_handle),
          );
        },
      ),
    );
  }
}

