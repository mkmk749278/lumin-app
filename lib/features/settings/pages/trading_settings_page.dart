/// Trading — the hub the Menu's single "Auto-trade & execution" row opens.
///
/// Why this page exists (handoff §29, 2026-09-19): the Menu used to list all
/// five of these pages at the top level, so the first thing a user saw after
/// two promotional banners was `Pre-TP grab`, `Invalidation` and
/// `Symbol preference` — three settings that mean nothing until you already
/// auto-trade, sitting above `Profile` and `Subscription`, which mean
/// something on day one.
///
/// Nothing is hidden and nothing is removed: every page below is the same
/// page, one tap further in. That is the whole trade — the Menu gets its
/// hierarchy back, and an advanced user reaches the same controls from one
/// obvious place instead of scanning a flat list of sixteen rows.
///
/// Each row carries a one-line description of what the setting does, because
/// `Pre-TP grab` and `Invalidation` are Lumin's own vocabulary and a name
/// alone teaches nobody what the switch changes (handoff §30).
library;

import 'package:flutter/material.dart';

import '../../../shared/tokens.dart';
import '../settings_rows.dart';
import 'auto_trade_settings_page.dart';
import 'invalidation_settings_page.dart';
import 'pretp_settings_page.dart';
import 'server_side_execution_page.dart';
import 'symbol_preference_page.dart';

class TradingSettingsPage extends StatelessWidget {
  const TradingSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Auto-trade & execution')),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          const SizedBox(height: LuminSpacing.md),
          SettingsSection(
            title: 'EXECUTION',
            rows: [
              SettingsRow(
                icon: Icons.auto_mode,
                label: 'Auto-trade',
                subtitle: 'Position size, leverage, and how much Lumin manages',
                onTap: () => _push(context, const AutoTradeSettingsPage()),
              ),
              SettingsRow(
                icon: Icons.cloud_done_outlined,
                label: 'Exchange connection',
                subtitle:
                    "Lumin's engine can manage eligible trades even when your "
                    'phone is offline',
                onTap: () => _push(context, const ServerSideExecutionPage()),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.md),
          SettingsSection(
            title: 'TRADING PREFERENCES',
            rows: [
              SettingsRow(
                icon: Icons.filter_list_alt,
                label: 'Symbol preference',
                subtitle: 'Which pairs are allowed to auto-trade for you',
                onTap: () => _push(context, const SymbolPreferencePage()),
              ),
              SettingsRow(
                icon: Icons.shield_moon_outlined,
                label: 'Pre-TP grab',
                subtitle:
                    'Allows profit to be secured before the primary target',
                onTap: () => _push(context, const PreTpSettingsPage()),
              ),
              SettingsRow(
                icon: Icons.shield_outlined,
                label: 'Invalidation',
                subtitle:
                    'Stops following a signal when its setup is no longer valid',
                onTap: () => _push(context, const InvalidationSettingsPage()),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.xl),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}
