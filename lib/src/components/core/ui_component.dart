/// Base para componentes de shell embutíveis: raiz construída uma vez,
/// listeners rastreados (removidos no dispose) e coalescência de updates
/// de UI em um flush por frame (UiScheduler).
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Componente de UI com ciclo de vida próprio.
///
/// Subclasses constroem [root] no construtor e registram listeners via
/// [listen]; [dispose] é idempotente, cancela os listeners e remove [root]
/// do DOM (compatível com `ngOnDestroy` do AngularDart).
abstract class UiComponent {
  UiComponent(this.root);

  final web.HTMLElement root;
  final List<(web.EventTarget, String, JSFunction)> _listeners = [];
  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// Registra um listener que será removido automaticamente no [dispose].
  void listen(web.EventTarget target, String type, JSFunction handler,
      [web.AddEventListenerOptions? options]) {
    if (options != null) {
      target.addEventListener(type, handler, options);
    } else {
      target.addEventListener(type, handler);
    }
    _listeners.add((target, type, handler));
  }

  /// Hook chamado uma única vez durante o [dispose].
  void onDispose() {}

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final (target, type, handler) in _listeners) {
      target.removeEventListener(type, handler);
    }
    _listeners.clear();
    onDispose();
    root.remove();
  }
}

/// Agenda tarefas de UI coalescidas: cada função é executada no máximo uma
/// vez por frame (deduplicada por identidade), via `requestAnimationFrame`.
class UiScheduler {
  final Set<void Function()> _pending = {};
  bool _scheduled = false;
  bool _disposed = false;

  void schedule(void Function() task) {
    if (_disposed) return;
    _pending.add(task);
    if (_scheduled) return;
    _scheduled = true;
    web.window.requestAnimationFrame(((double _) {
      _scheduled = false;
      if (_disposed) return;
      final tasks = _pending.toList();
      _pending.clear();
      for (final t in tasks) {
        t();
      }
    }).toJS);
  }

  void dispose() {
    _disposed = true;
    _pending.clear();
  }
}
