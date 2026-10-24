import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_scope.dart';
import '../../core/camera_draft.dart';
import '../../core/ledger.dart';
import '../../model/models.dart';
import '../../model/money.dart';
import '../more/cards_screen.dart';
import '../widgets/adaptive.dart';
import '../widgets/amount_keypad.dart';
import '../widgets/common.dart';
import '../widgets/icons.dart';

/// Alta y edición de un movimiento.
class TxEditor extends StatefulWidget {
  const TxEditor({super.key, this.existing, this.kind, this.template, this.inbox, this.initialAccountId, this.initialToAccountId, this.initialMinor, this.initialToMinor, this.initialDate, this.initialDescription, this.draft, this.statementOf});

  final Tx? existing;
  final TxKind? kind;
  final TxTemplate? template;
  final InboxItem? inbox;
  final String? initialAccountId;
  final String? initialToAccountId;
  final int? initialMinor;

  /// Monto que debe llegar al destino de una transferencia, en la moneda del
  /// destino (el pago de una tarjeta). Si el origen está en otra moneda, el
  /// monto que sale se calcula con la tasa guardada.
  final int? initialToMinor;
  final DateTime? initialDate;
  final String? initialDescription;

  /// Movimiento a medio escribir que se recuperó después de que Android
  /// cerrara la app con la cámara abierta (trae la foto ya adjunta).
  final Tx? draft;

  /// Pago de tarjeta que se registra desde la fila de un extracto: la fecha
  /// de su corte (`aaaa-mm-dd`). El movimiento queda vinculado a él.
  final String? statementOf;

  @override
  State<TxEditor> createState() => _TxEditorState();
}

class _TxEditorState extends State<TxEditor> {
  late TxKind _kind;
  late Calc _calc;
  int _minor = 0;
  String? _accountId;
  String? _toAccountId;

  /// Monto recibido en una transferencia entre monedas, si lo escribió el
  /// usuario (o venía de antes). Null = se calcula con la tasa guardada.
  int? _toMinor;
  bool _toAuto = true;

  /// Datos con que se calculó el monto recibido guardado (si cambian, se
  /// recalcula).
  String _toBasis = '';
  String? _categoryId;
  late DateTime _date;
  final TextEditingController _desc = TextEditingController();
  final TextEditingController _payee = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  final TextEditingController _check = TextEditingController();
  final TextEditingController _tag = TextEditingController();
  final List<String> _tags = <String>[];
  final List<TxSplit> _splits = <TxSplit>[];
  final List<String> _attachments = <String>[];
  final Set<String> _savedAttachments = <String>{};
  int _installments = 1;

  /// El usuario eligió las cuotas (si no, un avance nuevo propone 24).
  bool _installmentsTouched = false;

  /// Cuotas que se proponen para un avance: en cajero y en la app, Bancolombia
  /// los difiere siempre a 24 meses, y es lo más común en Colombia.
  static const int _defaultAdvanceInstallments = 24;
  bool _reconciled = false;
  bool _keypad = false;
  bool _more = false;
  bool _saving = false;

  /// El usuario tocó el monto (no se vuelve a convertir el del aviso).
  bool _amountEdited = false;

  /// Explicación de cómo se obtuvo el monto de un aviso en otra moneda.
  String? _noticeNote;
  Services? _s;

  @override
  void initState() {
    super.initState();
    final Tx? e = widget.draft ?? widget.existing;
    final TxTemplate? tpl = widget.template;
    final InboxItem? ib = widget.inbox;
    _kind = e?.kind ?? tpl?.kind ?? ib?.kind ?? widget.kind ?? TxKind.expense;
    _minor = e?.amountMinor ?? tpl?.amountMinor ?? widget.initialMinor ?? 0;
    _calc = Calc(initialMinor: _minor);
    _accountId = e?.accountId ?? tpl?.accountId ?? ib?.accountId ?? widget.initialAccountId;
    _toAccountId = e?.toAccountId ?? tpl?.toAccountId ?? widget.initialToAccountId;
    if (e != null) {
      _toMinor = e.toAmountMinor;
      _toAuto = e.toAmountMinor == null || e.toAmountAuto;
      _toBasis = _basisOf(e.amountMinor, e.accountId, e.toAccountId);
    } else if (tpl?.toAmountMinor != null) {
      _toMinor = tpl!.toAmountMinor;
      _toAuto = false;
    }
    _categoryId = e?.categoryId ?? tpl?.categoryId;
    _date = e?.date ?? ib?.receivedAt ?? widget.initialDate ?? clock.now();
    _desc.text = e?.description ?? tpl?.description ?? ib?.merchant ?? widget.initialDescription ?? '';
    _payee.text = e?.payee ?? tpl?.payee ?? '';
    _notes.text = e?.notes ?? (ib == null ? '' : ib.rawText);
    _check.text = e?.checkNumber ?? '';
    _tags.addAll(e?.tags ?? tpl?.tags ?? <String>[]);
    _splits.addAll(e?.splits ?? <TxSplit>[]);
    _attachments.addAll(e?.attachments ?? <String>[]);
    _savedAttachments.addAll(widget.existing?.attachments ?? <String>[]);
    _more = widget.draft != null;
    _installments = e?.installments ?? 1;
    _reconciled = e?.reconciled ?? false;
    _keypad = e == null && _minor == 0 && widget.initialToMinor == null && ib == null;
  }

