// lib/screens/dashboard_screen.dart

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/movimiento.dart';
import '../models/movimientos_provider.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MovimientosProvider>().cargar();
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<MovimientosProvider>();
    final meses = [
      'Enero','Febrero','Marzo','Abril','Mayo','Junio',
      'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: prov.anioActual,
              style: Theme.of(context).textTheme.bodyMedium,
              items: List.generate(5, (i) {
                final anio = DateTime.now().year - i;
                return DropdownMenuItem(value: anio, child: Text('$anio'));
              }),
              onChanged: (a) { if (a != null) prov.setAnio(a); },
            ),
          ),
          const SizedBox(width: 4),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: prov.mesActual,
              style: Theme.of(context).textTheme.bodyMedium,
              items: List.generate(12, (i) => DropdownMenuItem(
                value: i + 1, child: Text(meses[i]),
              )),
              onChanged: (m) { if (m != null) prov.setMes(m); },
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => prov.cargar(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 2. Resumen del mes
            _TituloSeccion(
              icono: Icons.calendar_month,
              titulo: 'Resumen del mes',
              subtitulo: meses[prov.mesActual - 1],
            ),
            const SizedBox(height: 10),
            const _ResumenMes(),
            const SizedBox(height: 20),

            // 1. Saldos por cuenta (primero)
            const _TituloSeccion(
              icono: Icons.account_balance_wallet,
              titulo: 'Saldos por cuenta',
              subtitulo: 'Acumulado total',
            ),
            const SizedBox(height: 10),
            const _GraficoSaldosCuentas(),
            const SizedBox(height: 20),
            
            // 3. Gráfico pastel
            _TituloSeccion(
              icono: Icons.pie_chart,
              titulo: 'Gastos por categoría',
              subtitulo: meses[prov.mesActual - 1],
            ),
            const SizedBox(height: 10),
            _GraficoPastel(mes: prov.mesActual, anio: prov.anioActual),
            const SizedBox(height: 20),

            // 4. Barras por semana
            const _TituloSeccion(
              icono: Icons.bar_chart,
              titulo: 'Ingresos vs egresos',
              subtitulo: 'Por semana',
            ),
            const SizedBox(height: 10),
            _GraficoBarrasSemanas(mes: prov.mesActual, anio: prov.anioActual),
            const SizedBox(height: 20),

            // 5. Últimos movimientos
            const _TituloSeccion(
              icono: Icons.history,
              titulo: 'Últimos movimientos',
              subtitulo: '',
            ),
            const SizedBox(height: 10),
            const _UltimosMovimientos(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ── Título de sección ─────────────────────────────────────────────────────────

class _TituloSeccion extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String subtitulo;
  const _TituloSeccion({required this.icono, required this.titulo, required this.subtitulo});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icono, size: 18, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 8),
      Text(titulo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      if (subtitulo.isNotEmpty) ...[
        const SizedBox(width: 6),
        Text('· $subtitulo',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
      ],
    ]);
  }
}

// ── Saldos por cuenta (primero) ───────────────────────────────────────────────

