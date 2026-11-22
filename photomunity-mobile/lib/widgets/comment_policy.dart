import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n.dart';
import '../core/theme.dart';

/// Yükleme ve düzenlemede: kim yorum yapabilir (herkes / takipçiler / kapalı).
class CommentPolicyPicker extends StatelessWidget {
  const CommentPolicyPicker({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    Widget opt(String v, IconData icon) {
      final on = value == v;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: on ? p.accentTint : p.surface2,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onChanged(v),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: on ? p.accent : Colors.transparent, width: 2),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: on ? p.accentText : p.ink),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('comments.policy_$v'), style: font(15, weight: 700, color: p.ink)),
                        Text(t('comments.policy_${v}_hint'), style: font(12.5, color: p.inkMuted)),
                      ],
                    ),
                  ),
                  Icon(
                    on ? Icons.radio_button_checked : Icons.radio_button_off,
                    size: 22,
                    color: on ? p.accent : p.inkSubtle,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
          child: Text(t('comments.title'), style: font(13, weight: 700, color: p.inkMuted)),
        ),
        opt('everyone', LucideIcons.globe),
        opt('followers', LucideIcons.users),
        opt('off', LucideIcons.lock),
      ],
    );
  }
}
