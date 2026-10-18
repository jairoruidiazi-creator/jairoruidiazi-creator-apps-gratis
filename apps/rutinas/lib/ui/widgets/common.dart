import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/dates.dart';
import '../catalog.dart';

/// Ancho desde el que la app usa el riel lateral (tabletas y pantallas grandes).
const double kWideLayout = 600;

/// Ancho máximo del contenido para que las líneas sigan siendo legibles.
const double kReadableWidth = 720;

/// Riel lateral solo si hay ancho y alto de sobra (una tableta, no un teléfono
/// acostado, donde el riel de cinco destinos no cabe a lo alto).
bool isWideLayout(BuildContext context) {
  final Size s = MediaQuery.sizeOf(context);
  return s.width >= kWideLayout && s.height >= 520;
}

/// Centra el contenido y lo limita a un ancho cómodo de leer.
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({super.key, required this.child, this.maxWidth = kReadableWidth});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
    );
  }
}

/// Título de sección dentro de una lista.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 8, 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              header: true,
              child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Pantalla vacía con un ícono, una explicación y una acción.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ExcludeSemantics(child: Icon(icon, size: 56, color: theme.colorScheme.primary)),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          if (action != null) ...<Widget>[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// Rejilla de tarjetas del mismo ancho y, en cada fila, de la misma altura:
/// tantas columnas como quepan con [minTileWidth] (todas en una fila si
/// caben; si no, de a dos o de a tres).
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children, this.minTileWidth = 150, this.spacing = 8});

  final List<Widget> children;
  final double minTileWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final int n = children.length;
        if (n == 0) {
          return const SizedBox.shrink();
        }
        final int fit = math.max(1, ((box.maxWidth + spacing) / (minTileWidth + spacing)).floor());
        int cols;
        if (fit >= n) {
          cols = n;
        } else if (fit >= 3 && n > 4) {
          cols = 3;
        } else {
          cols = math.min(2, fit);
        }
        final List<Widget> rows = <Widget>[];
        for (int i = 0; i < n; i += cols) {
          final List<Widget> cells = <Widget>[];
          for (int j = 0; j < cols; j++) {
            if (j > 0) {
              cells.add(SizedBox(width: spacing));
            }
            cells.add(Expanded(child: i + j < n ? children[i + j] : const SizedBox.shrink()));
          }
          if (rows.isNotEmpty) {
            rows.add(SizedBox(height: spacing));
          }
          rows.add(IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells)));
        }
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
      },
    );
  }
}

/// Diálogo de confirmación. Devuelve true si se aceptó.
Future<bool> confirm(BuildContext context, {required String title, required String message, required String yes, bool destructive = false}) async {
  final ThemeData theme = Theme.of(context);
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(message)),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t(context, 'Cancelar', 'Cancel'))),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: theme.colorScheme.error, foregroundColor: theme.colorScheme.onError) : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(yes),
        ),
      ],
    ),
  );
  return ok ?? false;
}

void showSnack(BuildContext context, String text, {String? actionLabel, VoidCallback? onAction}) {
  final ScaffoldMessengerState? m = ScaffoldMessenger.maybeOf(context);
  if (m == null) {
    return;
  }
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(text),
    action: actionLabel == null || onAction == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction),
  ));
}

/// Número con botones − y + de 48 dp. Para lectores de pantalla se anuncia
/// como un valor ajustable.
class NumberStepper extends StatelessWidget {
  const NumberStepper({super.key, required this.value, required this.min, required this.max, required this.onChanged, required this.label, this.step = 1, this.format});

  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  /// Qué se ajusta, para los lectores de pantalla ("Meta diaria").
  final String label;
  final String Function(int value)? format;