class _GraficoSaldosCuentas extends StatelessWidget {
  const _GraficoSaldosCuentas();

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'es');

    return FutureBuilder<Map<String, double>>(
      future: context.read<MovimientosProvider>().getSaldosPorCuenta(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(height: 100,
            child: Center(child: CircularProgressIndicator()));
        }
        final saldos = snap.data!;

        final maxAbs = saldos.values.fold<double>(
            0, (m, v) => v.abs() > m ? v.abs() : m);

        // Total patrimonio
        final total = saldos.values.fold<double>(0, (s, v) => s + v);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              // Patrimonio total
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Patrimonio neto',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  Text(
                    '${total >= 0 ? '' : '-'}\$${fmt.format(total.abs())}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: total >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 14),
              // Barra por cuenta
              ...saldos.entries.map((entry) {
                final saldo = entry.value;
                final pct = maxAbs == 0 ? 0.0 : saldo.abs() / maxAbs;
                final color = saldo >= 0 ? Colors.green : Colors.red;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(entry.key,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w500)),
                          Text(
                            '${saldo < 0 ? '-' : ''}\$${fmt.format(saldo.abs())}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: color),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct.clamp(0.0, 1.0),
                          backgroundColor: Colors.grey.shade100,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

// ── Resumen del mes ───────────────────────────────────────────────────────────

class _ResumenMes extends StatelessWidget {
  const _ResumenMes();

  @override
  Widget build(BuildContext context) {
    final prov = context.read<MovimientosProvider>();
    final fmt = NumberFormat('#,##0.00', 'es');

    return FutureBuilder<Map<String, double>>(
      future: prov.getResumenMes(),
      builder: (context, snap) {
        final ingresos = snap.data?['ingresos'] ?? 0;
        final egresos  = snap.data?['egresos'] ?? 0;
        final balance  = ingresos - egresos;

        return Row(children: [
          _StatCard(label: 'Ingresos',
              valor: '\$${fmt.format(ingresos)}',
              color: Colors.green, icon: Icons.arrow_downward),
          const SizedBox(width: 8),
          _StatCard(label: 'Egresos',
              valor: '\$${fmt.format(egresos)}',
              color: Colors.red, icon: Icons.arrow_upward),
          const SizedBox(width: 8),
          _StatCard(label: 'Balance',
              valor: '${balance >= 0 ? '+' : ''}\$${fmt.format(balance)}',
              color: balance >= 0 ? Colors.green : Colors.red,
              icon: Icons.account_balance_wallet, bold: true),
        ]);
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String valor;
  final Color color;
  final IconData icon;
  final bool bold;
  const _StatCard({required this.label, required this.valor,
      required this.color, required this.icon, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          // ignore: deprecated_member_use
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          // ignore: deprecated_member_use
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 10, color: color)),
          ]),
          const SizedBox(height: 4),
          Text(valor, style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: color)),
        ]),
      ),
    );
  }
}

// ── Gráfico Pastel ────────────────────────────────────────────────────────────

class _GraficoPastel extends StatefulWidget {
  final int mes;
  final int anio;
  const _GraficoPastel({required this.mes, required this.anio});

  @override
  State<_GraficoPastel> createState() => _GraficoPastelState();
}

class _GraficoPastelState extends State<_GraficoPastel> {
  int _tocado = -1;
  static const _excluir = {'TRANSFERENCIA', 'INGRESOS', 'SALDO'};
  static const _colores = [
    Color(0xFF2563EB), Color(0xFFDC2626), Color(0xFFD97706),
    Color(0xFF059669), Color(0xFF7C3AED), Color(0xFFDB2777),
    Color(0xFF0891B2), Color(0xFF65A30D), Color(0xFFEA580C),
  ];

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: context.read<MovimientosProvider>().getGastosPorCategoria(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(height: 200,
            child: Center(child: CircularProgressIndicator()));
        }

        final datos = snap.data!
            .where((d) => !_excluir.contains((d['categoria'] as String).toUpperCase()))
            .toList();

        if (datos.isEmpty) {
          return Container(
          height: 100,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(child: Text('Sin gastos este mes',
              style: TextStyle(color: Colors.grey.shade400))),
        );
        }

