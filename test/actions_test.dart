import 'package:flutter_test/flutter_test.dart';

import 'package:stockinfo/indicators.dart';

PriceRow _row({
  required String date,
  required double close,
  double? daily,
  double? ma20,
  bool dip = false,
  bool profit = false,
  double? vol,
  bool live = false,
}) {
  return PriceRow(
    date: date,
    close: close,
    dailyPct: daily,
    periodPct: 0,
    ma20: ma20,
    offHighPct: 0,
    upLowPct: 0,
    volRatio: vol,
    dip: dip,
    profit: profit,
    live: live,
  );
}

List<PriceRow> _trend({required int n, required double close}) {
  return [
    for (var i = 0; i < n; i++)
      _row(
        date: '2026-01-${(i + 1).toString().padLeft(2, '0')}',
        close: close,
        daily: 0.1,
        ma20: close - 1,
      ),
  ];
}

void main() {
  test('calm DIP buys max two tranches', () {
    final rows = addActions(
      [
        ..._trend(n: 20, close: 100),
        _row(date: '2026-02-01', close: 97, daily: -2.5, ma20: 99, dip: true, vol: 0.8),
        _row(date: '2026-02-02', close: 96, daily: -1.0, ma20: 99, dip: true, vol: 0.9),
        _row(date: '2026-02-03', close: 95, daily: -1.0, ma20: 99, dip: true, vol: 0.7),
      ],
      dipPct: -2.0,
      profitPct: 3.0,
    );
    expect(rows[0].action, 'HOLD'); // first displayed row never trades
    expect(rows[20].action, 'BUY');
    expect(rows[21].action, 'BUY');
    expect(rows[22].action, 'HOLD'); // tranche limit reached
  });

  test('shock pauses buys for three closes', () {
    final rows = addActions(
      [
        ..._trend(n: 20, close: 100),
        _row(date: '2026-02-01', close: 95, daily: -5.0, ma20: 99, dip: true, vol: 2.5),
        _row(date: '2026-02-02', close: 94, daily: -1.0, ma20: 99, dip: true, vol: 0.8),
        _row(date: '2026-02-03', close: 93, daily: -1.0, ma20: 99, dip: true, vol: 0.8),
        _row(date: '2026-02-04', close: 92, daily: -1.0, ma20: 99, dip: true, vol: 0.8),
        _row(date: '2026-02-05', close: 91, daily: -1.0, ma20: 99, dip: true, vol: 0.8),
        _row(date: '2026-02-06', close: 90, daily: -1.0, ma20: 99, dip: true, vol: 0.8),
      ],
      dipPct: -2.0,
      profitPct: 3.0,
    );
    expect(rows[20].action, 'PAUSE');
    expect(rows[21].action, 'PAUSE');
    expect(rows[22].action, 'PAUSE');
    expect(rows[23].action, 'PAUSE');
    expect(rows[24].action, 'BUY');
  });

  test('take-profit sells 25 percent once per rally', () {
    final rows = addActions(
      [
        ..._trend(n: 20, close: 100),
        _row(date: '2026-02-01', close: 97, daily: -2.5, ma20: 99, dip: true, vol: 0.8),
        _row(date: '2026-02-02', close: 100, daily: 3.0, ma20: 99, profit: true, vol: 1.0),
        _row(date: '2026-02-03', close: 101, daily: 1.0, ma20: 99, profit: true, vol: 1.0),
      ],
      dipPct: -2.0,
      profitPct: 3.0,
    );
    expect(rows[20].action, 'BUY');
    expect(rows[21].action, 'TAKE-PROFIT');
    expect(rows[22].action, 'HOLD');
  });

  test('live rows never trade', () {
    final rows = addActions(
      [
        ..._trend(n: 20, close: 100),
        _row(date: '2026-02-01', close: 97, daily: -2.5, ma20: 99, dip: true, vol: 0.8, live: true),
      ],
      dipPct: -2.0,
      profitPct: 3.0,
    );
    expect(rows[20].action, 'HOLD');
    expect(rows[20].actionDetail, contains('live preview'));
  });

  test('simulate tracks cash and shares', () {
    final rows = addActions(
      [
        ..._trend(n: 20, close: 100),
        _row(date: '2026-02-01', close: 100, daily: -2.5, ma20: 101, dip: true, vol: 0.8),
        _row(date: '2026-02-02', close: 103, daily: 3.0, ma20: 101, profit: true, vol: 1.0),
      ],
      dipPct: -2.0,
      profitPct: 3.0,
    );
    final sim = simulate(rows);
    expect(sim.buys, 1);
    expect(sim.sells, 1);
    // 1 unit buys 0.01 shares at 100, sells 25 percent at 103.
    // simulate() rounds cash to 2 decimals like the script.
    expect(sim.cash, 3.26);
    expect(sim.shares, closeTo(0.0075, 0.0001));
  });

  test('downtrend blocks calm DIP buys', () {
    final rows = addActions(
      [
        for (var i = 0; i < 20; i++)
          _row(
            date: '2026-01-${(i + 1).toString().padLeft(2, '0')}',
            close: 95,
            daily: -0.2,
            ma20: 100,
          ),
        _row(date: '2026-02-01', close: 93, daily: -2.0, ma20: 100, dip: true, vol: 0.8),
      ],
      dipPct: -2.0,
      profitPct: 3.0,
    );
    expect(rows.last.downtrend, isTrue);
    expect(rows.last.action, 'HOLD');
  });

  test('take-profit frees one core tranche slot', () {
    // Two core buys fill slots and leave cash at 2.0. A big rally makes
    // the 25 percent sale cover the 2.0 reserve, so the next DIP can buy.
    // Old code never freed slots, so it gave HOLD here.
    final rows = addActions(
      [
        ..._trend(n: 20, close: 100),
        _row(date: '2026-02-01', close: 97, daily: -2.5, ma20: 99, dip: true, vol: 0.8),
        _row(date: '2026-02-02', close: 96, daily: -1.0, ma20: 99, dip: true, vol: 0.8),
        _row(date: '2026-02-03', close: 200, daily: 108.0, ma20: 99, profit: true, vol: 1.0),
        _row(date: '2026-02-04', close: 97, daily: -3.0, ma20: 99, dip: true, vol: 0.8),
      ],
      dipPct: -2.0,
      profitPct: 3.0,
    );
    expect(rows[20].action, 'BUY');
    expect(rows[21].action, 'BUY');
    expect(rows[22].action, 'TAKE-PROFIT');
    expect(rows[23].action, 'BUY');
  });

  test('cash reserve blocks buys when cash runs low', () {
    // Two buys leave cash at 2.0. A modest rally frees a slot but the
    // sale only lifts cash to about 2.52, below the 3.0 needed for a
    // 1.0 buy with 2.0 reserve. Slot is free, cash blocks.
    final rows = addActions(
      [
        ..._trend(n: 20, close: 100),
        _row(date: '2026-02-01', close: 97, daily: -2.5, ma20: 99, dip: true, vol: 0.8),
        _row(date: '2026-02-02', close: 96, daily: -1.0, ma20: 99, dip: true, vol: 0.8),
        _row(date: '2026-02-03', close: 100, daily: 4.0, ma20: 99, profit: true, vol: 1.0),
        _row(date: '2026-02-04', close: 97, daily: -3.0, ma20: 99, dip: true, vol: 0.8),
      ],
      dipPct: -2.0,
      profitPct: 3.0,
    );
    expect(rows[20].action, 'BUY');
    expect(rows[21].action, 'BUY');
    expect(rows[22].action, 'TAKE-PROFIT');
    expect(rows[23].action, 'HOLD');
  });
}
