import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/ad_widgets.dart';
import '../widgets/common.dart';

final _packagesProvider =
    FutureProvider.autoDispose<({Package? monthly, Package? annual})>((ref) {
      return ref.read(purchasesProvider).packages();
    });

class ProScreen extends ConsumerStatefulWidget {
  const ProScreen({super.key});

  @override
  ConsumerState<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends ConsumerState<ProScreen> {
  bool _yearly = true;
  bool _busy = false;

  Future<void> _afterPurchase() async {
    // Webhook'u beklemeden backend'i RevenueCat ile eşitle, sonra yetkiyi yenile
    try {
      await ref.read(apiProvider).post<dynamic>('/billing/sync');
    } catch (_) {}
    ref.invalidate(billingProvider);
    await ref.read(authProvider.notifier).refreshMe();
  }

  Future<void> _buy(Package pkg) async {
    final t = L10n.of(context);
    setState(() => _busy = true);
    try {
      if (await ref.read(purchasesProvider).buy(pkg)) {
        await _afterPurchase();
        if (mounted) toast(context, t('pro.welcome'));
      }
    } catch (e) {
      if (mounted) toast(context, t('pro.error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final t = L10n.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(purchasesProvider).restore();
      await _afterPurchase();
      if (mounted) toast(context, t('pro.restored'));
    } catch (_) {
      if (mounted) toast(context, t('pro.error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final locale = t.locale.languageCode;
    final status = ref.watch(billingProvider).asData?.value;
    final packs = ref.watch(_packagesProvider);
    final available = ref.read(purchasesProvider).available;

    Widget perk(String k) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: p.accent,
            child: Icon(LucideIcons.check, size: 16, color: p.accentInk),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('pro.perk.$k'),
                  style: font(16, weight: 600, color: p.ink),
                ),
                Text(
                  t('pro.perk.${k}_body'),
                  style: font(14, height: 1.4, color: p.inkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          const Align(alignment: Alignment.centerLeft, child: ProBadge()),
          const SizedBox(height: 12),
          Text(
            t('pro.title'),
            style: font(
              34,
              weight: 700,
              height: 1.02,
              spacing: -1.3,
              color: p.ink,
            ),
          ),
          const SizedBox(height: 10),
          Text(t('pro.lead'), style: font(16, height: 1.45, color: p.inkMuted)),
          const SizedBox(height: 22),
          if (status?.isPro ?? false)
            Container(
              color: p.surface,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.circleCheck, color: p.accent),
                      const SizedBox(width: 8),
                      Text(
                        t('pro.you_are_pro'),
                        style: font(17, weight: 600, color: p.ink),
                      ),
                    ],
                  ),
                  if (status!.periodEnd != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      t(status.willRenew ? 'pro.renews' : 'pro.ends', {
                        'date': DateFormat.yMMMMd(locale)
                            .format(status.periodEnd!),
                      }),
                      style: font(14, color: p.inkMuted),
                    ),
                  ],
                  if (status.status == 'grace') ...[
                    const SizedBox(height: 10),
                    Notice(t('pro.payment_issue'), tone: NoticeTone.error),
                  ],
                  const SizedBox(height: 12),
                  if (status.store == 'stripe')
                    Text(
                      t('pro.manage_web'),
                      style: font(13.5, height: 1.4, color: p.inkMuted),
                    )
                  else
                    OutlinedButton(
                      onPressed: () => launchUrl(
                        Uri.parse(
                          Platform.isIOS
                              ? 'https://apps.apple.com/account/subscriptions'
                              : 'https://play.google.com/store/account/subscriptions',
                        ),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Text(t('pro.manage')),
                    ),
                ],
              ),
            )
          else ...[
            if (!available)
              Notice(t('pro.unavailable'))
            else
              switch (packs) {
                AsyncData(:final value)
                    when value.monthly != null || value.annual != null =>
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          for (final (yearly, pkg) in [
                            (false, value.monthly),
                            (true, value.annual),
                          ])
                            if (pkg != null)
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    right: yearly ? 0 : 8,
                                  ),
                                  child: InkWell(
                                    onTap: () =>
                                        setState(() => _yearly = yearly),
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: p.surface,
                                        border: Border.all(
                                          color: _yearly == yearly
                                              ? p.ink
                                              : p.line,
                                          width: _yearly == yearly ? 1.5 : 1,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            t(
                                              yearly
                                                  ? 'pro.yearly'
                                                  : 'pro.monthly',
                                            ),
                                            style: font(13.5, color: p.inkMuted),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            pkg.storeProduct.priceString,
                                            style: font(
                                              22,
                                              weight: 600,
                                              color: p.ink,
                                            ),
                                          ),
                                          Text(
                                            t(
                                              yearly
                                                  ? 'pro.per_yearly'
                                                  : 'pro.per_monthly',
                                            ),
                                            style: font(12, color: p.inkMuted),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _buy(
                                (_yearly ? value.annual : value.monthly) ??
                                    (value.annual ?? value.monthly)!,
                              ),
                        child: BusyLabel(busy: _busy, label: t('pro.cta')),
                      ),
                    ],
                  ),
                AsyncError() || AsyncData() => Notice(t('pro.unavailable')),
                _ => const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              },
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy || !available ? null : _restore,
              child: Text(t('pro.restore')),
            ),
            Text(
              t(
                Platform.isIOS
                    ? 'pro.fine_print_ios'
                    : 'pro.fine_print_android',
              ),
              style: font(12, height: 1.45, color: p.inkMuted),
            ),
          ],
          const SizedBox(height: 28),
          for (final k in ['no_ads', 'badge', 'uploads', 'support']) perk(k),
        ],
      ),
    );
  }
}