        final total = datos.fold<double>(0, (s, d) => s + (d['total'] as double));

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            SizedBox(
              height: 200,
              child: PieChart(PieChartData(
                pieTouchData: PieTouchData(
                  touchCallback: (event, response) {
                    setState(() {
                      _tocado = response?.touchedSection?.touchedSectionIndex ?? -1;
                    });
                  },
                ),
                sections: List.generate(datos.length, (i) {
                  final pct = (datos[i]['total'] as double) / total * 100;
                  final tocado = i == _tocado;
                  return PieChartSectionData(
                    value: datos[i]['total'] as double,
                    title: tocado ? '${pct.toStringAsFixed(1)}%'
                        : pct >= 8 ? '${pct.toStringAsFixed(0)}%' : '',
                    color: _colores[i % _colores.length],
                    radius: tocado ? 75 : 60,
                    titleStyle: const TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w700, color: Colors.white),
                  );
                }),
                sectionsSpace: 2,
                centerSpaceRadius: 45,
              )),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12, runSpacing: 8,
              children: List.generate(datos.length, (i) {
                final fmt = NumberFormat('#,##0.00', 'es');
                return GestureDetector(
                  onTap: () => setState(() => _tocado = _tocado == i ? -1 : i),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 10, height: 10,
                        decoration: BoxDecoration(
                            color: _colores[i % _colores.length],
                            shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text('${datos[i]['categoria']}  \$${fmt.format(datos[i]['total'])}',
                        style: TextStyle(fontSize: 11,
                            fontWeight: i == _tocado ? FontWeight.w700 : FontWeight.normal)),
                  ]),
                );
              }),
            ),
          ]),
        );
      },
    );
  }
}

// ── Barras por semana ─────────────────────────────────────────────────────────

class _GraficoBarrasSemanas extends StatelessWidget {
  final int mes;
  final int anio;
  const _GraficoBarrasSemanas({required this.mes, required this.anio});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: context.read<MovimientosProvider>().getResumenPorSemana(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(height: 180,
            child: Center(child: CircularProgressIndicator()));
        }

        final datos = snap.data!;
        if (datos.isEmpty) {
          return Container(
          height: 100,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(child: Text('Sin datos este mes',
              style: TextStyle(color: Colors.grey.shade400))),
        );
        }

        final maxVal = datos.fold<double>(0, (m, d) {
          final ing = (d['ingresos'] as double?) ?? 0;
          final egr = (d['egresos'] as double?) ?? 0;
          return [m, ing, egr].reduce((a, b) => a > b ? a : b);
        });

        return Container(
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SizedBox(
            height: 180,
            child: BarChart(BarChartData(
              maxY: maxVal * 1.2,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final fmt = NumberFormat('#,##0', 'es');
                    final label = rodIndex == 0 ? 'Ingresos' : 'Egresos';
                    return BarTooltipItem('$label\n\$${fmt.format(rod.toY)}',
                        const TextStyle(color: Colors.white, fontSize: 11));
                  },
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true, reservedSize: 45,
                  getTitlesWidget: (val, meta) {
                    if (val == 0) return const SizedBox();
                    return Text(NumberFormat('#,##0', 'es').format(val),
                        style: const TextStyle(fontSize: 9));
                  },
                )),
                bottomTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (val, meta) =>
                      Text('S${val.toInt() + 1}', style: const TextStyle(fontSize: 11)),
                )),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: maxVal / 4,
                getDrawingHorizontalLine: (val) =>
                    FlLine(color: Colors.grey.shade200, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(datos.length, (i) {
                final d = datos[i];
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: (d['ingresos'] as double?) ?? 0,
                      color: Colors.green,
                      width: 10,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                    BarChartRodData(
                      toY: (d['egresos'] as double?) ?? 0,
                      color: Colors.red,
                      width: 10,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ],
                  barsSpace: 4,
                );
              }),
            )),
          ),
        );
      },
    );
  }
}

// ── Últimos movimientos ───────────────────────────────────────────────────────

class _UltimosMovimientos extends StatelessWidget {
  const _UltimosMovimientos();

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'es');
    final movimientos =
        context.watch<MovimientosProvider>().movimientos.take(5).toList();

    if (movimientos.isEmpty) return const SizedBox();

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: movimientos.map((m) {
          final esIngreso = m.tipo == TipoMovimiento.ingreso;
          final color = esIngreso ? Colors.green : Colors.red;
          return ListTile(
            dense: true,
            title: Text(m.categoria,
                style: const TextStyle(fontSize: 13)),
            subtitle: Text(m.cuenta,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            trailing: Text(
              '${esIngreso ? '+' : '-'}\$${fmt.format(m.monto)}',
              style: TextStyle(fontWeight: FontWeight.w600,
                  fontSize: 13, color: color),
            ),
          );
        }).toList(),
      ),
    );
  }
}
