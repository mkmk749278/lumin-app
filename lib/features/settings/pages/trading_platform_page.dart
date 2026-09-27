/// Trading platform — choose the exchange Lumin trades on (2026-09-27).
///
/// A user auto-trades on ONE exchange: Binance (the default, unchanged) or
/// CoinDCX.  The same signals go to both; only where the order is placed
/// changes.  CoinDCX is Indian and can margin in rupees: signals keep their
/// USDT prices (that is what the contract trades at), while margin, size and
/// profit/loss are shown in ₹ at CoinDCX's own published conversion price.
///
/// Rules this page keeps (CLAUDE.md, *the engine is the source of truth* and
/// *an engine unknown is not an engine no*):
///
/// * every state shown is read back from the engine after a write — never
///   the tap;
/// * a status the engine could not read says so ("Couldn't check") and never
///   renders as "not connected";
/// * CoinDCX can only be chosen once the engine will actually trade on it for
///   this user; choosing it before that would take the user off Binance onto
///   an exchange that places nothing, so the engine refuses it and the page
///   explains why.
///
/// CoinDCX's API cannot report whether a key can withdraw or is locked to our
/// server, so connecting asks the user to confirm both (owner decision) —
/// the checklist is the engine's own wording, fetched from `/api/coindcx/info`.
library;


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/api_client.dart';
import '../../../data/app_config.dart';
import '../../../data/coindcx_models.dart';
import '../../../shared/friendly_error.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/page_skeleton.dart';
import '../../launch/region_gate.dart';
import 'tos_acceptance_page.dart';

class TradingPlatformPage extends StatefulWidget {
  const TradingPlatformPage({super.key});

  @override
  State<TradingPlatformPage> createState() => _TradingPlatformPageState();
}

class _TradingPlatformPageState extends State<TradingPlatformPage> {
  VenueSettings? _venue;
  CoinDCXInfo? _info;
  CoinDCXConnectStatus? _status;
  CoinDCXPositions? _positions;
  bool? _tosAccepted;
  String? _loadError;
  String? _actionMessage;
  bool _actionIsError = false;
  bool _busy = false;
  bool _showConnectForm = false;