  static String _basisOf(int amount, String? from, String? to) => '$amount|$from|$to';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_s != null) {
      return;
    }
    _s = AppScope.of(context);
    final Ledger l = _s!.ledger;
    _calc.spanish = _s!.settings.spanish;
    final InboxItem? ib = widget.inbox;
    // Un borrador recuperado ya trae lo que se había escrito sobre el aviso.
    final bool fromNotice = ib != null && widget.existing == null && widget.draft == null;
    if (fromNotice) {
      _initFromNotice(l, ib);
    }
    if (_accountId == null || l.account(_accountId) == null) {
      final String def = _s!.settings.defaultAccountId;
      _accountId = l.account(def)?.id ?? (l.activeAccounts.isEmpty ? null : l.activeAccounts.first.id);
      if (_kind == TxKind.transfer && _accountId == _toAccountId) {
        _accountId = l.activeAccounts.where((Account a) => a.id != _toAccountId && !a.isCredit).map((Account a) => a.id).firstOrNull;
      }
    }
    if (fromNotice) {
      _applyNoticeAmount(l);
    }
    final int? toMinor = widget.initialToMinor;
    if (toMinor != null && widget.existing == null) {
      _applyTargetAmount(l, toMinor);
    }
  }

  /// Cuentas de un aviso: la de origen por banco y dígitos; en un pago de
  /// tarjeta, la tarjeta como destino; en un retiro, el efectivo; si la plata
  /// llegó desde otra cuenta propia, la del aviso es el destino.
  void _initFromNotice(Ledger l, InboxItem ib) {
    final Account? matched = l.account(ib.accountId) ?? l.matchNotice(ib).account;
    if (ib.kind != TxKind.transfer) {
      _accountId = matched?.id;
      return;
    }
    switch (ib.flow) {
      case NoticeFlow.cardPayment:
        _accountId = matched?.id;
        _toAccountId = l.noticeCard(ib)?.id;
        break;
      case NoticeFlow.withdrawal:
        _accountId = matched?.id;
        _toAccountId = l.activeAccounts.where((Account a) => a.type == AccountType.cash).map((Account a) => a.id).firstOrNull;
        break;
      case NoticeFlow.transferIn:
        _toAccountId = matched?.id;
        _accountId = null;
        break;
      default:
        _accountId = matched?.id;
    }
  }

  /// El monto del aviso en la moneda de la cuenta: si el aviso llegó en otra
  /// moneda (una compra en dólares con una tarjeta en pesos), se convierte con
  /// la tasa guardada y se avisa que hay que revisarlo; sin tasa, se pide.
  void _applyNoticeAmount(Ledger l) {
    final InboxItem? ib = widget.inbox;
    if (ib == null || _amountEdited) {
      return;
    }
    final String? side = ib.flow == NoticeFlow.transferIn ? _toAccountId : _accountId;
    final String currency = l.account(side)?.currency ?? l.baseCurrency;
    final bool es = _s!.settings.spanish;
    final String original = Money.format(ib.amountMinor, ib.currency, spanish: es);
    if (ib.currency == currency) {
      _minor = ib.amountMinor;
      _noticeNote = null;
    } else {
      final int? converted = l.convert(ib.amountMinor, ib.currency, currency);
      _minor = converted ?? 0;
      _noticeNote = converted == null
          ? (es ? 'El aviso decía $original y la cuenta está en $currency: escribe el monto que te cobraron.' : 'The notice said $original and the account is in $currency: type the amount you were charged.')
          : (es ? 'El aviso decía $original; se convirtió a $currency con la tasa guardada. Revisa el valor que te cobró el banco.' : 'The notice said $original; it was converted to $currency at the saved rate. Check the amount your bank charged.');
    }
    _calc = Calc(initialMinor: _minor, spanish: _calc.spanish);
    _keypad = _minor == 0;
  }

  /// Pago de una tarjeta: el monto que debe llegar a la tarjeta, en su moneda.
  void _applyTargetAmount(Ledger l, int toMinor) {
    final Account? from = l.account(_accountId);
    final Account? to = l.account(_toAccountId);
    if (from == null || to == null || from.currency == to.currency) {
      _minor = toMinor;
    } else {
      _toMinor = toMinor;
      _toAuto = false;
      _minor = l.convert(toMinor, to.currency, from.currency) ?? 0;
    }
    _calc = Calc(initialMinor: _minor, spanish: _calc.spanish);
    _keypad = _minor == 0;
  }

  @override
  void dispose() {
    disposeLater(<ChangeNotifier>[_desc, _payee, _notes, _check, _tag]);
    super.dispose();
  }

  Ledger get _l => _s!.ledger;
  Account? get _account => _l.account(_accountId);
  String get _currency => _account?.currency ?? _l.baseCurrency;
  bool get _showDecimal => Money.info(_currency).decimals > 0 || _s!.settings.showCents;

  void _onKey(String k) => setState(() {
        _calc.press(k);
        _minor = _calc.valueMinor;
        _amountEdited = true;
      });

  /// Cierra la calculadora resolviendo la operación que quedó a medias:
  /// "50.000 + 20.000" y Listo anota 70.000.
  void _closeKeypad() => setState(() {
        _settleAmount();
        _keypad = false;
      });

  void _settleAmount() {
    _calc.evaluate();
    int v = _calc.valueMinor;
    if (!_showDecimal) {
      // Pesos sin centavos: una división queda en el peso más cercano.
      v = (v / 100).round() * 100;
    }
    if (v != _minor) {
      _minor = v;
      _calc = Calc(initialMinor: _minor, spanish: _calc.spanish);
    }
  }

  Future<void> _pickDate() async {
    final DateTime? d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d == null || !mounted) {
      return;
    }
    final TimeOfDay? tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_date));
    setState(() => _date = DateTime(d.year, d.month, d.day, tm?.hour ?? _date.hour, tm?.minute ?? _date.minute));
  }

  Future<void> _addAttachment(ImageSource source) async {
    final Ledger l = _s!.ledger;
    // Android puede cerrar la app mientras la cámara está abierta: se guarda
    // lo escrito para recuperarlo junto con la foto al volver.
    final bool keepDraft = source == ImageSource.camera && Platform.isAndroid;
    try {
      if (keepDraft) {
        await CameraDraft.save(l, _compose(), existingId: widget.existing?.id, inboxId: widget.inbox?.id);
      }
      final XFile? f = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 82);
      if (f == null) {
        return;
      }
      // La foto del recibo se guarda cifrada, igual que el resto del libro, y
      // las copias sin cifrar que deja el selector se borran.
      final String rel = 'attachments/${newId()}.jpg.enc';
      await l.store.writeBytes(rel, await f.readAsBytes());
      await deletePickerCopies(f);
      if (mounted) {
        setState(() => _attachments.add(rel));
      }
    } catch (e) {
      debugPrint('Adjuntar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'No se pudo adjuntar la foto. Intenta de nuevo.', 'The photo could not be attached. Try again.'))));
      }
    } finally {
      if (keepDraft) {
        await CameraDraft.clear(l);
      }
    }
  }

  /// Avance: transferencia que sale de una tarjeta de crédito (cajero, o
  /// pasar plata de la tarjeta a una cuenta).
  bool get _isAdvance => _kind == TxKind.transfer && (_account?.isCredit ?? false);

  /// Cuotas que se muestran y se guardan.
  int get _shownInstallments => _isAdvance && !_installmentsTouched && widget.existing == null && widget.draft == null ? _defaultAdvanceInstallments : _installments;

  int get _splitTotal => _splits.fold<int>(0, (int s, TxSplit p) => s + p.amountMinor);

  /// Divide el total en partes. El total escrito se conserva y cada parte
  /// propone lo que falta por asignar.
  Future<void> _addSplit() async {
    _settleAmount();
    final CategoryKind ck = _kind == TxKind.income ? CategoryKind.income : CategoryKind.expense;
    final Category? c = await pickCategory(context, ck);
    if (c == null || !mounted) {
      return;
    }
    final bool es = _s!.settings.spanish;
    final int remaining = _minor - _splitTotal;
    final String? txt = await askText(context, '${t(context, 'Monto para', 'Amount for')} ${c.name}', initial: remaining > 0 ? Money.format(remaining, _currency, withSymbol: false, showCents: _showDecimal, spanish: es) : '', keyboard: const TextInputType.numberWithOptions(decimal: true));
    if (txt == null) {
      return;
    }
    final int? m = Money.parse(txt);
    if (m == null || m <= 0) {
      return;
    }
    setState(() {
      if (_splits.isEmpty && _minor <= 0) {
        // Sin total escrito: las partes forman el total.
        _minor = m;
        _calc = Calc(initialMinor: _minor, spanish: _calc.spanish);
      }
      _splits.add(TxSplit(categoryId: c.id, amountMinor: m));
      _categoryId = null;
    });
  }

  void _showMessage(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  bool get _crossCurrency {
    final Account? a = _account;
    final Account? to = _l.account(_toAccountId);
    return _kind == TxKind.transfer && a != null && to != null && a.currency != to.currency;
  }

  /// Monto recibido que se guardará (null = que lo calcule el libro).
  int? _receivedToSave() {
    if (!_crossCurrency) {
      return null;
    }
    if (!_toAuto) {
      return _toMinor;
    }
    // Calculado antes y sin cambios en monto ni cuentas: se conserva la tasa
    // de ese día.
    if (widget.existing != null && _toMinor != null && _toBasis == _basisOf(_minor, _accountId, _toAccountId)) {
      return _toMinor;
    }
    return null;
  }

  /// Extracto al que queda vinculado el pago: el de la fila desde la que se
  /// abrió (o el que ya tenía), mientras siga siendo una transferencia a la
  /// misma tarjeta.
  String? get _linkKey {
    final Tx? base = widget.existing ?? widget.draft;
    final String? key = base?.statementOf ?? widget.statementOf;
    if (key == null) {
      return null;
    }
    final String? card = base == null ? widget.initialToAccountId : (base.isOutsidePayment ? base.accountId : base.toAccountId);
    final bool toCard = _kind == TxKind.transfer && _toAccountId != null && _toAccountId == card;
    // El pago hecho fuera de Plata sigue siéndolo mientras sea un abono a la
    // misma tarjeta.
    final bool outsideKept = base != null && base.isOutsidePayment && _kind == TxKind.income && _accountId == card;
    return toCard || outsideKept ? key : null;
  }

  /// El movimiento tal como está escrito en el formulario (sin validar).
  Tx _compose() {
    final Tx? e = widget.existing;
    final Tx tx = e == null ? Tx(id: newId(), kind: _kind, amountMinor: _minor, accountId: _accountId ?? '', date: _date) : Tx.fromJson(e.toJson());
    tx.kind = _kind;
    tx.amountMinor = _minor;
    tx.accountId = _accountId ?? '';
    tx.toAccountId = _kind == TxKind.transfer ? _toAccountId : null;
    final int? received = _kind == TxKind.transfer ? _receivedToSave() : null;
    tx.toAmountMinor = received;
    tx.toAmountAuto = received != null && _toAuto;
    tx.categoryId = _splits.isEmpty ? _categoryId : null;
    tx.date = _date;
    tx.description = _desc.text.trim();
    tx.payee = _payee.text.trim();
    tx.notes = _notes.text.trim();
    tx.checkNumber = _check.text.trim();
    tx.tags
      ..clear()
      ..addAll(_tags);
    tx.splits
      ..clear()
      ..addAll(_kind == TxKind.transfer ? const <TxSplit>[] : _splits);
    tx.attachments
      ..clear()
      ..addAll(_attachments);
    tx.installments = (_account?.isCredit ?? false) && (_kind == TxKind.expense || _kind == TxKind.transfer) ? _shownInstallments : 1;
    tx.reconciled = _reconciled;
    tx.statementOf = _linkKey;
    // Un pago hecho fuera de Plata que se cambia a transferencia desde una
    // cuenta (u otra cosa) deja de serlo.
    if (e != null && e.isOutsidePayment && !(_kind == TxKind.income && _accountId == e.accountId)) {
      tx.source = 'manual';
    }
    if (widget.inbox != null) {
      tx.source = 'notice';
    }
    return tx;
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    setState(_settleAmount);
    final Ledger l = _l;
    if (_minor <= 0) {
      setState(() => _keypad = true);
      _showMessage(t(context, 'Escribe el monto.', 'Enter the amount.'));
      return;
    }
    if (_accountId == null) {
      _showMessage(t(context, 'Elige la cuenta.', 'Choose the account.'));
      return;
    }
    if (_kind == TxKind.transfer && (_toAccountId == null || _toAccountId == _accountId)) {
      _showMessage(t(context, 'Elige la cuenta de destino.', 'Choose the destination account.'));
      return;
    }
    if (_kind != TxKind.transfer && _splits.isNotEmpty && _splitTotal != _minor) {
      final bool es = _s!.settings.spanish;
      _showMessage(t(context, 'Las partes suman ${Money.format(_splitTotal, _currency, spanish: es)} y el total es ${Money.format(_minor, _currency, spanish: es)}. Ajusta las partes o el total.', 'The parts add up to ${Money.format(_splitTotal, _currency, spanish: es)} and the total is ${Money.format(_minor, _currency, spanish: es)}. Adjust the parts or the total.'));
      return;
    }
    final Tx? e = widget.existing;
    // Se arma un borrador: si el libro lo rechaza, el original queda intacto.
    final Tx tx = _compose();
    // Al confirmar un aviso se vuelve a buscar el mismo cargo ya anotado (un
    // programado, algo anotado a mano): pudo llegar después del aviso.
    if (widget.inbox != null && e == null && _kind != TxKind.transfer) {
      final Tx? dup = l.similarTx(tx);
      if (dup != null) {
        final bool es = _s!.settings.spanish;
        final String what = '${Money.format(dup.amountMinor, dup.currency, spanish: es)} · ${formatDate(dup.date, 'dd MMM', spanish: es)}${dup.description.isEmpty ? '' : ' · ${dup.description}'}';
        final bool go = await confirm(context, t(context, 'Posible duplicado', 'Possible duplicate'), t(context, 'Ya hay un movimiento igual en esta cuenta ($what). ¿Anotar el aviso de todas formas?', 'There is already a matching transaction in this account ($what). Log the notice anyway?'), yes: t(context, 'Anotar igual', 'Log anyway'));
        if (!go || !mounted) {
          return;
        }
      }
    }
    setState(() => _saving = true);
    try {
      if (e == null) {
        await l.addTx(tx);
      } else {
        l.updateTx(tx);
      }
    } on TxRejected catch (err) {
      if (mounted) {
        setState(() => _saving = false);
        _showMessage(txProblemText(context, err));
      }
      return;
    }
    if (widget.inbox != null) {
      widget.inbox!.status = 'accepted';
      widget.inbox!.accountId = _accountId;
      // Si el aviso era la ocurrencia de un programado, el programado avanza.
      if (e == null) {
        l.linkNoticeToScheduled(widget.inbox!, tx);
      }
      l.save();
    }
    await l.deleteAttachmentFiles(_savedAttachments.difference(_attachments.toSet()));
    _s!.settings.defaultAccountId = _accountId!;
    await _s!.settings.save();
    // Un abono a la tarjeta que puede ser el pago hecho fuera de Plata de un
    // extracto marcado: el libro lo tomó provisionalmente por ese pago; se
    // pregunta aquí mismo (G1).
    if (mounted) {
      await askOutsideMatch(context, tx);
    }
    if (mounted) {
      // Solo al anotar uno nuevo: editar uno viejo no avisa.
      if (e == null) {
        offerOutsideHint(context, tx);
      }
      Navigator.of(context).pop(tx);
    }
  }

  Future<void> _saveAsTemplate() async {
    _settleAmount();
    final String? name = await askText(context, t(context, 'Nombre de la plantilla', 'Template name'), initial: _desc.text.trim());
    if (name == null || name.trim().isEmpty) {
      return;
    }
    final bool transfer = _kind == TxKind.transfer;
    await _l.addTemplate(TxTemplate(
      id: newId(),
      name: name.trim(),
      kind: _kind,
      amountMinor: _minor > 0 ? _minor : null,
      accountId: _accountId,
      toAccountId: transfer ? _toAccountId : null,
      toAmountMinor: transfer && _crossCurrency && !_toAuto ? _toMinor : null,
      categoryId: transfer ? null : _categoryId,
      description: _desc.text.trim(),
      payee: _payee.text.trim(),
      tags: List<String>.from(_tags),
      icon: _l.category(_categoryId)?.icon ?? (transfer ? 'transfer' : 'star'),
      color: _l.category(_categoryId)?.color ?? 0xFFFB8C00,
    ));
    if (mounted) {
      _showMessage(t(context, 'Plantilla guardada.', 'Template saved.'));
    }
  }

  Future<void> _editReceived(Account to) async {
    final bool es = _s!.settings.spanish;
    final String? txt = await askText(context, '${t(context, 'Monto recibido en', 'Amount received in')} ${to.currency}', initial: _toAuto || _toMinor == null ? '' : Money.format(_toMinor!, to.currency, withSymbol: false, showCents: true, spanish: es), hint: t(context, 'Vacío = calcular con la tasa guardada', 'Empty = use the saved rate'), keyboard: const TextInputType.numberWithOptions(decimal: true));
    if (txt == null) {
      return;
    }
    final int? v = Money.parse(txt);
    setState(() {
      if (txt.trim().isEmpty || v == null || v <= 0) {
        _toAuto = true;
        _toMinor = null;
      } else {
        _toAuto = false;
        _toMinor = v;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final Ledger l = s.ledger;
    final bool es = s.settings.spanish;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Account? acc = _account;
    final Account? to = l.account(_toAccountId);
    final Category? cat = l.category(_categoryId);
    final CategoryKind ck = _kind == TxKind.income ? CategoryKind.income : CategoryKind.expense;
    final bool crossCurrency = _crossCurrency;
    final List<Suggestion> suggestions = _desc.text.trim().length >= 2 && widget.existing == null ? l.suggest(_desc.text, kind: _kind) : <Suggestion>[];
    _calc.spanish = es;

    String receivedText() {
      if (to == null || acc == null) {
        return '';
      }
      final int? kept = _receivedToSave();
      if (!_toAuto && _toMinor != null) {
        return Money.format(_toMinor!, to.currency, showCents: true, spanish: es);
      }
      if (kept != null) {
        return '${Money.format(kept, to.currency, showCents: true, spanish: es)} · ${t(context, 'con la tasa de ese día', 'at that day\'s rate')}';
      }
      final int? preview = l.convert(_minor, acc.currency, to.currency);
      if (preview == null) {
        return t(context, 'Sin tasa entre ${acc.currency} y ${to.currency}: toca para escribir cuánto llegó, o pon la tasa en Más › Monedas.', 'No rate between ${acc.currency} and ${to.currency}: tap to type how much arrived, or set the rate under More › Currencies.');
      }
      return '≈ ${Money.format(preview, to.currency, showCents: true, spanish: es)} · ${t(context, 'con la tasa guardada', 'at the saved rate')}';
    }

    return ReadableScaffold(
      safeBottom: false,
      appBar: AppBar(
        title: Text(widget.existing == null ? t(context, 'Nuevo movimiento', 'New transaction') : t(context, 'Editar movimiento', 'Edit transaction')),
        actions: <Widget>[
          PopupMenuButton<String>(
            onSelected: (String v) async {
              if (v == 'template') {
                await _saveAsTemplate();
              } else if (v == 'delete' && widget.existing != null) {
                if (await confirm(context, t(context, 'Borrar movimiento', 'Delete transaction'), t(context, 'Esta acción no se puede deshacer.', 'This cannot be undone.'), yes: t(context, 'Borrar', 'Delete'))) {
                  await l.deleteTx(widget.existing!.id);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                }
              } else if (v == 'duplicate' && widget.existing != null) {
                final Tx copy;
                try {
                  copy = await l.duplicateTx(widget.existing!);
                } on TxRejected catch (err) {
                  if (context.mounted) {
                    _showMessage(txProblemText(context, err));
                  }
                  return;
                }
                if (context.mounted) {
                  await askOutsideMatch(context, copy);
                }
                if (context.mounted) {
                  offerOutsideHint(context, copy);
                  Navigator.of(context).pop();
                }
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              // Un pago hecho fuera de Plata no se copia ni se vuelve plantilla:
              // la copia sería un ingreso de verdad (se marca con «Ya lo pagué»).
              if (!(widget.existing?.isOutsidePayment ?? false)) PopupMenuItem<String>(value: 'template', child: Text(t(context, 'Guardar como plantilla', 'Save as template'))),
              if (widget.existing != null && !widget.existing!.isOutsidePayment) PopupMenuItem<String>(value: 'duplicate', child: Text(t(context, 'Duplicar hoy', 'Duplicate today'))),
              if (widget.existing != null) PopupMenuItem<String>(value: 'delete', child: Text(t(context, 'Borrar', 'Delete'))),
            ],
          ),
          TextButton(onPressed: _saving ? null : _save, child: Text(t(context, 'Guardar', 'Save'))),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: <Widget>[
                if (widget.existing?.isAdjustment ?? false)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(t(context, 'Ajuste de saldo: corrige el saldo de la cuenta y no cuenta como gasto ni ingreso en informes ni presupuestos.', 'Balance adjustment: it corrects the account balance and does not count as spending or income in reports or budgets.'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ),
                SegmentedButton<TxKind>(
                  segments: <ButtonSegment<TxKind>>[
                    ButtonSegment<TxKind>(value: TxKind.expense, label: Text(t(context, 'Gasto', 'Expense')), icon: const Icon(Icons.remove_circle_outline)),
                    ButtonSegment<TxKind>(value: TxKind.income, label: Text(t(context, 'Ingreso', 'Income')), icon: const Icon(Icons.add_circle_outline)),
                    ButtonSegment<TxKind>(value: TxKind.transfer, label: Text(t(context, 'Transf.', 'Transfer')), icon: const Icon(Icons.swap_horiz)),
                  ],
                  selected: <TxKind>{_kind},
                  showSelectedIcon: false,
                  onSelectionChanged: (Set<TxKind> v) => setState(() {
                    _kind = v.first;
                    final CategoryKind newKind = _kind == TxKind.income ? CategoryKind.income : CategoryKind.expense;
                    if (_kind == TxKind.transfer) {
                      _categoryId = null;
                      _splits.clear();
                    } else if (cat != null && cat.kind != newKind) {
                      // Un reembolso se elige a propósito con su botón, no al cambiar de tipo.
                      _categoryId = null;
                    }
                  }),
                ),
                const SizedBox(height: 12),
                AmountTile(minor: _minor, currency: _currency, color: kindColor(context, _kind), onTap: () => _keypad ? _closeKeypad() : setState(() => _keypad = true), label: _calc.expression.isNotEmpty && _calc.hasPendingOp ? _calc.expression : null),
                if (_noticeNote != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_noticeNote!, style: TextStyle(fontSize: 12, color: cs.tertiary))),
                if (_linkKey != null && DateTime.tryParse(_linkKey!) != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      (widget.existing?.isOutsidePayment ?? false) && _kind == TxKind.income
                          ? t(
                              context,
                              'Pago hecho fuera de Plata del extracto del ${dayText(context, DateTime.parse(_linkKey!))}: baja la deuda de la tarjeta, no sale de ninguna cuenta y no cuenta como ingreso. Si lo pagaste desde una cuenta que tienes en Plata, cámbialo a transferencia desde esa cuenta.',
                              'Payment made outside Plata for the ${dayText(context, DateTime.parse(_linkKey!))} statement: it lowers the card debt, does not come from any account and is not income. If you paid it from an account you have in Plata, change it to a transfer from that account.',
                            )
                          : t(
                              context,
                              'Queda asociado al extracto del ${dayText(context, DateTime.parse(_linkKey!))}: cuenta para ese extracto con cualquier fecha y reemplaza lo que se marcó como pagado fuera de Plata. Si lo pagaste desde una cuenta que no tienes en Plata, no lo registres: basta con la marca «Ya lo pagué».',
                              'It is linked to the ${dayText(context, DateTime.parse(_linkKey!))} statement: it counts for that statement whatever its date and replaces what was marked as paid outside Plata. If you paid from an account you do not have in Plata, do not log it: the "Already paid" mark is enough.',
                            ),
                      style: TextStyle(fontSize: 12, color: cs.tertiary),
                    ),
                  ),
                if (crossCurrency && to != null) ...<Widget>[
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.currency_exchange),
                    title: Text('${t(context, 'Monto recibido en', 'Amount received in')} ${to.currency}'),
                    subtitle: Text(receivedText()),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => _editReceived(to),
                  ),
                ],
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: acc == null ? const Icon(Icons.account_balance_wallet_outlined) : IconBadge(icon: acc.icon, color: acc.color),
                  title: Text(_kind == TxKind.transfer ? t(context, 'Desde', 'From') : t(context, 'Cuenta', 'Account')),
                  subtitle: Text(acc?.name ?? t(context, 'Elegir', 'Choose')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final Account? a = await pickAccount(context, exclude: _kind == TxKind.transfer ? _toAccountId : null);
                    if (a != null) {
                      setState(() {
                        _accountId = a.id;
                        _applyNoticeAmount(l);
                      });
                    }
                  },
                ),
                if (_kind == TxKind.transfer)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: to == null ? const Icon(Icons.call_received) : IconBadge(icon: to.icon, color: to.color),
                    title: Text(t(context, 'Hacia', 'To')),
                    subtitle: Text(to?.name ?? t(context, 'Elegir', 'Choose')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final Account? a = await pickAccount(context, exclude: _accountId, title: t(context, 'Cuenta de destino', 'Destination account'));
                      if (a != null) {
                        setState(() {
                          _toAccountId = a.id;
                          _applyNoticeAmount(l);
                        });
                      }
                    },
                  )
                else if (_splits.isEmpty) ...<Widget>[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: cat == null ? const Icon(Icons.label_outline) : IconBadge(icon: cat.icon, color: cat.color),
                    title: Text(_kind == TxKind.income && cat?.kind == CategoryKind.expense ? t(context, 'Reembolso de', 'Refund of') : t(context, 'Categoría', 'Category')),
                    subtitle: Text(cat == null ? t(context, 'Elegir', 'Choose') : l.categoryPath(cat.id)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final Category? c = await pickCategory(context, ck, current: _categoryId);
                      if (c != null) {
                        setState(() => _categoryId = c.id);
                      }
                    },
                  ),
                  if (_kind == TxKind.income)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () async {
                          final Category? c = await pickCategory(context, CategoryKind.expense, current: _categoryId);
                          if (c != null) {
                            setState(() => _categoryId = c.id);
                          }
                        },
                        icon: const Icon(Icons.undo),
                        label: Text(t(context, '¿Es un reembolso? Elige el gasto que devuelve', 'Is it a refund? Pick the expense it returns')),
                      ),
                    ),
                ],
                if (_splits.isNotEmpty) ...<Widget>[
                  Padding(padding: const EdgeInsets.only(top: 8, bottom: 4), child: Text(t(context, 'Dividido entre categorías', 'Split across categories'), style: Theme.of(context).textTheme.titleSmall)),
                  for (int i = 0; i < _splits.length; i++)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: IconBadge(icon: l.category(_splits[i].categoryId)?.icon ?? 'label', color: l.category(_splits[i].categoryId)?.color ?? 0xFF607D8B, size: 32),
                      title: Text(l.categoryPath(_splits[i].categoryId)),
                      subtitle: Text(Money.format(_splits[i].amountMinor, _currency, showCents: s.settings.showCents, spanish: es)),
                      trailing: IconButton(
                        tooltip: t(context, 'Quitar esta parte', 'Remove this part'),
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _splits.removeAt(i)),
                      ),
                    ),
                  if (_splitTotal != _minor)
                    Text(
                      _splitTotal < _minor ? '${t(context, 'Falta por asignar', 'Still to assign')}: ${Money.format(_minor - _splitTotal, _currency, showCents: s.settings.showCents, spanish: es)}' : '${t(context, 'Las partes pasan el total por', 'The parts exceed the total by')} ${Money.format(_splitTotal - _minor, _currency, showCents: s.settings.showCents, spanish: es)}',
                      style: TextStyle(fontSize: 12, color: cs.error),
                    ),
                ],
                if (_kind != TxKind.transfer)
                  Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _addSplit, icon: const Icon(Icons.call_split), label: Text(_splits.isEmpty ? t(context, 'Dividir en varias categorías', 'Split across categories') : t(context, 'Añadir otra parte', 'Add another part')))),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(t(context, 'Fecha', 'Date')),
                  subtitle: Text('${formatDate(_date, 'EEE dd MMM yyyy', spanish: es)} · ${formatDate(_date, 'HH:mm')}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickDate,
                ),
                TextField(
                  controller: _desc,
                  decoration: InputDecoration(labelText: t(context, 'Descripción', 'Description'), border: const OutlineInputBorder(), isDense: true, hintText: t(context, 'Ej.: Mercado D1', 'E.g.: Groceries')),
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                ),
                if (suggestions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: <Widget>[
                        for (final Suggestion sg in suggestions)
                          ActionChip(
                            avatar: Icon(AppIcons.of(l.category(sg.categoryId)?.icon ?? 'label'), size: 16),
                            label: Text(sg.description),
                            onPressed: () => setState(() {
                              _desc.text = sg.description;
                              _desc.selection = TextSelection.collapsed(offset: _desc.text.length);
                              _categoryId ??= sg.categoryId;
                              if (sg.payee.isNotEmpty && _payee.text.isEmpty) {
                                _payee.text = sg.payee;
                              }
                              if (_minor == 0 && sg.amountMinor != null) {
                                _minor = sg.amountMinor!;
                                _calc = Calc(initialMinor: _minor, spanish: es);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                if ((acc?.isCredit ?? false) && (_kind == TxKind.expense || _kind == TxKind.transfer)) ...<Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(child: Text(_isAdvance ? t(context, 'Cuotas del avance', 'Cash advance installments') : t(context, 'Cuotas', 'Installments'))),
                      DropdownButton<int>(
                        value: _shownInstallments,
                        items: <DropdownMenuItem<int>>[
                          for (final int n in (<int>{1, 2, 3, 6, 9, 12, 18, 24, 36, 48, _shownInstallments}.toList()..sort())) DropdownMenuItem<int>(value: n, child: Text(n == 1 ? t(context, '1 (pago único)', '1 (single)') : '$n')),
                        ],
                        onChanged: (int? v) => setState(() {
                          _installments = v ?? 1;
                          _installmentsTouched = true;
                        }),
                      ),
                    ],
                  ),
                  if (_isAdvance) Text(t(context, 'Los bancos suelen diferir los avances a 24 meses (Bancolombia, siempre en cajero y en la app). Revisa en tu extracto a cuántas cuotas quedó.', 'Banks usually spread cash advances over 24 months (Bancolombia always does at ATMs and in the app). Check your statement for the number of installments.'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
                TextButton.icon(onPressed: () => setState(() => _more = !_more), icon: Icon(_more ? Icons.expand_less : Icons.expand_more), label: Text(t(context, 'Más campos (beneficiario, etiquetas, notas, recibo)', 'More fields (payee, tags, notes, receipt)'))),
                if (_more) ...<Widget>[
                  TextField(controller: _payee, decoration: InputDecoration(labelText: t(context, 'Beneficiario / comercio', 'Payee / merchant'), border: const OutlineInputBorder(), isDense: true), textCapitalization: TextCapitalization.words),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: <Widget>[
                      for (final String tg in _tags) InputChip(label: Text('#$tg'), onDeleted: () => setState(() => _tags.remove(tg))),
                      for (final String tg in l.allTags.where((String x) => !_tags.contains(x)).take(8)) ActionChip(label: Text('#$tg'), onPressed: () => setState(() => _tags.add(tg))),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      Expanded(child: TextField(controller: _tag, decoration: InputDecoration(hintText: t(context, 'Nueva etiqueta', 'New tag'), isDense: true), onSubmitted: (_) => _addTag())),
                      IconButton(tooltip: t(context, 'Añadir etiqueta', 'Add tag'), onPressed: _addTag, icon: const Icon(Icons.add_circle_outline)),
                    ],
                  ),
                  TextField(controller: _notes, maxLines: 3, minLines: 1, decoration: InputDecoration(labelText: t(context, 'Notas', 'Notes'), border: const OutlineInputBorder(), isDense: true)),
                  const SizedBox(height: 10),
                  TextField(controller: _check, decoration: InputDecoration(labelText: t(context, 'Número de cheque o referencia', 'Check or reference number'), border: const OutlineInputBorder(), isDense: true)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      for (final String a in _attachments)
                        SizedBox(
                          width: 84,
                          height: 84,
                          child: Stack(
                            children: <Widget>[
                              Positioned(left: 0, bottom: 0, child: ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 72, height: 72, child: _AttachmentThumb(relative: a)))),
                              // Botón de quitar con su área de toque completa de 48 × 48
                              // dentro del recuadro (fuera de él no recibiría toques).
                              Positioned(
                                right: 0,
                                top: 0,
                                child: IconButton(
                                  tooltip: t(context, 'Quitar foto', 'Remove photo'),
                                  onPressed: () => setState(() => _attachments.remove(a)),
                                  icon: const CircleAvatar(radius: 11, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 14, color: Colors.white)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      OutlinedButton.icon(onPressed: () => _addAttachment(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined), label: Text(t(context, 'Foto del recibo', 'Receipt photo'))),
                      OutlinedButton.icon(onPressed: () => _addAttachment(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: Text(t(context, 'Galería', 'Gallery'))),
                    ],
                  ),
                  if (widget.existing != null)
                    SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(t(context, 'Conciliado con el extracto', 'Reconciled with statement')), value: _reconciled, onChanged: (bool v) => setState(() => _reconciled = v)),
                ],
              ],
            ),
          ),
          if (_keypad)
            Material(
              color: cs.surfaceContainerLow,
              elevation: 8,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Row(
                        children: <Widget>[
                          Expanded(child: Text(_calc.expression.isEmpty ? '0' : _calc.expression, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600), textAlign: TextAlign.end, maxLines: 1, overflow: TextOverflow.ellipsis)),
                          IconButton(tooltip: t(context, 'Cerrar la calculadora', 'Close the keypad'), onPressed: _closeKeypad, icon: const Icon(Icons.keyboard_hide_outlined)),
                        ],
                      ),
                    ),
                    AmountKeypad(onKey: _onKey, onDone: _closeKeypad, doneLabel: t(context, 'Listo', 'Done'), deleteLabel: t(context, 'Borrar', 'Delete'), showDecimal: _showDecimal, spanish: es),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _addTag() {
    final String v = _tag.text.trim().replaceAll(' ', '_').replaceAll('#', '');
    if (v.isEmpty) {
      return;
    }
    setState(() {
      if (!_tags.contains(v)) {
        _tags.add(v);
      }
      _tag.clear();
    });
  }
}

class _AttachmentThumb extends StatefulWidget {
  const _AttachmentThumb({required this.relative});

  final String relative;

  @override
  State<_AttachmentThumb> createState() => _AttachmentThumbState();
}

class _AttachmentThumbState extends State<_AttachmentThumb> {
  Future<Uint8List?>? _bytes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bytes ??= AppScope.of(context).ledger.store.readBytes(widget.relative);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (BuildContext context, AsyncSnapshot<Uint8List?> snap) {
        final Uint8List? bytes = snap.data;
        if (snap.hasError) {
          return const Center(child: Icon(Icons.broken_image_outlined));
        }
        if (bytes == null) {
          return ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest);
        }
        return Semantics(
          image: true,
          label: t(context, 'Foto del recibo', 'Receipt photo'),
          child: GestureDetector(
            onTap: () => showDialog<void>(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.memory(bytes)))),
            child: Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 200, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
          ),
        );
      },
    );
  }
}
