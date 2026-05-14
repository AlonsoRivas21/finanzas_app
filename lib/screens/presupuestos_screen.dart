// lib/screens/presupuestos_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/presupuesto_service.dart';
import '../database/catalogo_service.dart';

class PresupuestosScreen extends StatefulWidget {
  const PresupuestosScreen({super.key});

  @override
  State<PresupuestosScreen> createState() => _PresupuestosScreenState();
}

class _PresupuestosScreenState extends State<PresupuestosScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  int _mes = DateTime.now().month;
  int _anio = DateTime.now().year;

  List<PresupuestoModel> _porCategoria = [];
  List<PresupuestoModel> _porCuenta = [];
  Map<String, double> _gastosCategorias = {};
  Map<String, double> _gastosCuentas = {};
  bool _cargando = true;

  final _meses = [
    'Enero','Febrero','Marzo','Abril','Mayo','Junio',
    'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _cargar();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final todos = await PresupuestoService.getPresupuestos(_mes, _anio);
    final gastosCat = await PresupuestoService.getGastosRealesCategorias(_mes, _anio);
    final gastosCue = await PresupuestoService.getGastosRealesCuentas(_mes, _anio);
    setState(() {
      _porCategoria = todos.where((p) => p.tipo == 'categoria').toList();
      _porCuenta    = todos.where((p) => p.tipo == 'cuenta').toList();
      _gastosCategorias = gastosCat;
      _gastosCuentas    = gastosCue;
      _cargando = false;
    });
  }

  Future<void> _mostrarForm({PresupuestoModel? p, required String tipo}) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => _FormPresupuesto(
        presupuesto: p,
        tipo: tipo,
        mes: _mes,
        anio: _anio,
      ),
    );
    if (res == true) _cargar();
  }

  Future<void> _mostrarMasivo({required String tipo}) async {
    final existentes = (tipo == 'categoria' ? _porCategoria : _porCuenta)
        .map((p) => p.nombre).toList();

    final res = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogoMasivo(
        tipo: tipo,
        mes: _mes,
        anio: _anio,
        existentes: existentes,
      ),
    );
    if (res == true) _cargar();
  }

  Future<void> _eliminar(PresupuestoModel p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar presupuesto'),
        content: Text('¿Eliminar el presupuesto de ${p.nombre}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await PresupuestoService.eliminar(p.id);
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Presupuestos'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.category), text: 'Categorías'),
            Tab(icon: Icon(Icons.account_balance_wallet), text: 'Cuentas'),
          ],
        ),
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _anio,
              style: Theme.of(context).textTheme.bodyMedium,
              items: List.generate(3, (i) {
                final a = DateTime.now().year - i;
                return DropdownMenuItem(value: a, child: Text('$a'));
              }),
              onChanged: (a) { if (a != null) setState(() { _anio = a; _cargar(); }); },
            ),
          ),
          const SizedBox(width: 4),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _mes,
              style: Theme.of(context).textTheme.bodyMedium,
              items: List.generate(12, (i) => DropdownMenuItem(
                value: i + 1, child: Text(_meses[i]),
              )),
              onChanged: (m) { if (m != null) setState(() { _mes = m; _cargar(); }); },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.library_add_outlined),
            tooltip: 'Agregar varios',
            onPressed: () => _mostrarMasivo(tipo: _tab.index == 0 ? 'categoria' : 'cuenta'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [
                // Tab categorías
                _ListaPresupuestos(
                  presupuestos: _porCategoria,
                  gastos: _gastosCategorias,
                  onAgregar: () => _mostrarForm(tipo: 'categoria'),
                  onEditar: (p) => _mostrarForm(p: p, tipo: 'categoria'),
                  onEliminar: _eliminar,
                  etiquetaVacio: 'categorías',
                ),
                // Tab cuentas
                _ListaPresupuestos(
                  presupuestos: _porCuenta,
                  gastos: _gastosCuentas,
                  onAgregar: () => _mostrarForm(tipo: 'cuenta'),
                  onEditar: (p) => _mostrarForm(p: p, tipo: 'cuenta'),
                  onEliminar: _eliminar,
                  etiquetaVacio: 'cuentas',
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _mostrarForm(tipo: _tab.index == 0 ? 'categoria' : 'cuenta'),
        tooltip: 'Nuevo presupuesto',
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ── Diálogo Masivo ──────────────────────────────────────────────────────────

class _DialogoMasivo extends StatefulWidget {
  final String tipo;
  final int mes;
  final int anio;
  final List<String> existentes;
  const _DialogoMasivo({
    required this.tipo,
    required this.mes,
    required this.anio,
    required this.existentes,
  });

  @override
  State<_DialogoMasivo> createState() => _DialogoMasivoState();
}

class _DialogoMasivoState extends State<_DialogoMasivo> {
  final _limiteCtrl = TextEditingController(text: '0');
  List<String> _opciones = [];
  final Set<String> _seleccionados = {};
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarOpciones();
  }

  Future<void> _cargarOpciones() async {
    List<Map<String, dynamic>> data;
    if (widget.tipo == 'categoria') {
      data = await CatalogoService.getCategorias();
    } else {
      data = await CatalogoService.getCuentas();
    }
    
    setState(() {
      _opciones = data
          .map((e) => e['nombre'] as String)
          .where((n) => !widget.existentes.contains(n))
          .toList();
      _cargando = false;
    });
  }

  @override
  void dispose() {
    _limiteCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_seleccionados.isEmpty) return;
    setState(() => _guardando = true);
    final limite = double.tryParse(_limiteCtrl.text.replaceAll(',', '.')) ?? 0;

    try {
      for (final nombre in _seleccionados) {
        await PresupuestoService.guardar(
          PresupuestoService.crear(
            tipo: widget.tipo,
            nombre: nombre,
            limite: limite,
            mes: widget.mes,
            anio: widget.anio,
          ),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.tipo == 'categoria' ? 'categorías' : 'cuentas';
    return AlertDialog(
      title: Text('Agregar $label'),
      content: _cargando 
        ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
        : SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _limiteCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Límite para todos',
                    prefixText: '\$ ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Selecciona para agregar:', 
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (_opciones.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('No hay más elementos disponibles.', 
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _opciones.length,
                      itemBuilder: (context, index) {
                        final op = _opciones[index];
                        return CheckboxListTile(
                          title: Text(op, style: const TextStyle(fontSize: 14)),
                          value: _seleccionados.contains(op),
                          onChanged: (val) {
                            setState(() {
                              if (val == true) _seleccionados.add(op);
                              else _seleccionados.remove(op);
                            });
                          },
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _seleccionados.isEmpty || _guardando ? null : _guardar,
          child: _guardando 
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('Agregar seleccionados'),
        ),
      ],
    );
  }
}

// ── Lista de presupuestos ─────────────────────────────────────────────────────

class _ListaPresupuestos extends StatelessWidget {
  final List<PresupuestoModel> presupuestos;
  final Map<String, double> gastos;
  final VoidCallback onAgregar;
  final Function(PresupuestoModel) onEditar;
  final Function(PresupuestoModel) onEliminar;
  final String etiquetaVacio;

  const _ListaPresupuestos({
    required this.presupuestos,
    required this.gastos,
    required this.onAgregar,
    required this.onEditar,
    required this.onEliminar,
    required this.etiquetaVacio,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'es');

    if (presupuestos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.savings_outlined, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('Sin presupuestos de $etiquetaVacio',
                style: TextStyle(color: Colors.grey.shade500)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onAgregar,
              icon: const Icon(Icons.add),
              label: Text('Agregar presupuesto de $etiquetaVacio'),
            ),
          ],
        ),
      );
    }

    final totalLimite  = presupuestos.fold<double>(0, (s, p) => s + p.limite);
    final totalGastado = presupuestos.fold<double>(
        0, (s, p) => s + (gastos[p.nombre] ?? 0));
    final excedidos = presupuestos
        .where((p) => (gastos[p.nombre] ?? 0) > p.limite)
        .length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Resumen
        _ResumenCard(
          totalLimite: totalLimite,
          totalGastado: totalGastado,
          excedidos: excedidos,
          fmt: fmt,
        ),
        const SizedBox(height: 16),

        // Items
        ...presupuestos.map((p) {
          final gastado  = gastos[p.nombre] ?? 0;
          final pct      = p.limite > 0 ? (gastado / p.limite).clamp(0.0, 1.5) : 0.0;
          final excedido = gastado > p.limite;
          final color    = excedido ? Colors.red
              : pct >= 0.8 ? Colors.orange
              : Colors.green;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PresupuestoCard(
              presupuesto: p,
              gastado: gastado,
              pct: pct,
              color: color,
              excedido: excedido,
              fmt: fmt,
              onEditar: () => onEditar(p),
              onEliminar: () => onEliminar(p),
            ),
          );
        }),

        const SizedBox(height: 60),
      ],
    );
  }
}