  final _keyCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();
  final List<bool> _checks = [false, false, false];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _secretCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = AppConfigScope.of(context).repo;
    final tos = await isTosCurrentlyAccepted();
    try {
      final results = await Future.wait<Object>([
        repo.fetchVenue(),
        repo.fetchCoinDCXInfo(),
        repo.fetchCoinDCXStatus().catchError((Object _) => CoinDCXConnectStatus.unreadable),
        repo.fetchCoinDCXPositions().catchError(
            (Object _) => const CoinDCXPositions(readable: false, positions: [])),
      ]);
      if (!mounted) return;
      setState(() {
        _tosAccepted = tos;
        _venue = results[0] as VenueSettings;
        _info = results[1] as CoinDCXInfo;
        _status = results[2] as CoinDCXConnectStatus;
        _positions = results[3] as CoinDCXPositions;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tosAccepted = tos;
        _loadError = friendlyActionError(e, action: 'load your trading platform');
      });
    }
  }

  void _say(String msg, {bool error = false}) =>
      setState(() {
        _actionMessage = msg;
        _actionIsError = error;
      });

  String _detailOf(Object e) {
    // ApiError.message is already the engine's `detail` (api_client
    // _decodeError).  A 4xx here is the engine refusing with a sentence
    // written for the user (e.g. 409 "CoinDCX is not open for your
    // account yet") — show it rather than a generic failure.
    if (e is ApiError && e.statusCode >= 400 && e.statusCode < 500 &&
        e.statusCode != 401 && e.message.isNotEmpty) {
      return e.message;
    }
    if (e is CoinDCXConnectError) return e.detail;
    return friendlyActionError(e, action: 'save this');
  }

  Future<void> _choose(String venue) async {
    if (_busy || _venue?.venue == venue) return;
    setState(() => _busy = true);
    try {
      final v = await AppConfigScope.of(context).repo.updateVenue(venue: venue);
      if (!mounted) return;
      setState(() => _venue = v);
      _say(v.venue == 'coindcx'
          ? 'Auto-trade now places your trades on CoinDCX.'
          : 'Auto-trade now places your trades on Binance.');
    } catch (e) {
      if (!mounted) return;
      _say(_detailOf(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveSetting({String? margin, double? leverage}) async {
    setState(() => _busy = true);
    try {
      final v = await AppConfigScope.of(context)
          .repo
          .updateVenue(marginCurrency: margin, leverage: leverage);
      if (!mounted) return;
      setState(() => _venue = v);
    } catch (e) {
      if (!mounted) return;
      _say(_detailOf(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    final key = _keyCtrl.text.trim();
    final secret = _secretCtrl.text.trim();
    if (key.isEmpty || secret.isEmpty) {
      _say('Paste both the API key and the secret.', error: true);
      return;
    }
    if (_checks.contains(false)) {
      _say('Confirm every item on the safety checklist.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final ok = await AppConfigScope.of(context).repo.connectCoinDCX(
            apiKey: key,
            apiSecret: secret,
            attestIpBound: _checks[0],
            attestNoWithdraw: _checks[1],
            attestTradingConsent: _checks[2],
          );
      if (!mounted) return;
      _keyCtrl.clear();
      _secretCtrl.clear();
      setState(() => _showConnectForm = false);
      final bal = ok.balances.entries
          .map((e) => '${e.key} ${e.value.toStringAsFixed(2)}')
          .join(' · ');
      _say('CoinDCX key ${ok.keyPublicIdFirst8}… connected.'
          '${bal.isEmpty ? '' : ' Futures wallet: $bal.'}');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _say(_detailOf(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LuminColors.bgCard,
        title: const Text('Remove CoinDCX key?'),
        content: const Text(
            'Lumin will stop trading on CoinDCX for you. Open CoinDCX positions '
            'must be closed first.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await AppConfigScope.of(context).repo.disconnectCoinDCX();
      if (!mounted) return;
      _say('CoinDCX key removed.');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _say(_detailOf(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LuminColors.bgDeep,
      appBar: AppBar(title: const Text('Trading platform'), backgroundColor: LuminColors.bgDeep),
      body: RegionGate(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(LuminSpacing.lg),
            children: _body(),
          ),
        ),
      ),
    );
  }

  List<Widget> _body() {
    if (_loadError != null && _venue == null) {
      return [_note(_loadError!, color: LuminColors.loss), _retry()];
    }
    final venue = _venue;
    final info = _info;
    if (venue == null || info == null) {
      return const [PageSkeleton(inline: true, cards: 3, padding: EdgeInsets.zero)];
    }
    return [
      if (_actionMessage != null) ...[
        _note(_actionMessage!, color: _actionIsError ? LuminColors.loss : LuminColors.success),
        const SizedBox(height: LuminSpacing.md),
      ],
      if (!venue.readable)
        _note("Couldn't read your saved platform right now — showing Binance until it loads.",
            color: LuminColors.warn),
      _sectionTitle('WHERE LUMIN TRADES FOR YOU'),
      _platformTile(
        id: 'binance',
        title: 'Binance',
        subtitle: 'USDT futures. Pre-TP, TP ladder and trailing exits available.',
        selected: !venue.isCoinDCX,
        enabled: true,
      ),
      const SizedBox(height: LuminSpacing.sm),
      _platformTile(
        id: 'coindcx',
        title: 'CoinDCX',
        subtitle: 'Indian exchange. Margin and P&L in ₹ or USDT.',
        selected: venue.isCoinDCX,
        enabled: venue.coindcxConnected == true &&
            venue.coindcxAttested == true &&
            info.executionEnabled &&
            venue.coindcxAllowListed,
      ),
      const SizedBox(height: LuminSpacing.sm),
      _coindcxAvailability(venue, info),
      const SizedBox(height: LuminSpacing.xl),
      _sectionTitle('COINDCX CONNECTION'),
      _connectionSection(info),
      if (_status?.connected == true) ...[
        const SizedBox(height: LuminSpacing.xl),
        _sectionTitle('COINDCX SETTINGS'),
        _settingsSection(venue, info),
      ],
      if ((_positions?.positions ?? const []).isNotEmpty || _positions?.readable == false) ...[
        const SizedBox(height: LuminSpacing.xl),
        _sectionTitle('COINDCX TRADES'),
        _positionsSection(),
      ],
      const SizedBox(height: LuminSpacing.xl),
    ];
  }

  Widget _coindcxAvailability(VenueSettings v, CoinDCXInfo info) {
    if (v.isCoinDCX && !v.coindcxLive) {
      return _note(
        'CoinDCX auto-trade is paused right now, so no trades are being placed '
        'for you. Switch to Binance to keep trading, or wait for CoinDCX to resume.',
        color: LuminColors.warn,
      );
    }
    if (!info.executionEnabled || !v.coindcxAllowListed) {
      return _note(
        'CoinDCX auto-trade is being tested and is not open yet. You can connect '
        'your key now; you will be able to switch as soon as it opens.',
        color: LuminColors.textSecondary,
      );
    }
    if (v.coindcxConnected != true) {
      return _note('Connect your CoinDCX key below to choose CoinDCX.',
          color: LuminColors.textSecondary);
    }
    return const SizedBox.shrink();
  }

  Widget _platformTile({
    required String id,
    required String title,
    required String subtitle,
    required bool selected,
    required bool enabled,
  }) {
    final canTap = enabled && !selected && !_busy;
    return InkWell(
      key: Key('platform-$id'),
      borderRadius: BorderRadius.circular(LuminRadii.md),
      onTap: canTap ? () => _choose(id) : null,
      child: Container(
        padding: const EdgeInsets.all(LuminSpacing.md),
        decoration: BoxDecoration(
          color: LuminColors.bgCard,
          borderRadius: BorderRadius.circular(LuminRadii.md),
          border: Border.all(
            color: selected ? LuminColors.accent : LuminColors.cardBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected
                  ? LuminColors.accent
                  : (enabled ? LuminColors.textSecondary : LuminColors.textMuted)),
          const SizedBox(width: LuminSpacing.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                      color: enabled || selected ? LuminColors.textPrimary : LuminColors.textMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(color: LuminColors.textSecondary, fontSize: 12)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _connectionSection(CoinDCXInfo info) {
    final st = _status;
    if (_tosAccepted == false) {
      return _card([
        const Text('Accept the terms of service before connecting an exchange key.',
            style: TextStyle(color: LuminColors.textPrimary, fontSize: 13)),
        const SizedBox(height: LuminSpacing.sm),
        FilledButton(
          onPressed: () async {
            await Navigator.of(context)
                .push(MaterialPageRoute<bool>(builder: (_) => const TosAcceptancePage()));
            await _load();
          },
          child: const Text('Read terms'),
        ),
      ]);
    }
    if (st == null) return const PageSkeleton(inline: true, cards: 1, padding: EdgeInsets.zero);
    if (!st.readable) {
      return _card([
        const Text("Couldn't check your CoinDCX key right now.",
            style: TextStyle(color: LuminColors.warn, fontSize: 13)),
        const SizedBox(height: LuminSpacing.xs),
        const Text('Your key is not affected — this is only the status check.',
            style: TextStyle(color: LuminColors.textSecondary, fontSize: 12)),
        _retry(),
      ]);
    }
    if (st.connected == true && !_showConnectForm) {
      return _card([
        Row(children: [
          const Icon(Icons.check_circle, color: LuminColors.success, size: 18),
          const SizedBox(width: LuminSpacing.sm),
          Expanded(
            child: Text('Connected · key ${st.keyPublicIdFirst8 ?? ''}…',
                style: const TextStyle(color: LuminColors.textPrimary, fontWeight: FontWeight.w600)),
          ),
        ]),
        if (st.attested != true) ...[
          const SizedBox(height: LuminSpacing.sm),
          const Text('Reconnect this key and confirm the safety checklist to trade with it.',
              style: TextStyle(color: LuminColors.warn, fontSize: 12)),
        ],
        const SizedBox(height: LuminSpacing.sm),
        Row(children: [
          TextButton(
            onPressed: _busy ? null : () => setState(() => _showConnectForm = true),
            child: const Text('Replace key'),
          ),
          const Spacer(),
          TextButton(
            onPressed: _busy ? null : _disconnect,
            child: const Text('Remove key', style: TextStyle(color: LuminColors.loss)),
          ),
        ]),
      ]);
    }
    return _connectForm(info);
  }

  Widget _connectForm(CoinDCXInfo info) {
    final ip = info.engineIp;
    return _card([
      const Text('Create a CoinDCX API key for Lumin',
          style: TextStyle(color: LuminColors.textPrimary, fontWeight: FontWeight.w700)),
      const SizedBox(height: LuminSpacing.sm),
      _step('1', 'In CoinDCX, open API Dashboard and create a new key with futures trading on.'),
      _step('2', 'Choose "Bind IP address" and enter Lumin\'s server IP:'),
      if (ip != null)
        Padding(
          padding: const EdgeInsets.only(left: 28, bottom: LuminSpacing.sm),
          child: OutlinedButton.icon(
            key: const Key('copy-ip'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: ip));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Server IP $ip copied')));
            },
            icon: const Icon(Icons.copy, size: 16),
            label: Text(ip),
          ),
        ),
      _step('3', 'Do not give the key any withdrawal permission.'),
      _step('4', 'Paste the key and secret here.'),
      const SizedBox(height: LuminSpacing.sm),
      TextField(
        key: const Key('coindcx-key'),
        controller: _keyCtrl,
        decoration: const InputDecoration(labelText: 'API key'),
        autocorrect: false,
        enableSuggestions: false,
      ),
      const SizedBox(height: LuminSpacing.sm),
      TextField(
        key: const Key('coindcx-secret'),
        controller: _secretCtrl,
        decoration: const InputDecoration(labelText: 'API secret'),
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
      ),
      const SizedBox(height: LuminSpacing.md),
      const Text('Safety checklist',
          style: TextStyle(color: LuminColors.textPrimary, fontWeight: FontWeight.w600)),
      for (var i = 0; i < info.attestationItems.length && i < _checks.length; i++)
        CheckboxListTile(
          key: Key('attest-$i'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _checks[i],
          onChanged: (v) => setState(() => _checks[i] = v ?? false),
          title: Text(info.attestationItems[i],
              style: const TextStyle(color: LuminColors.textSecondary, fontSize: 12)),
        ),
      const SizedBox(height: LuminSpacing.sm),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: const Key('coindcx-connect'),
          onPressed: _busy ? null : _connect,
          child: Text(_busy ? 'Checking with CoinDCX…' : 'Connect CoinDCX'),
        ),
      ),
      const SizedBox(height: LuminSpacing.xs),
      const Text('Your secret is encrypted on our server and never stored on this phone.',
          style: TextStyle(color: LuminColors.textMuted, fontSize: 11)),
    ]);
  }

  Widget _settingsSection(VenueSettings v, CoinDCXInfo info) {
    final rate = info.inrPerUsdt;
    return _card([
      const Text('Margin currency',
          style: TextStyle(color: LuminColors.textPrimary, fontWeight: FontWeight.w600)),
      const SizedBox(height: LuminSpacing.sm),
      SegmentedButton<String>(
        key: const Key('margin-currency'),
        segments: [
          for (final c in info.marginCurrencies)
            ButtonSegment(value: c, label: Text(c == 'INR' ? '₹ INR' : c)),
        ],
        selected: {v.marginCurrency},
        onSelectionChanged: _busy ? null : (s) => _saveSetting(margin: s.first),
      ),
      const SizedBox(height: LuminSpacing.xs),
      Text(
        v.marginCurrency == 'INR'
            ? 'Margin and profit/loss in rupees'
                '${rate != null ? ' at CoinDCX\'s rate (₹${rate.toStringAsFixed(0)} per USDT)' : ''}. '
                'Signal prices stay in USDT — that is the price the contract trades at.'
            : 'Margin and profit/loss in USDT from your CoinDCX futures wallet.',
        style: const TextStyle(color: LuminColors.textSecondary, fontSize: 12),
      ),
      const SizedBox(height: LuminSpacing.lg),
      Text('Leverage: up to ${v.leverage.toStringAsFixed(0)}x',
          style: const TextStyle(color: LuminColors.textPrimary, fontWeight: FontWeight.w600)),
      Slider(
        key: const Key('leverage'),
        min: info.leverageMin,
        max: info.leverageMax,
        divisions: (info.leverageMax - info.leverageMin).round(),
        value: v.leverage.clamp(info.leverageMin, info.leverageMax),
        label: '${v.leverage.toStringAsFixed(0)}x',
        onChanged: _busy ? null : (x) => setState(() => _venue = _withLeverage(v, x.roundToDouble())),
        onChangeEnd: _busy ? null : (x) => _saveSetting(leverage: x.roundToDouble()),
      ),
      const Text(
        'Lumin lowers leverage by itself when a stop is wide, so every trade is '
        'stopped well before it could be liquidated. Your position size stays the same.',
        style: TextStyle(color: LuminColors.textSecondary, fontSize: 12),
      ),
      const SizedBox(height: LuminSpacing.lg),
      if (info.exitProfile.isNotEmpty)
        Text(info.exitProfile, style: const TextStyle(color: LuminColors.textMuted, fontSize: 11)),
    ]);
  }

  VenueSettings _withLeverage(VenueSettings v, double x) => VenueSettings(
        venue: v.venue,
        marginCurrency: v.marginCurrency,
        leverage: x,
        readable: v.readable,
        coindcxConnected: v.coindcxConnected,
        coindcxAttested: v.coindcxAttested,
        coindcxKeyReadable: v.coindcxKeyReadable,
        coindcxExecutionEnabled: v.coindcxExecutionEnabled,
        coindcxAllowListed: v.coindcxAllowListed,
      );

  Widget _positionsSection() {
    final p = _positions!;
    if (!p.readable) {
      return _note("Couldn't load your CoinDCX trades right now.", color: LuminColors.warn);
    }
    return Column(children: [for (final pos in p.positions) _positionRow(pos)]);
  }

  Widget _positionRow(CoinDCXPosition p) {
    final inr = p.marginCurrency == 'INR';
    // Net of CoinDCX's fees where both fills reported one; otherwise the
    // gross move, labelled as such — never a gross figure passed off as net.
    final net = inr ? p.netPnlInr : p.netPnlUsdt;
    final isNet = net != null;
    final pnl = net ?? (inr ? p.realizedPnlInr : p.realizedPnlUsdt);
    final pnlText = pnl == null
        ? (p.isLive ? 'Open' : '—')
        : '${pnl >= 0 ? '+' : ''}${inr ? '₹' : ''}${pnl.toStringAsFixed(2)}${inr ? '' : ' USDT'}';
    final pnlNote = pnl == null ? null : (isNet ? 'after fees' : 'before fees');
    final color = pnl == null
        ? LuminColors.textSecondary
        : (pnl >= 0 ? LuminColors.success : LuminColors.loss);
    final reason = p.isLive
        ? (p.slResting ? 'Stop placed on CoinDCX' : 'Placing stop…')
        : (p.closeReason.isEmpty ? p.state : _reasonLabel(p.closeReason));
    return Container(
      margin: const EdgeInsets.only(bottom: LuminSpacing.sm),
      padding: const EdgeInsets.all(LuminSpacing.md),
      decoration: BoxDecoration(
          color: LuminColors.bgCard, borderRadius: BorderRadius.circular(LuminRadii.sm)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p.symbol} · ${p.side}',
                style: const TextStyle(color: LuminColors.textPrimary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('$reason · ${p.leverage.toStringAsFixed(0)}x ${p.marginCurrency}',
                style: const TextStyle(color: LuminColors.textSecondary, fontSize: 12)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(pnlText, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          if (pnlNote != null)
            Text(pnlNote, style: const TextStyle(color: LuminColors.textMuted, fontSize: 11)),
        ]),
      ]),
    );
  }

  static String _reasonLabel(String r) => const {
        'SL': 'Stopped out',
        'TP1': 'Target hit',
        'EXIT': 'Closed',
        'AGE_CAP': 'Closed (time limit)',
        'LIQUIDATED': 'Liquidated',
        'PROTECTION_FAILED': 'Closed — stop could not be placed',
        'LIQUIDATION_INSIDE_STOP': 'Closed — liquidation was nearer than the stop',
        'EXTERNAL': 'Closed on CoinDCX',
      }[r] ??
      r;

  // --------------------------------------------------------------- pieces

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: LuminSpacing.sm),
        child: Text(t,
            style: const TextStyle(
                color: LuminColors.textMuted, fontSize: 11, letterSpacing: 1.1,
                fontWeight: FontWeight.w700)),
      );

  // A Material, not a decorated Container: the safety checklist is made of
  // CheckboxListTiles, which paint on the nearest Material — a coloured box
  // between them hides their ink and trips a framework assertion.
  Widget _card(List<Widget> children) => Material(
        color: LuminColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LuminRadii.md),
          side: const BorderSide(color: LuminColors.cardBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(LuminSpacing.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      );

  Widget _note(String text, {required Color color}) => Container(
        padding: const EdgeInsets.all(LuminSpacing.md),
        decoration: BoxDecoration(
          color: LuminColors.bgCard,
          borderRadius: BorderRadius.circular(LuminRadii.sm),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 12, height: 1.4)),
      );

  Widget _step(String n, String text) => Padding(
        padding: const EdgeInsets.only(bottom: LuminSpacing.xs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 22,
              child: Text('$n.',
                  style: const TextStyle(color: LuminColors.accent, fontWeight: FontWeight.w700))),
          Expanded(
              child: Text(text,
                  style: const TextStyle(color: LuminColors.textSecondary, fontSize: 12))),
        ]),
      );

  Widget _retry() => Align(
        alignment: Alignment.centerLeft,
        child: TextButton(onPressed: _load, child: const Text('Try again')),
      );
}
