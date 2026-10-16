import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/ledger.dart';
import '../../model/models.dart';
import '../widgets/common.dart';
import '../widgets/icons.dart';

/// Categorías de gasto e ingreso con subcategorías.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  CategoryKind _kind = CategoryKind.expense;

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s.ledger,
      builder: (BuildContext context, Widget? _) {
        final Ledger l = s.ledger;
        final List<Category> roots = l.roots(_kind);
        return Scaffold(
          appBar: AppBar(title: Text(t(context, 'Categorías', 'Categories'))),
          floatingActionButton: FloatingActionButton.extended(heroTag: null, onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => CategoryEditor(kind: _kind))), icon: const Icon(Icons.add), label: Text(t(context, 'Categoría', 'Category'))),
          body: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<CategoryKind>(
                  showSelectedIcon: false,
                  segments: <ButtonSegment<CategoryKind>>[
                    ButtonSegment<CategoryKind>(value: CategoryKind.expense, label: Text(t(context, 'Gastos', 'Expenses'))),
                    ButtonSegment<CategoryKind>(value: CategoryKind.income, label: Text(t(context, 'Ingresos', 'Income'))),
                  ],
                  selected: <CategoryKind>{_kind},
                  onSelectionChanged: (Set<CategoryKind> v) => setState(() => _kind = v.first),
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: roots.length,
                  // onReorderItem existe desde Flutter 3.41; se mantiene onReorder por compatibilidad.
                  // ignore: deprecated_member_use
                  onReorder: (int oldIndex, int newIndex) {
                    if (newIndex > oldIndex) {
                      newIndex -= 1;
                    }
                    final Category moved = roots.removeAt(oldIndex);
                    roots.insert(newIndex, moved);
                    for (int i = 0; i < roots.length; i++) {
                      roots[i].order = i;
                    }
                    l.save();
                  },
                  itemBuilder: (BuildContext context, int i) {
                    final Category r = roots[i];
                    final List<Category> kids = l.children(r.id);
                    return Column(
                      key: ValueKey<String>(r.id),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ListTile(
                          leading: IconBadge(icon: r.icon, color: r.color),
                          title: Text(r.name),
                          subtitle: kids.isEmpty ? null : Text(kids.map((Category c) => c.name).join(', '), maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              IconButton(tooltip: t(context, 'Subcategoría', 'Subcategory'), icon: const Icon(Icons.add_circle_outline), onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => CategoryEditor(kind: _kind, parentId: r.id)))),
                              ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                            ],
                          ),
                          onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => CategoryEditor(existing: r))),
                        ),
                        if (kids.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: <Widget>[
                                for (final Category c in kids)
                                  ActionChip(
                                    avatar: Icon(AppIcons.of(c.icon), size: 16, color: Color(c.color)),
                                    label: Text(c.name),
                                    onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => CategoryEditor(existing: c))),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Alta y edición de una categoría o subcategoría.
class CategoryEditor extends StatefulWidget {
  const CategoryEditor({super.key, this.existing, this.kind, this.parentId});

  final Category? existing;
  final CategoryKind? kind;
  final String? parentId;

  @override
  State<CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<CategoryEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.existing?.name ?? '');
  late String _icon = widget.existing?.icon ?? 'label';
  late int _color = widget.existing?.color ?? 0xFF5C6BC0;
  late String? _parentId = widget.existing?.parentId ?? widget.parentId;
  late CategoryKind _kind = widget.existing?.kind ?? widget.kind ?? CategoryKind.expense;

  @override
  void dispose() {
    disposeLater(<ChangeNotifier>[_name]);
    super.dispose();
  }

  Future<void> _save() async {
    final Ledger l = AppScope.of(context).ledger;
    final String name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'Escribe un nombre.', 'Enter a name.'))));
      return;
    }
    final Category? e = widget.existing;
    if (e == null) {
      await l.addCategory(Category(id: newId(), name: name, kind: _kind, icon: _icon, color: _color, parentId: _parentId));
    } else {
      e
        ..name = name
        ..icon = _icon
        ..color = _color
        ..parentId = _parentId;
      l.save();
    }
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Ledger l = AppScope.of(context).ledger;
    final List<Category> roots = l.roots(_kind).where((Category c) => c.id != widget.existing?.id).toList();
    final bool hasChildren = widget.existing != null && l.children(widget.existing!.id).isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? (_parentId == null ? t(context, 'Nueva categoría', 'New category') : t(context, 'Nueva subcategoría', 'New subcategory')) : t(context, 'Editar categoría', 'Edit category')),
        actions: <Widget>[
          if (widget.existing != null)
            IconButton(
              tooltip: t(context, 'Eliminar', 'Delete'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(context, t(context, '¿Eliminar categoría?', 'Delete category?'), t(context, 'Si tiene movimientos se archiva (los movimientos la conservan). Las subcategorías van con ella.', 'If it has transactions it is archived (they keep it). Subcategories go with it.'), yes: t(context, 'Eliminar', 'Delete')) && context.mounted) {
                  l.deleteCategory(widget.existing!.id);
                  Navigator.pop(context);
                }
              },
            ),
          TextButton(onPressed: _save, child: Text(t(context, 'Guardar', 'Save'))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          Row(
            children: <Widget>[
              IconBadge(icon: _icon, color: _color, size: 52),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _name, autofocus: widget.existing == null, decoration: InputDecoration(labelText: t(context, 'Nombre', 'Name'), border: const OutlineInputBorder()), textCapitalization: TextCapitalization.sentences)),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.existing == null)
            SegmentedButton<CategoryKind>(
              showSelectedIcon: false,
              segments: <ButtonSegment<CategoryKind>>[
                ButtonSegment<CategoryKind>(value: CategoryKind.expense, label: Text(t(context, 'Gasto', 'Expense'))),
                ButtonSegment<CategoryKind>(value: CategoryKind.income, label: Text(t(context, 'Ingreso', 'Income'))),
              ],
              selected: <CategoryKind>{_kind},
              onSelectionChanged: (Set<CategoryKind> v) => setState(() {
                _kind = v.first;
                _parentId = null;
              }),
            ),
          const SizedBox(height: 12),
          if (!hasChildren)
            DropdownButtonFormField<String?>(
              initialValue: roots.any((Category c) => c.id == _parentId) ? _parentId : null,
              isExpanded: true,
              decoration: InputDecoration(labelText: t(context, 'Dentro de', 'Inside'), border: const OutlineInputBorder()),
              items: <DropdownMenuItem<String?>>[
                DropdownMenuItem<String?>(value: null, child: Text(t(context, '— Categoría principal —', '— Top level —'))),
                for (final Category r in roots) DropdownMenuItem<String?>(value: r.id, child: Text(r.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (String? v) => setState(() => _parentId = v),
            ),
          const Divider(height: 24),
          IconColorPicker(icon: _icon, color: _color, onIcon: (String v) => setState(() => _icon = v), onColor: (int v) => setState(() => _color = v)),
        ],
      ),
    );
  }
}
