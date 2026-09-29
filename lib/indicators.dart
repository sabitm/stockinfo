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

// Rule constants mirror ignored/prices.py.
const pauseDays = 3;
const shockVol = 2.0;
const reentryVol = 1.0;
const trendDays = 10;

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
    this.action = 'HOLD',
    this.actionDetail = '',
    this.shock = false,
    this.downtrend = false,
    this.belowMa20 = false,
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
  final String action;
  final String actionDetail;
  final bool shock;
  final bool downtrend;
  final bool belowMa20;

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
      action: action,
      actionDetail: actionDetail,
      shock: shock,
      downtrend: downtrend,
      belowMa20: belowMa20,
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
  final rebased = [
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
  // Actions run on displayed rows only so the simulator matches the UI.
  return addActions(rebased, dipPct: dipPct, profitPct: profitPct);
}

List<PriceRow> buildRows({  required List<RawBar> bars,
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

/// Fixed rule set ported from add_actions() in ignored/prices.py.
/// Runs on displayed rows only. LIVE rows never trade.
/// Tranche slots recycle: TAKE-PROFIT frees one core slot, CUT frees
/// the re-entry slot. Cash tracker below must mirror simulate(), or
/// BUY permission will diverge from real cash.
List<PriceRow> addActions(
  List<PriceRow> input, {
  required double dipPct,
  required double profitPct,
}) {
  var inRally = false;
  var pauseLeft = 0;
  var openCore = 0;
  var cash = 4.0;
  var shares = 0.0;
  var hasReentry = false;
  var reentryOpen = false;
  double? reentryPrice;

  final rows = <PriceRow>[];
  for (var i = 0; i < input.length; i++) {
    final row = input[i];
    final daily = row.dailyPct ?? 0.0;
    final vol = row.volRatio;
    final shock =
        daily <= dipPct * 2 && vol != null && vol >= shockVol;
    final belowMa =
        row.ma20 != null && row.close < row.ma20!;
    var streak = 0;
    for (var j = i; j >= 0; j--) {
      final prev = j == i ? row : rows[j];
      if (prev.ma20 != null && prev.close < prev.ma20!) {
        streak += 1;
      } else {
        break;
      }
    }
    final downtrend = streak >= trendDays;
    final isTake = row.profit;
    var firstTake = false;
    if (isTake) {
      firstTake = !inRally;
      inRally = true;
    } else {
      if (!(row.dip && row.profit)) inRally = false;
    }

    var action = 'HOLD';
    var detail = '';
    if (i == 0) {
      if (row.profit) inRally = true;
      if (row.live) detail = 'live preview, confirm at close';
    } else if (row.live) {
      detail = 'live preview, confirm at close';
    } else if (shock) {
      action = 'PAUSE';
      detail =
          'shock ${daily >= 0 ? '+' : ''}${daily.toStringAsFixed(2)}% on ${vol.toStringAsFixed(1)}x, no buys for $pauseDays closes';
      pauseLeft = pauseDays;
    } else if (pauseLeft > 0) {
      action = 'PAUSE';
      detail = 'cooling down ($pauseLeft left)';
      pauseLeft -= 1;
    } else if (reentryOpen && row.dip && !row.profit) {
      final entry = reentryPrice;
      final gain =
          entry == null ? 0.0 : (row.close / entry - 1) * 100;
      if (gain >= profitPct) {
        detail = 're-entry up ${gain.toStringAsFixed(1)}%, holding through DIP';
      } else {
        action = 'CUT';
        detail = 'bounce failed, cut re-entry on next bounce';
        final entry = reentryPrice;
        var qty = entry == null ? 0.0 : 0.5 / entry;
        if (qty > shares) qty = shares;
        shares -= qty;
        cash += qty * row.close;
        reentryOpen = false;
        hasReentry = false;
        reentryPrice = null;
      }
    } else if (isTake && firstTake && shares > 0) {
      action = 'TAKE-PROFIT';
      detail = 'first TAKE of rally, sell 25% once';
      final qty = shares * 0.25;
      shares -= qty;
      cash += qty * row.close;
      if (openCore > 0) openCore -= 1;
    } else if (row.dip &&
        !row.profit &&
        !downtrend &&
        openCore < 2 &&
        cash - 1.0 >= 2.0) {
      final calm = vol == null || vol < 1.5;
      if (calm) {
        action = 'BUY';
        detail = 'calm DIP tranche ${openCore + 1}/2';
        openCore += 1;
        cash -= 1.0;
        shares += 1.0 / row.close;
      }
    } else if (row.dip &&
        row.profit &&
        !hasReentry &&
        vol != null &&
        vol >= reentryVol &&
        cash - 0.5 >= 2.0) {
      action = 'BUY';
      detail = 'half-size re-entry on strength';
      hasReentry = true;
      reentryOpen = true;
      reentryPrice = row.close;
      cash -= 0.5;
      shares += 0.5 / row.close;
    }

    rows.add(
      PriceRow(
        date: row.date,
        close: row.close,
        dailyPct: row.dailyPct,
        periodPct: row.periodPct,
        ma10: row.ma10,
        ma20: row.ma20,
        offHighPct: row.offHighPct,
        upLowPct: row.upLowPct,
        volume: row.volume,
        vol20: row.vol20,
        volRatio: row.volRatio,
        highVol: row.highVol,
        dip: row.dip,
        profit: row.profit,
        live: row.live,
        action: action,
        actionDetail: detail,
        shock: shock,
        downtrend: downtrend,
        belowMa20: belowMa,
      ),
    );
  }
  return rows;
}

class SimResult {
  const SimResult({
    required this.cash,
    required this.shares,
    required this.equityUnits,
    required this.buys,
    required this.sells,
    required this.lastPrice,
  });

  final double cash;
  final double shares;
  final double equityUnits;
  final int buys;
  final int sells;
  final double lastPrice;
}

class _Lot {
  _Lot(this.size, this.price);

  final double size;
  final double price;
}

/// Cash + position tracker ported from simulate() in ignored/prices.py.
SimResult simulate(List<PriceRow> rows) {
  var cash = 4.0;
  var shares = 0.0;
  final buys = <_Lot>[];
  var sells = 0;
  for (final row in rows) {
    final price = row.close;
    if (row.action == 'BUY') {
      final size = row.actionDetail.contains('half-size') ? 0.5 : 1.0;
      if (cash >= size) {
        cash -= size;
        shares += size / price;
        buys.add(_Lot(size, price));
      }
    } else if (row.action == 'TAKE-PROFIT' && shares > 0) {
      final qty = shares * 0.25;
      shares -= qty;
      cash += qty * price;
      sells += 1;
    } else if (row.action == 'CUT' && buys.isNotEmpty) {
      final last = buys.removeLast();
      var qty = last.size / last.price;
      if (qty > shares) qty = shares;
      shares -= qty;
      cash += qty * price;
      sells += 1;
    }
  }
  final lastPrice = rows.isEmpty ? 0.0 : rows.last.close;
  final equity = cash + shares * lastPrice;
  double round2(double v) => (v * 100).round() / 100;
  return SimResult(
    cash: round2(cash),
    shares: (shares * 10000).round() / 10000,
    equityUnits: round2(equity),
    buys: buys.length,
    sells: sells,
    lastPrice: lastPrice,
  );
}
