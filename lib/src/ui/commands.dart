/// Undo/redo por snapshots de célula e operações estruturais.
library;

import '../model/workbook.dart';
import '../util/cell_ref.dart';

/// Snapshot imutável do conteúdo editável de uma célula.
class CellSnapshot {
  final CellValue? value;
  final String? formula;
  final bool isArrayFormula;
  final int styleIndex;

  const CellSnapshot(
      this.value, this.formula, this.isArrayFormula, this.styleIndex);

  factory CellSnapshot.of(Cell? cell) => cell == null
      ? const CellSnapshot(null, null, false, 0)
      : CellSnapshot(
          cell.value, cell.formula, cell.isArrayFormula, cell.styleIndex);

  void applyTo(Worksheet sheet, int row, int col) {
    final cell = sheet.ensureCell(row, col);
    cell
      ..value = value
      ..formula = formula
      ..isArrayFormula = isArrayFormula
      ..styleIndex = styleIndex
      ..invalidateFormat();
  }
}

/// Alteração de um conjunto de células (edição, colar, limpar, estilo).
class CellPatch {
  final int sheetIndex;
  final CellRef ref;
  final CellSnapshot before;
  final CellSnapshot after;

  const CellPatch(this.sheetIndex, this.ref, this.before, this.after);
}

sealed class Command {
  String get label;
}

class CellsCommand extends Command {
  @override
  final String label;
  final List<CellPatch> patches;

  CellsCommand(this.label, this.patches);
}

class MergeCommand extends Command {
  @override
  final String label;
  final int sheetIndex;
  final CellRange range;
  final bool isMerge; // true = mesclar, false = desfazer mescla

  MergeCommand(this.label, this.sheetIndex, this.range, {required this.isMerge});
}

class ResizeCommand extends Command {
  @override
  final String label;
  final int sheetIndex;
  final bool isColumn;
  final int index;
  final double? before; // largura chars / altura pt
  final double? after;

  ResizeCommand(this.label, this.sheetIndex, this.isColumn, this.index,
      this.before, this.after);
}

class CommandStack {
  final List<Command> _undo = [];
  final List<Command> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void push(Command command) {
    _undo.add(command);
    if (_undo.length > 500) _undo.removeAt(0);
    _redo.clear();
  }

  Command? popUndo() {
    if (_undo.isEmpty) return null;
    final c = _undo.removeLast();
    _redo.add(c);
    return c;
  }

  Command? popRedo() {
    if (_redo.isEmpty) return null;
    final c = _redo.removeLast();
    _undo.add(c);
    return c;
  }
}
