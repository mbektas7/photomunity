import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import 'design.dart';

const licenseKeys = ['all_rights', 'cc_by', 'cc_by_nc', 'contact'];

/// Kullanım hakkı seçimi (yükleme, düzenleme, varsayılan ayar) ve "İndirmeyi kapat".
class LicensePicker extends StatelessWidget {
  const LicensePicker({
    super.key,
    required this.license,
    required this.downloadsDisabled,
    required this.onLicense,
    required this.onDownloads,
    this.showNote = true,
  });
  final String license;
  final bool downloadsDisabled;
  final ValueChanged<String> onLicense;
  final ValueChanged<bool> onDownloads;
  final bool showNote;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
          child: Text(t('license.title'), style: font(13, weight: 700, color: p.inkMuted)),
        ),
        for (final k in licenseKeys)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              button: true,
              selected: license == k,
              child: Material(
                color: license == k ? p.accentTint : p.surface,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => onLicense(k),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: license == k ? p.accent : p.line, width: 2),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          license == k ? Icons.radio_button_checked : Icons.radio_button_off,
                          size: 22,
                          color: license == k ? p.accent : p.inkSubtle,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t('license.$k'), style: font(14.5, weight: 700, color: p.ink)),
                              const SizedBox(height: 2),
                              Text(t('license.${k}_hint'), style: font(12.5, color: p.inkMuted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ToggleRow(
          title: t('license.downloads_off'),
          sub: t('license.downloads_off_hint'),
          value: downloadsDisabled,
          onChanged: onDownloads,
        ),
        if (showNote) ...[
          const SizedBox(height: 4),
          Text(t('license.note'), style: font(12, height: 1.4, color: p.inkMuted)),
        ],
      ],
    );
  }
}