class _ResumenCard extends StatelessWidget {
  final double totalLimite;
  final double totalGastado;
  final int excedidos;
  final NumberFormat fmt;
  const _ResumenCard({
    required this.totalLimite,
    required this.totalGastado,
    required this.excedidos,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final disponible = totalLimite - totalGastado;
    final pct = totalLimite > 0
        ? (totalGastado / totalLimite).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Resumen',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 10),
          Row(children: [
            _Mini('Límite', '\$${fmt.format(totalLimite)}', Colors.white),
            _Mini('Gastado', '\$${fmt.format(totalGastado)}',
                totalGastado > totalLimite
                    ? Colors.red.shade200 : Colors.white),
            _Mini('Disponible',
                '${disponible >= 0 ? '' : '-'}\$${fmt.format(disponible.abs())}',
                disponible >= 0 ? Colors.green.shade200 : Colors.red.shade200),
            _Mini('Excedidos', '$excedidos',
                excedidos > 0 ? Colors.red.shade200 : Colors.green.shade200),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation<Color>(
                totalGastado > totalLimite
                    ? Colors.red.shade300 : Colors.white),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${(pct * 100).toStringAsFixed(1)}% del presupuesto usado',
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  final String label;
  final String valor;
  final Color color;
  const _Mini(this.label, this.valor, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          Text(valor,
              style: TextStyle(color: color, fontSize: 12,
                  fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _PresupuestoCard extends StatelessWidget {
  final PresupuestoModel presupuesto;
  final double gastado;
  final double pct;
  final Color color;
  final bool excedido;
  final NumberFormat fmt;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;

  const _PresupuestoCard({
    required this.presupuesto, required this.gastado,
    required this.pct, required this.color, required this.excedido,
    required this.fmt, required this.onEditar, required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    final disponible = presupuesto.limite - gastado;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(
          color: excedido ? Colors.red.shade200 : Colors.grey.shade200,
          width: excedido ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
        color: excedido
            // ignore: deprecated_member_use
            ? Colors.red.shade50.withOpacity(0.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Icon(_icono(presupuesto.nombre), size: 16, color: color),
                const SizedBox(width: 8),
                Text(presupuesto.nombre,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                if (excedido) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('EXCEDIDO',
                        style: TextStyle(color: Colors.white,
                            fontSize: 9, fontWeight: FontWeight.w700)),
                  ),
                ],
              ]),
              Row(children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: onEditar,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: Colors.red),
                  onPressed: onEliminar,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              backgroundColor: Colors.grey.shade100,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Gastado: \$${fmt.format(gastado)}',
                  style: TextStyle(fontSize: 12, color: color,
                      fontWeight: FontWeight.w500)),
              Text('Límite: \$${fmt.format(presupuesto.limite)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            disponible >= 0
                ? 'Disponible: \$${fmt.format(disponible)}'
                : 'Excedido en: \$${fmt.format(disponible.abs())}',
            style: TextStyle(
                fontSize: 11,
                color: disponible >= 0
                    ? Colors.grey.shade500 : Colors.red),
          ),
          if (!presupuesto.sincronizado)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                Icon(Icons.cloud_off, size: 11, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text('Pendiente de sincronizar',
                    style: TextStyle(fontSize: 10,
                        color: Colors.grey.shade400)),
              ]),
            ),
        ],
      ),
    );
  }

  IconData _icono(String nombre) {
    switch (nombre.toUpperCase()) {
      case 'TRANSPORTE':      return Icons.directions_bus;
      case 'COMER FUERA':     return Icons.restaurant;
      case 'SERVICIOS':       return Icons.receipt;
      case 'SHOPPING':        return Icons.shopping_bag;
      case 'HOGAR':           return Icons.home;
      case 'PROVICIONES':     return Icons.shopping_cart;
      case 'PERDIDO':         return Icons.money_off;
      case 'ENTRETENIMIENTO': return Icons.movie;
      case 'PELO':            return Icons.content_cut;
      case 'BILLETERA':       return Icons.account_balance_wallet;
      case 'MULTIMONEY':      return Icons.savings;
      default:                return Icons.label;
    }
  }
}

// ── Formulario ────────────────────────────────────────────────────────────────

class _FormPresupuesto extends StatefulWidget {
  final PresupuestoModel? presupuesto;
  final String tipo;
  final int mes;
  final int anio;
  const _FormPresupuesto({
    this.presupuesto,
    required this.tipo,
    required this.mes,
    required this.anio,
  });

  @override
  State<_FormPresupuesto> createState() => _FormPresupuestoState();
}

class _FormPresupuestoState extends State<_FormPresupuesto> {
  final _formKey = GlobalKey<FormState>();
  final _limiteCtrl = TextEditingController();
  late String _nombre;
  List<String> _opciones = [];
  bool _guardando = false;
  bool _cargando = true;

  bool get esEdicion => widget.presupuesto != null;

  @override
  void initState() {
    super.initState();
    _cargarOpciones();
  }

  Future<void> _cargarOpciones() async {
    if (widget.tipo == 'categoria') {
      final cats = await CatalogoService.getCategorias();
      _opciones = cats.map((c) => c['nombre'] as String).toList();
    } else {
      final cues = await CatalogoService.getCuentas();
      _opciones = cues.map((c) => c['nombre'] as String).toList();
    }

    _nombre = esEdicion
        ? widget.presupuesto!.nombre
        : _opciones.first;
    if (esEdicion) {
      _limiteCtrl.text = widget.presupuesto!.limite.toString();
    }
    setState(() => _cargando = false);
  }

  @override
  void dispose() {
    _limiteCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);

    final limite =
        double.tryParse(_limiteCtrl.text.replaceAll(',', '.')) ?? 0;

    try {
      await PresupuestoService.guardar(
        PresupuestoService.crear(
          id: esEdicion ? widget.presupuesto!.id : null,
          tipo:   widget.tipo,
          nombre: _nombre,
          limite: limite,
          mes:    widget.mes,
          anio:   widget.anio,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.tipo == 'categoria' ? 'Categoría' : 'Cuenta';

    return AlertDialog(
      title: Text(esEdicion
          ? 'Editar presupuesto'
          : 'Nuevo presupuesto de $label'),
      content: _cargando 
        ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
        : Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: _nombre,
            decoration: InputDecoration(
                labelText: label, border: const OutlineInputBorder()),
            items: _opciones
                .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                .toList(),
            onChanged: esEdicion ? null : (v) => setState(() => _nombre = v!),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _limiteCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Límite mensual',
              prefixText: '\$ ',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Ingresa el límite';
              if (double.tryParse(v.replaceAll(',', '.')) == null) {
                return 'Monto inválido';
              }
              return null;
            },
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(esEdicion ? 'Guardar' : 'Crear'),
        ),
      ],
    );
  }
}
