// Indicator math mirrors ignored/prices.py.

class RawBar {
  const RawBar({
    required this.date,
    required this.close,
    this.volume,
    this.live = false,
  });

  final String date;
  final double close;
  final int? volume;
  final bool live;
}

class PriceRow {
  const PriceRow({
    required this.date,
    required this.close,
    this.dailyPct,
    required this.periodPct,
    this.ma10,
    this.ma20,
    required this.offHighPct,
    required this.upLowPct,
    this.volume,
    this.vol20,
    this.volRatio,
    this.highVol = false,
    this.dip = false,
    this.profit = false,
    this.live = false,
  });

  final String date;
  final double close;
  final double? dailyPct;
  final double periodPct;
  final double? ma10;
  final double? ma20;
  final double offHighPct;
  final double upLowPct;
  final int? volume;
  final int? vol20;
  final double? volRatio;
  final bool highVol;
  final bool dip;
  final bool profit;
  final bool live;

  PriceRow copyWith({bool? dip, bool? profit}) {
    return PriceRow(
      date: date,
      close: close,
      dailyPct: dailyPct,
      periodPct: periodPct,
      ma10: ma10,
      ma20: ma20,
      offHighPct: offHighPct,
      upLowPct: upLowPct,
      volume: volume,
      vol20: vol20,
      volRatio: volRatio,
      highVol: highVol,
      dip: dip ?? this.dip,
      profit: profit ?? this.profit,
      live: live,
    );
  }

  String get signal {
    if (dip && profit) return 'DIP+TAKE';
    if (dip) return 'DIP';
    if (profit) return 'TAKE';
    return '';
  }
}

class AutoLevels {
  const AutoLevels(this.dip, this.profit, this.median);

  final double dip;
  final double profit;
  final double? median;
}

double _roundHalf(double v) => (v * 2).round() / 2;

AutoLevels autoLevels(List<PriceRow> rows) {
  final done = rows.where((r) => !r.live).toList();
  final moves = <double>[];
  for (var i = 1; i < done.length; i++) {
    final prev = done[i - 1].close;
    if (prev > 0) {
      moves.add((done[i].close / prev - 1).abs() * 100);
    }
  }
  final recent = moves.length > 60 ? moves.sublist(moves.length - 60) : moves;
  if (recent.length < 20) return const AutoLevels(-2.0, 3.0, null);
  recent.sort();
  final mid = recent.length ~/ 2;
  final median = recent.length.isOdd
      ? recent[mid]
      : (recent[mid - 1] + recent[mid]) / 2;
  var dip = -_roundHalf(median * 2.0);
  var profit = _roundHalf(median * 3.0);
  dip = dip.clamp(-8.0, -2.0);
  profit = profit.clamp(3.0, 10.0);
  return AutoLevels(dip, profit, (median * 100).round() / 100);
}

/// Build indicators on warmup bars, then keep [startDate]..[endDate].
/// Period percent is rebased to the first displayed close.
List<PriceRow> displayRows({
  required List<RawBar> bars,
  required String startDate,
  required String endDate,
  required double dipPct,
  required double profitPct,
}) {
  final built = buildRows(bars: bars, dipPct: dipPct, profitPct: profitPct);
  final shown = built
      .where(
        (r) =>
            r.date.compareTo(startDate) >= 0 && r.date.compareTo(endDate) <= 0,
      )
      .toList();
  if (shown.isEmpty) return shown;
  final base = shown.first.close;
  return [
    for (var i = 0; i < shown.length; i++)
      PriceRow(
        date: shown[i].date,
        close: shown[i].close,
        dailyPct: i == 0 ? null : shown[i].dailyPct,
        periodPct: ((shown[i].close / base - 1) * 10000).round() / 100,
        ma10: shown[i].ma10,
        ma20: shown[i].ma20,
        offHighPct: shown[i].offHighPct,
        upLowPct: shown[i].upLowPct,
        volume: shown[i].volume,
        vol20: shown[i].vol20,
        volRatio: shown[i].volRatio,
        highVol: shown[i].highVol,
        dip: shown[i].dip,
        profit: shown[i].profit,
        live: shown[i].live,
      ),
  ];
}

List<PriceRow> buildRows({
  required List<RawBar> bars,
  required double dipPct,
  required double profitPct,
}) {
  final rows = <PriceRow>[];
  for (var i = 0; i < bars.length; i++) {
    final closes = [for (var j = 0; j <= i; j++) bars[j].close];
    final vols = [for (var j = 0; j <= i; j++) bars[j].volume];

    double? ma10;
    if (i >= 9) {
      ma10 = (closes.sublist(i - 9, i + 1).reduce((a, b) => a + b) / 10 * 100)
              .round() /
          100;
    }
    double? ma20;
    if (i >= 19) {
      ma20 = (closes.sublist(i - 19, i + 1).reduce((a, b) => a + b) / 20 * 100)
              .round() /
          100;
    }

    final window = closes.sublist(i - (i >= 19 ? 19 : i), i + 1);
    final high = window.reduce((a, b) => a > b ? a : b);
    final low = window.reduce((a, b) => a < b ? a : b);
    final offHigh = (bars[i].close / high - 1) * 100;
    final upLow = (bars[i].close / low - 1) * 100;

    double? daily;
    if (i > 0) {
      daily = (bars[i].close / bars[i - 1].close - 1) * 100;
      daily = (daily * 100).round() / 100;
    }
    final period = (bars[i].close / bars.first.close - 1) * 100;

    int? vol20;
    double? volRatio;
    var highVol = false;
    final volWindow = vols.sublist(i - (i >= 19 ? 19 : i), i + 1);
    final valid = volWindow.whereType<int>().toList();
    if (valid.length == 20 && bars[i].volume != null) {
      final avg = valid.reduce((a, b) => a + b) / 20;
      vol20 = avg.round();
      volRatio = (bars[i].volume! / avg * 100).round() / 100;
      highVol = volRatio >= 1.5;
    }

    rows.add(
      PriceRow(
        date: bars[i].date,
        close: (bars[i].close * 100).round() / 100,
        dailyPct: daily,
        periodPct: (period * 100).round() / 100,
        ma10: ma10,
        ma20: ma20,
        offHighPct: (offHigh * 100).round() / 100,
        upLowPct: (upLow * 100).round() / 100,
        volume: bars[i].volume,
        vol20: vol20,
        volRatio: volRatio,
        highVol: highVol,
        dip: (offHigh * 100).round() / 100 <= dipPct,
        profit: (upLow * 100).round() / 100 >= profitPct,
        live: bars[i].live,
      ),
    );
  }
  return rows;
}