  @override
  Widget build(BuildContext context) {
    final String shown = format == null ? '$value' : format!(value);
    final bool canDown = value - step >= min;
    final bool canUp = value + step <= max;
    return Semantics(
      label: label,
      value: shown,
      increasedValue: canUp ? (format == null ? '${value + step}' : format!(value + step)) : null,
      decreasedValue: canDown ? (format == null ? '${value - step}' : format!(value - step)) : null,
      onIncrease: canUp ? () => onChanged(value + step) : null,
      onDecrease: canDown ? () => onChanged(value - step) : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ExcludeSemantics(
            child: IconButton.filledTonal(
              onPressed: canDown ? () => onChanged(value - step) : null,
              icon: const Icon(Icons.remove),
            ),
          ),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 56),
              child: ExcludeSemantics(
                child: Text(shown, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          ExcludeSemantics(
            child: IconButton.filledTonal(
              onPressed: canUp ? () => onChanged(value + step) : null,
              icon: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de etiqueta y control que se acomoda en dos líneas si no cabe.
class LabeledControl extends StatelessWidget {
  const LabeledControl({super.key, required this.label, required this.child, this.help});

  final String label;
  final String? help;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(label, style: theme.textTheme.bodyLarge),
                if (help != null) Text(help!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Círculos de color para elegir (48 dp cada uno).
class ColorChoice extends StatelessWidget {
  const ColorChoice({super.key, required this.selected, required this.onChanged, this.colors = kColors});

  final int selected;
  final ValueChanged<int> onChanged;
  final List<NamedColor> colors;

  @override
  Widget build(BuildContext context) {
    final bool es = isSpanish(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: <Widget>[
        for (final NamedColor c in colors)
          Semantics(
            button: true,
            selected: c.value == selected,
            label: c.label(es),
            child: InkResponse(
              onTap: () => onChanged(c.value),
              radius: 26,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: c.color,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.value == selected ? cs.onSurface : Colors.transparent, width: 3),
                    ),
                    child: c.value == selected ? Icon(Icons.check, size: 20, color: onColor(c.color)) : null,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Días de la semana para marcar (en el orden de la semana del usuario).
class WeekdayChoice extends StatelessWidget {
  const WeekdayChoice({super.key, required this.selected, required this.onChanged, required this.weekStart});

  final List<int> selected;
  final ValueChanged<List<int>> onChanged;
  final int weekStart;

  @override
  Widget build(BuildContext context) {
    final bool es = isSpanish(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final int d in orderedWeekdays(weekStart))
          Semantics(
            label: weekdayName(d, spanish: es),
            selected: selected.contains(d),
            button: true,
            excludeSemantics: true,
            child: FilterChip(
              label: Text(weekdayShort(d, spanish: es)),
              selected: selected.contains(d),
              showCheckmark: false,
              onSelected: (bool on) {
                final List<int> next = List<int>.of(selected);
                if (on) {
                  next.add(d);
                } else {
                  next.remove(d);
                }
                next.sort();
                onChanged(next);
              },
            ),
          ),
      ],
    );
  }
}

/// Selector de minutos y segundos con botones.
class DurationChoice extends StatelessWidget {
  const DurationChoice({super.key, required this.seconds, required this.onChanged, this.minSeconds = 1, this.maxSeconds = 4 * 3600});

  final int seconds;
  final ValueChanged<int> onChanged;
  final int minSeconds;
  final int maxSeconds;

  @override
  Widget build(BuildContext context) {
    final int m = seconds ~/ 60;
    final int s = seconds % 60;
    void set(int total) => onChanged(total.clamp(minSeconds, maxSeconds));
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            NumberStepper(value: m, min: 0, max: maxSeconds ~/ 60, onChanged: (int v) => set(v * 60 + s), label: t(context, 'Minutos', 'Minutes')),
            ExcludeSemantics(child: Text(t(context, 'minutos', 'minutes'), style: Theme.of(context).textTheme.labelMedium)),
          ],
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            NumberStepper(value: s, min: 0, max: 55, step: 5, onChanged: (int v) => set(m * 60 + v), label: t(context, 'Segundos', 'Seconds'), format: (int v) => v.toString().padLeft(2, '0')),
            ExcludeSemantics(child: Text(t(context, 'segundos', 'seconds'), style: Theme.of(context).textTheme.labelMedium)),
          ],
        ),
      ],
    );
  }
}

/// Ícono de un hábito en un círculo de su color.
class HabitAvatar extends StatelessWidget {
  const HabitAvatar({super.key, required this.icon, required this.color, this.size = 44, this.progress});

  final String icon;
  final int color;
  final double size;

  /// Avance del día (0 a 1) que se dibuja como anillo; null sin anillo.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final Color c = Color(color);
    final Widget circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      child: Icon(habitIconFor(icon).icon, color: onColor(c), size: size * 0.55),
    );
    final double? p = progress;
    if (p == null) {
      return ExcludeSemantics(child: circle);
    }
    return ExcludeSemantics(
      child: SizedBox(
        width: size + 10,
        height: size + 10,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            SizedBox(
              width: size + 10,
              height: size + 10,
              child: CircularProgressIndicator(value: p.clamp(0.0, 1.0).toDouble(), strokeWidth: 3.5, color: c, backgroundColor: c.withValues(alpha: 0.18)),
            ),
            circle,
          ],
        ),
      ),
    );
  }
}

/// Pide un texto en un diálogo. Devuelve null si se cancela.
Future<String?> askText(BuildContext context, {required String title, required String label, String hint = '', String initial = '', String? okLabel}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext ctx) => _TextPrompt(title: title, label: label, hint: hint, initial: initial, cancelLabel: t(context, 'Cancelar', 'Cancel'), okLabel: okLabel ?? t(context, 'Aceptar', 'OK')),
  );
}

class _TextPrompt extends StatefulWidget {
  const _TextPrompt({required this.title, required this.label, required this.hint, required this.initial, required this.cancelLabel, required this.okLabel});

  final String title;
  final String label;
  final String hint;
  final String initial;
  final String cancelLabel;
  final String okLabel;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _c,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: widget.label, hintText: widget.hint),
        onSubmitted: (String v) => Navigator.of(context).pop(v),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(widget.cancelLabel)),
        FilledButton(onPressed: () => Navigator.of(context).pop(_c.text), child: Text(widget.okLabel)),
      ],
    );
  }
}
