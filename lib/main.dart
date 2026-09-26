import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'indicators.dart';
import 'services/yahoo_service.dart';

void main() {
  runApp(const StockApp());
}

class StockApp extends StatelessWidget {
  const StockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StockInfo',
      theme: ThemeData(
        colorScheme: .fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: .fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const PreviewPage(),
    );
  }
}

class PreviewPage extends StatefulWidget {
  const PreviewPage({super.key});

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  final _ticker = TextEditingController(text: 'SPUS');
  final _dip = TextEditingController(text: '-2.0');
  final _profit = TextEditingController(text: '3.0');
  final _yahoo = YahooService();

  int? _range = 60;
  int _customDays = 45;
  bool _auto = true;
  bool _loading = true;
  String? _error;
  List<RawBar> _bars = const [];
  List<String> _reconstructed = const [];
  bool _liveFailed = false;
  bool _backfillFailed = false;
  String _loadedTicker = 'SPUS';
  int _loadId = 0;

  @override
  void initState() {
    super.initState();
    _restoreState();
  }

  // Restore last user state so the app opens where it was left.
  // Invalid stored values fall back to defaults.
  Future<void> _restoreState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ticker = prefs.getString('ticker');
      if (ticker != null && ticker.isNotEmpty) {
        _ticker.text = ticker;
        _loadedTicker = ticker;
      }
      final range = prefs.getInt('range');
      if (range == null || const [7, 14, 31, 60, 90].contains(range)) {
        _range = range ?? 60;
      }
      final custom = prefs.getInt('customDays');
      if (custom != null && custom >= 1 && custom <= 120) {
        _customDays = custom;
      }
      _auto = prefs.getBool('auto') ?? true;
      final dip = prefs.getString('dip');
      if (dip != null && dip.isNotEmpty) _dip.text = dip;
      final profit = prefs.getString('profit');
      if (profit != null && profit.isNotEmpty) _profit.text = profit;
    } catch (_) {
      // Storage unavailable, keep defaults.
    }
    if (mounted) setState(() {});
    await _load();
  }

  Future<void> _saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ticker', _ticker.text.trim().toUpperCase());
      if (_range == null) {
        await prefs.remove('range');
      } else {
        await prefs.setInt('range', _range!);
      }
      await prefs.setInt('customDays', _customDays);
      await prefs.setBool('auto', _auto);
      await prefs.setString('dip', _dip.text);
      await prefs.setString('profit', _profit.text);
    } catch (_) {
      // Storage failures must not block loading prices.
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _dip.dispose();
    _profit.dispose();
    _yahoo.close();
    super.dispose();
  }

  int get _days => _range ?? _customDays;

  String get _endDate => formatDate(todayEtDate());

  String get _startDate =>
      formatDate(todayEtDate().subtract(Duration(days: _days)));

  AutoLevels get _autoLevels => autoLevels(
    buildRows(bars: _bars, dipPct: -2.0, profitPct: 3.0),
  );

  double get _activeDip =>
      _auto ? _autoLevels.dip : -(double.tryParse(_dip.text)?.abs() ?? 2.0);

  double get _activeProfit =>
      _auto ? _autoLevels.profit : double.tryParse(_profit.text)?.abs() ?? 3.0;

  List<PriceRow> get _rows {
    if (_bars.isEmpty) return const [];
    return displayRows(
      bars: _bars,
      startDate: _startDate,
      endDate: _endDate,
      dipPct: _activeDip,
      profitPct: _activeProfit,
    );
  }

  List<String> get _shownReconstructed => _reconstructed
      .where(
        (d) => d.compareTo(_startDate) >= 0 && d.compareTo(_endDate) <= 0,
      )
      .toList();

  Future<void> _load() async {
    final id = ++_loadId;
    final symbol = _ticker.text.trim().toUpperCase();
    unawaited(_saveState());
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _yahoo.load(symbol: symbol, rangeDays: _days);
      if (!mounted || id != _loadId) return;
      setState(() {
        _bars = result.bars;
        _reconstructed = result.reconstructed;
        _liveFailed = result.liveFailed;
        _backfillFailed = result.backfillFailed;
        _loadedTicker = symbol;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _loadId) return;
      setState(() {
        _loading = false;
        _error = _message(e);
      });
    }
  }

  String _message(Object error) {
    final text = error.toString();
    const prefix = 'Exception: ';
    if (text.startsWith(prefix)) return text.substring(prefix.length);
    return 'Could not load prices. Check the ticker and network, then retry.';
  }

  Future<void> _pickCustom() async {
    final input = TextEditingController(text: '$_customDays');
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Custom range'),
        content: TextField(
          controller: input,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Days (1-120)',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(input.text);
              if (v == null || v < 1 || v > 120) return;
              Navigator.pop(context, v);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() {
        _customDays = result;
        _range = null;
      });
      await _saveState();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final scheme = Theme.of(context).colorScheme;
    final auto = _bars.isEmpty ? const AutoLevels(-2, 3, null) : _autoLevels;
    final last = rows.isEmpty ? null : rows.last;
    final reconstructed = _shownReconstructed;

    return Scaffold(
      appBar: AppBar(title: const Text('StockInfo')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ticker,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Ticker',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _loading ? null : _load,
                child: const Text('Load'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<int?>(
              segments: [
                const ButtonSegment(value: 7, label: Text('7D')),
                const ButtonSegment(value: 14, label: Text('14D')),
                const ButtonSegment(value: 31, label: Text('31D')),
                const ButtonSegment(value: 60, label: Text('60D')),
                const ButtonSegment(value: 90, label: Text('90D')),
                ButtonSegment(
                  value: null,
                  label: Text(_range == null ? '${_customDays}D' : 'Custom'),
                ),
              ],
              selected: {_range},
              onSelectionChanged: (s) {
                final v = s.first;
                if (v == null) {
                  _pickCustom();
                } else {
                  setState(() => _range = v);
                  _saveState();
                  _load();
                }
              },
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null) ...[
            Card(
              color: scheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_error!, style: TextStyle(color: scheme.onErrorContainer)),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (last != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _loadedTicker,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(width: 8),
                      if (last.live)
                        Chip(
                          label: const Text('LIVE'),
                          backgroundColor: scheme.primaryContainer,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    last.dailyPct == null
                        ? last.close.toStringAsFixed(2)
                        : '${last.close.toStringAsFixed(2)}  (${last.dailyPct! >= 0 ? '+' : ''}${last.dailyPct!.toStringAsFixed(2)}%)',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _auto
                        ? 'Levels auto: DIP ${auto.dip.toStringAsFixed(1)}%, profit +${auto.profit.toStringAsFixed(1)}%${auto.median == null ? '' : ', median move ${auto.median!.toStringAsFixed(2)}%'}'
                        : 'Levels manual: DIP ${_activeDip.toStringAsFixed(1)}%, profit +${_activeProfit.toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _stat(context, 'MA10', last.ma10?.toStringAsFixed(2) ?? '-'),
                      _stat(context, 'MA20', last.ma20?.toStringAsFixed(2) ?? '-'),
                      _stat(context, 'Off high', '${last.offHighPct.toStringAsFixed(2)}%'),
                      _stat(
                        context,
                        'Vol',
                        last.volRatio == null ? '-' : '${last.volRatio!.toStringAsFixed(1)}x',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Levels', style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      const Text('Auto'),
                      Switch(
                        value: _auto,
                        onChanged: (v) {
                          setState(() => _auto = v);
                          _saveState();
                        },
                      ),
                    ],
                  ),
                  if (!_auto)
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _dip,
                            keyboardType: const TextInputType.numberWithOptions(
                              signed: true,
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'DIP %',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (_) {
                              setState(() {});
                              _saveState();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _profit,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Profit %',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (_) {
                              setState(() {});
                              _saveState();
                            },
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (rows.isNotEmpty) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Price', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SizedBox(height: 220, child: PriceChart(rows: rows)),
                  const SizedBox(height: 8),
                  const LegendRow(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ],
          if (_loading && rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            ...rows.reversed.map((r) => PriceTile(row: r)),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 12),
            ActionsCard(rows: rows),
            const SizedBox(height: 12),
            SimCard(rows: rows),
          ],
          if (reconstructed.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Reconstructed from 5m bars (daily close was missing): ${reconstructed.join(', ')}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (rows.any((r) => r.live)) ...[
            const SizedBox(height: 8),
            Text(
              'LIVE row is provisional (last 5m price, partial volume).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_liveFailed || _backfillFailed) ...[
            const SizedBox(height: 8),
            Text(
              _liveFailed && _backfillFailed
                  ? 'Live price and 5m backfill failed. Showing daily closes only.'
                  : _liveFailed
                      ? 'Live price failed. Showing daily closes only.'
                      : '5m backfill failed. Missing daily closes stay empty.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class LegendRow extends StatelessWidget {
  const LegendRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 16,
      children: [
        _Legend(color: Colors.indigo, label: 'Close'),
        _Legend(color: Colors.teal, label: 'MA10'),
        _Legend(color: Colors.orange, label: 'MA20'),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 16, height: 3, color: color),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

class PriceChart extends StatelessWidget {
  const PriceChart({super.key, required this.rows});

  final List<PriceRow> rows;

  @override
  Widget build(BuildContext context) {
    final closes = [
      for (var i = 0; i < rows.length; i++) FlSpot(i.toDouble(), rows[i].close),
    ];
    final ma10 = [
      for (var i = 0; i < rows.length; i++)
        if (rows[i].ma10 != null) FlSpot(i.toDouble(), rows[i].ma10!),
    ];
    final ma20 = [
      for (var i = 0; i < rows.length; i++)
        if (rows[i].ma20 != null) FlSpot(i.toDouble(), rows[i].ma20!),
    ];

    var minY = rows.first.close;
    var maxY = rows.first.close;
    for (final r in rows) {
      if (r.close < minY) minY = r.close;
      if (r.close > maxY) maxY = r.close;
      if (r.ma10 != null && r.ma10! < minY) minY = r.ma10!;
      if (r.ma10 != null && r.ma10! > maxY) maxY = r.ma10!;
      if (r.ma20 != null && r.ma20! < minY) minY = r.ma20!;
      if (r.ma20 != null && r.ma20! > maxY) maxY = r.ma20!;
    }
    final pad = (maxY - minY) * 0.15;
    minY -= pad;
    maxY += pad;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (rows.length - 1).toDouble(),
        minY: minY,
        maxY: maxY,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, _) => Text(
                v.toStringAsFixed(0),
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (rows.length / 4).ceilToDouble(),
              getTitlesWidget: (v, _) {
                final i = v.round();
                if (i < 0 || i >= rows.length) return const SizedBox.shrink();
                return Text(
                  rows[i].date.substring(5),
                  style: const TextStyle(fontSize: 11),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map(
                  (s) => LineTooltipItem(
                    '${rows[s.x.round()].date}\n${s.y.toStringAsFixed(2)}',
                    const TextStyle(fontSize: 12),
                  ),
                )
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: closes,
            isCurved: true,
            color: Colors.indigo,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
          ),
          if (ma10.length > 1)
            LineChartBarData(
              spots: ma10,
              isCurved: true,
              color: Colors.teal,
              barWidth: 1.5,
              dotData: const FlDotData(show: false),
            ),
          if (ma20.length > 1)
            LineChartBarData(
              spots: ma20,
              isCurved: true,
              color: Colors.orange,
              barWidth: 1.5,
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
    );
  }
}

class PriceTile extends StatelessWidget {
  const PriceTile({super.key, required this.row});

  final PriceRow row;

  // Dark chip backgrounds with white text for contrast on both themes.
  Color _signalColor() {
    if (row.dip && row.profit) return Colors.purple.shade700;
    if (row.dip) return Colors.red.shade700;
    return Colors.green.shade800;
  }

  // Action chips use distinct hues from signal chips.
  Color _actionColor() {
    switch (row.action) {
      case 'BUY':
        return Colors.green.shade800;
      case 'TAKE-PROFIT':
        return Colors.indigo.shade700;
      case 'PAUSE':
        return Colors.amber.shade800;
      case 'CUT':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade600;
    }
  }

  String _volText() {
    if (row.volRatio != null) {
      final mark = row.highVol ? '*' : '';
      return 'Vol ${row.volRatio!.toStringAsFixed(1)}x$mark';
    }
    if (row.volume != null) return 'Vol ${_compact(row.volume!)}';
    return 'Vol -';
  }

  String _compact(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final up = (row.dailyPct ?? 0) >= 0;
    final pctColor = row.dailyPct == null
        ? scheme.outline
        : (up ? Colors.green.shade700 : Colors.red.shade700);
    final dailyText = row.dailyPct == null
        ? ''
        : '${row.dailyPct! >= 0 ? '+' : ''}${row.dailyPct!.toStringAsFixed(2)}%';
    final periodText = row.dailyPct == null
        ? 'start of period'
        : 'period ${row.periodPct >= 0 ? '+' : ''}${row.periodPct.toStringAsFixed(2)}%  \u00b7  ${_volText()}';
    final hasChips = row.signal.isNotEmpty || row.action != 'HOLD';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          row.date,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (row.live) ...[
                        const SizedBox(width: 8),
                        Chip(
                          label: const Text('LIVE'),
                          backgroundColor: scheme.primaryContainer,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  row.close.toStringAsFixed(2),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    periodText,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  dailyText,
                  style: TextStyle(color: pctColor, fontSize: 12),
                ),
              ],
            ),
            if (hasChips) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (row.signal.isNotEmpty)
                    Chip(
                      label: Text(
                        row.signal,
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: _signalColor(),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (row.action != 'HOLD')
                    Chip(
                      label: Text(
                        row.action,
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: _actionColor(),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ActionsCard extends StatelessWidget {
  const ActionsCard({super.key, required this.rows});

  final List<PriceRow> rows;

  @override
  Widget build(BuildContext context) {
    final acted = rows.where((r) => r.action != 'HOLD').toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Actions', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (acted.isEmpty)
              Text(
                'No actions in this range. Rules only trade calm DIPs and strength re-entries.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              ...acted.reversed.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 92,
                        child: Text(
                          r.date,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${r.action} @ ${r.close.toStringAsFixed(2)} - ${r.actionDetail}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class SimCard extends StatelessWidget {
  const SimCard({super.key, required this.rows});

  final List<PriceRow> rows;

  @override
  Widget build(BuildContext context) {
    final sim = simulate(rows);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Simulation', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '4 units start. Each BUY uses 1 unit, half-size re-entry uses 0.5.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _item(context, 'Cash', sim.cash.toStringAsFixed(2)),
                _item(context, 'Shares', sim.shares.toStringAsFixed(4)),
                _item(
                  context,
                  'Equity',
                  '${sim.equityUnits.toStringAsFixed(2)} @ ${sim.lastPrice.toStringAsFixed(2)}',
                ),
                _item(context, 'Buys', '${sim.buys}'),
                _item(context, 'Sells', '${sim.sells}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}
