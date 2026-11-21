import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../core/api_client.dart';
import '../core/config.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/brand_logo.dart';
import '../widgets/common.dart';
import '../widgets/design.dart';
import '../widgets/justified_wall.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: BrandLogo(height: 120, stacked: true),
    ),
  );
}

/// İlk açılış: başlık + herkese açık son kareler duvarı.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    final wall = ref.watch(photoPagesProvider('explore'));
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverSafeArea(
            bottom: false,
            sliver: SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BrandLogo(height: 30),
                    const SizedBox(height: 40),
                    Text(t('welcome.title'), style: font(44, weight: 700, height: 0.96, spacing: -1.9, color: p.ink)),
                    const SizedBox(height: 18),
                    Text(t('welcome.lead'), style: font(17, height: 1.5, color: p.inkMuted)),
                    const SizedBox(height: 26),
                    LargeButton(label: t('welcome.register'), onPressed: () => context.push('/register')),
                    const SizedBox(height: Space.s3),
                    SizedBox(
                      height: 56,
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: p.surface,
                          foregroundColor: p.ink,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.box)),
                          textStyle: font(17, weight: 700),
                        ),
                        onPressed: () => context.push('/login'),
                        child: Text(t('welcome.login')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            sliver: SliverJustifiedWall(photos: wall.items, target: 170, completeRowsOnly: true),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

/// Giriş ve kayıt ekranlarının ortak iskeleti: marka satırı, isteğe bağlı
/// canlı fotoğraf şeridi, başlık, form ve alt bağlantı.
class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.title, this.lead, required this.children, this.ribbon = false, this.footer});
  final String title;
  final String? lead;
  final List<Widget> children;
  final bool ribbon;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final canPop = context.canPop();
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(top: Space.s2, bottom: Space.s8),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s5),
              child: SizedBox(
                height: 44,
                child: Row(
                  children: [
                    if (canPop) ...[
                      RoundIconButton(
                        icon: LucideIcons.arrowLeft,
                        label: MaterialLocalizations.of(context).backButtonTooltip,
                        onPressed: () => context.pop(),
                      ),
                      const SizedBox(width: Space.s3),
                    ],
                    const BrandLogo(height: 30),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.s6),
            if (ribbon) ...[const _PhotoRibbon(), const SizedBox(height: Space.s6)],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: AppText.display(p.ink)),
                  if (lead != null) ...[
                    const SizedBox(height: Space.s2),
                    Text(lead!, style: font(16, height: 1.45, color: p.inkMuted)),
                  ],
                  const SizedBox(height: Space.s6),
                  ...children,
                  if (footer != null) ...[const SizedBox(height: Space.s5), footer!],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Herkese açık son kareler: kendi en-boy oranında (kırpılmadan), altında
/// çekim bilgisi. Yavaşça kayar; "hareketi azalt" açıksa durur.
class _PhotoRibbon extends ConsumerStatefulWidget {
  const _PhotoRibbon();

  @override
  ConsumerState<_PhotoRibbon> createState() => _PhotoRibbonState();
}

class _PhotoRibbonState extends ConsumerState<_PhotoRibbon> {
  static const _h = 148.0;
  final _scroll = ScrollController();
  Timer? _retry;

  @override
  void initState() {
    super.initState();
    _retry = Timer(const Duration(seconds: 1), _drift);
  }

  @override
  void dispose() {
    _retry?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _drift() async {
    if (!mounted || !_scroll.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    final max = _scroll.position.maxScrollExtent;
    if (max <= 0) {
      _retry = Timer(const Duration(seconds: 1), _drift);
      return;
    }
    final target = _scroll.offset >= max - 1 ? 0.0 : max;
    final ms = ((target - _scroll.offset).abs() * 40).round();
    await _scroll.animateTo(
      target,
      duration: Duration(milliseconds: ms < 600 ? 600 : ms),
      curve: Curves.linear,
    );
    // Kullanıcı kaydırırsa animasyon kesilir; biraz bekleyip sürdür.
    if (mounted) _retry = Timer(const Duration(seconds: 2), _drift);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final locale = L10n.of(context).locale.languageCode;
    final photos = ref
        .watch(photoPagesProvider('explore'))
        .items
        .where((x) => x.thumb != null && x.thumb!.height > 0)
        .take(16)
        .toList();
    const pad = EdgeInsets.symmetric(horizontal: Space.s5);
    const gap = SizedBox(width: Space.s3);
    return SizedBox(
      height: _h + 26,
      child: photos.isEmpty
          ? ListView(
              scrollDirection: Axis.horizontal,
              padding: pad,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final w in const [210.0, 112.0, 196.0, 148.0]) ...[
                  Container(
                    width: w,
                    height: _h,
                    margin: const EdgeInsets.only(bottom: 26),
                    decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(Radii.photo)),
                  ),
                  gap,
                ],
              ],
            )
          : ListView.separated(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              padding: pad,
              itemCount: photos.length,
              separatorBuilder: (_, _) => gap,
              itemBuilder: (context, i) {
                final ph = photos[i];
                final v = ph.thumb!;
                final w = _h * v.width / v.height;
                final exif = exifChips(ph.exif, locale);
                return SizedBox(
                  width: w,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.photo),
                        child: SizedBox(
                          width: w,
                          height: _h,
                          child: NetPhoto(url: v.url, semanticLabel: ph.title ?? ph.user.displayName),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        exif.isNotEmpty ? exif.join(' · ') : '@${ph.user.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: font(12.5, weight: 600, color: p.inkMuted, tabular: true),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// Şifre alanı: kilit simgesi ve göster/gizle düğmesi.
class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    this.helper,
    this.isNew = false,
    this.onSubmitted,
    this.validator,
  });
  final TextEditingController controller;
  final String label;
  final String? helper;
  final bool isNew;
  final VoidCallback? onSubmitted;
  final String? Function(String?)? validator;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    return TextFormField(
      controller: widget.controller,
      obscureText: !_visible,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: [widget.isNew ? AutofillHints.newPassword : AutofillHints.password],
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
        prefixIcon: const Icon(LucideIcons.lockKeyhole, size: 20),
        suffixIcon: IconButton(
          tooltip: t(_visible ? 'auth.hide_password' : 'auth.show_password'),
          icon: Icon(_visible ? LucideIcons.eyeOff : LucideIcons.eye, size: 20),
          onPressed: () => setState(() => _visible = !_visible),
        ),
      ),
      onFieldSubmitted: (_) => widget.onSubmitted?.call(),
      validator: widget.validator,
    );
  }
}

/// "Hesabın yok mu? Hesap oluştur" türü alt bağlantı.
class _SwitchLink extends StatelessWidget {
  const _SwitchLink({required this.prompt, required this.action, required this.to});
  final String prompt;
  final String action;
  final String to;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(prompt, style: AppText.body(p.inkMuted)),
        TextButton(
          onPressed: () => context.pushReplacement(to),
          child: Text(action, style: AppText.bodyStrong(p.accentText)),
        ),
      ],
    );
  }
}

class SocialButtons extends ConsumerStatefulWidget {
  const SocialButtons({super.key, required this.onError});
  final void Function(String) onError;

  @override
  ConsumerState<SocialButtons> createState() => _SocialButtonsState();
}

class _SocialButtonsState extends ConsumerState<SocialButtons> {
  bool _busy = false;
  static bool _googleReady = false;

  bool get _googleEnabled => AppConfig.googleServerClientId.isNotEmpty;
  bool get _appleEnabled => Platform.isIOS;

  Future<void> _run(Future<bool> Function() signIn) async {
    final failed = L10n.of(context)('auth.social_failed');
    setState(() => _busy = true);
    try {
      await signIn(); // yönlendirme oturum durumuna göre router'da yapılır
    } on ApiException catch (e) {
      widget.onError(e.message.isNotEmpty ? e.message : failed);
    } catch (_) {
      // Kullanıcı pencereyi kapattı; sessizce geç
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _google() async {
    final g = GoogleSignIn.instance;
    if (!_googleReady) {
      await g.initialize(
        clientId: AppConfig.googleIosClientId.isEmpty ? null : AppConfig.googleIosClientId,
        serverClientId: AppConfig.googleServerClientId,
      );
      _googleReady = true;
    }
    final account = await g.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) throw ApiException(0, 'social', '');
    return ref.read(authProvider.notifier).oauth('google', idToken, displayName: account.displayName);
  }

  Future<bool> _apple() async {
    final c = await SignInWithApple.getAppleIDCredential(
      scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
    );
    if (c.identityToken == null) throw ApiException(0, 'social', '');
    final name = [c.givenName, c.familyName].whereType<String>().join(' ').trim();
    return ref.read(authProvider.notifier).oauth('apple', c.identityToken!, displayName: name.isEmpty ? null : name);
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    if (!_googleEnabled && !_appleEnabled) return const SizedBox.shrink();
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.box));
    Widget label(Widget icon, String text) => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        icon,
        const SizedBox(width: 10),
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_appleEnabled)
          SizedBox(
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: p.ink,
                foregroundColor: p.bg,
                shape: shape,
                textStyle: font(16, weight: 600),
              ),
              onPressed: _busy ? null : () => _run(_apple),
              child: label(const Icon(Icons.apple, size: 24), t('auth.continue_apple')),
            ),
          ),
        if (_appleEnabled && _googleEnabled) const SizedBox(height: Space.s3),
        if (_googleEnabled)
          SizedBox(
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: p.surface,
                foregroundColor: p.ink,
                shape: shape,
                textStyle: font(16, weight: 600),
              ),
              onPressed: _busy ? null : () => _run(_google),
              child: label(Text('G', style: font(19, weight: 700, color: p.ink)), t('auth.continue_google')),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s5),
          child: Row(
            children: [
              Expanded(child: Divider(color: p.line)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(t('auth.or_email'), style: font(13, color: p.inkMuted)),
              ),
              Expanded(child: Divider(color: p.line)),
            ],
          ),
        ),
      ],
    );
  }
}

final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _usernameRe = RegExp(r'^[a-zA-Z0-9_.]{3,30}$');

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).login(_email.text.trim(), _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    return _AuthScaffold(
      title: t('auth.login_title'),
      lead: t('auth.login_lead'),
      ribbon: true,
      footer: _SwitchLink(prompt: t('auth.no_account'), action: t('welcome.register'), to: '/register'),
      children: [
        SocialButtons(onError: (m) => setState(() => _error = m)),
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _email,
                  decoration: InputDecoration(
                    labelText: t('auth.email'),
                    prefixIcon: const Icon(LucideIcons.mail, size: 20),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  validator: (v) => _emailRe.hasMatch(v?.trim() ?? '') ? null : t('auth.invalid_email'),
                ),
                const SizedBox(height: Space.s3),
                _PasswordField(
                  controller: _password,
                  label: t('auth.password'),
                  onSubmitted: _submit,
                  validator: (v) => (v ?? '').isEmpty ? t('auth.required') : null,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => context.push('/forgot-password'), child: Text(t('auth.forgot'))),
                ),
                if (_error != null) ...[Notice(_error!, tone: NoticeTone.error), const SizedBox(height: Space.s3)],
                LargeButton(label: t('auth.login_submit'), busy: _busy, onPressed: _submit),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  ApiException? _error;

  @override
  void dispose() {
    for (final c in [_name, _username, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).register({
        'display_name': _name.text.trim(),
        'username': _username.text.trim().toLowerCase(),
        'email': _email.text.trim(),
        'password': _password.text,
      });
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    String? fieldError(String code) => _error?.code == code ? _error!.message : null;
    final general = _error != null && !{'email_taken', 'username_taken'}.contains(_error!.code)
        ? errorText(context, _error!)
        : null;

    return _AuthScaffold(
      title: t('auth.register_title'),
      lead: t('auth.register_lead'),
      footer: _SwitchLink(prompt: t('auth.have_account'), action: t('welcome.login'), to: '/login'),
      children: [
        SocialButtons(onError: (m) => setState(() => _error = ApiException(0, 'social', m))),
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: t('auth.display_name'),
                    prefixIcon: const Icon(LucideIcons.user, size: 20),
                  ),
                  autofillHints: const [AutofillHints.name],
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v ?? '').trim().isEmpty ? t('auth.required') : null,
                ),
                const SizedBox(height: Space.s3),
                TextFormField(
                  controller: _username,
                  decoration: InputDecoration(
                    labelText: t('auth.username'),
                    helperText: t('auth.username_hint'),
                    prefixIcon: const Icon(LucideIcons.atSign, size: 20),
                    errorText: fieldError('username_taken'),
                  ),
                  autofillHints: const [AutofillHints.newUsername],
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  validator: (v) => _usernameRe.hasMatch(v?.trim() ?? '') ? null : t('auth.invalid_username'),
                ),
                const SizedBox(height: Space.s3),
                TextFormField(
                  controller: _email,
                  decoration: InputDecoration(
                    labelText: t('auth.email'),
                    errorText: fieldError('email_taken'),
                    prefixIcon: const Icon(LucideIcons.mail, size: 20),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  validator: (v) => _emailRe.hasMatch(v?.trim() ?? '') ? null : t('auth.invalid_email'),
                ),
                const SizedBox(height: Space.s3),
                _PasswordField(
                  controller: _password,
                  label: t('auth.password'),
                  helper: t('auth.password_hint'),
                  isNew: true,
                  onSubmitted: _submit,
                  validator: (v) => (v ?? '').length >= 8 ? null : t('auth.short_password'),
                ),
                const SizedBox(height: 20),
                if (general != null) ...[Notice(general, tone: NoticeTone.error), const SizedBox(height: Space.s3)],
                LargeButton(label: t('auth.register_submit'), busy: _busy, onPressed: _submit),
                const SizedBox(height: Space.s3),
                Text(t('auth.terms'), style: Theme.of(context).textTheme.bodySmall),
                const LegalLinks(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_emailRe.hasMatch(_email.text.trim())) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).postPublic('/auth/forgot-password', {'email': _email.text.trim()});
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    return _AuthScaffold(
      title: t('auth.forgot_title'),
      lead: t('auth.forgot_lead'),
      children: _sent
          ? [Notice(t('auth.forgot_sent'), tone: NoticeTone.success)]
          : [
              TextField(
                controller: _email,
                decoration: InputDecoration(labelText: t('auth.email')),
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: BusyLabel(busy: _busy, label: t('auth.forgot_submit')),
              ),
            ],
    );
  }
}

// ---------------------------------------------------------------- E-posta bağlantıları

/// E-postadaki doğrulama bağlantısı: /verify-email?token=…
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, required this.token});
  final String token;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      await ref.read(apiProvider).postPublic('/auth/verify-email', {'token': widget.token});
      if (ref.read(authProvider).asData?.value != null) {
        await ref.read(authProvider.notifier).refreshMe();
      }
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final signedIn = ref.watch(authProvider).asData?.value != null;
    return _AuthScaffold(
      title: t('auth.verify_title'),
      children: [
        if (_error != null) ...[
          Notice(_error!, tone: NoticeTone.error),
          const SizedBox(height: 18),
          FilledButton(onPressed: () => context.go(signedIn ? '/feed' : '/welcome'), child: Text(t('auth.continue'))),
        ] else if (_done) ...[
          Notice(t('auth.verified'), tone: NoticeTone.success),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () => context.go(signedIn ? '/feed' : '/login'),
            child: Text(signedIn ? t('auth.continue') : t('auth.login_submit')),
          ),
        ] else
          Row(
            children: [
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4)),
              const SizedBox(width: 12),
              Text(t('auth.verifying'), style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
      ],
    );
  }
}

/// E-postadaki şifre sıfırlama bağlantısı: /reset-password?token=…
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.token});
  final String token;

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = L10n.of(context);
    if (_password.text.length < 8) {
      setState(() => _error = t('auth.short_password'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).postPublic('/auth/reset-password', {
        'token': widget.token,
        'new_password': _password.text,
      });
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    return _AuthScaffold(
      title: t('auth.reset_title'),
      children: _done
          ? [
              Notice(t('auth.reset_done'), tone: NoticeTone.success),
              const SizedBox(height: 18),
              FilledButton(onPressed: () => context.go('/login'), child: Text(t('auth.login_submit'))),
            ]
          : [
              TextField(
                controller: _password,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(labelText: t('auth.new_password'), errorText: _error),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: BusyLabel(busy: _busy, label: t('auth.reset_submit')),
              ),
            ],
    );
  }
}

/// Davet bağlantısı: /invite/community?token=… ya da /invite/judge?token=…
/// Giriş yapılmamışsa yönlendirici önce girişe gönderir, sonra buraya geri getirir.
class InviteScreen extends ConsumerStatefulWidget {
  const InviteScreen({super.key, required this.kind, required this.token});
  final String kind; // community | judge
  final String token;

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _accept();
  }

  Future<void> _accept() async {
    final api = ref.read(apiProvider);
    try {
      final String route;
      if (widget.kind == 'judge') {
        final c = await api.post<Map<String, dynamic>>('/contest-judge-invites/accept', {'token': widget.token});
        ref.invalidate(contestProvider);
        route = '/contests/${c['id']}';
      } else {
        final c = await api.post<Map<String, dynamic>>('/community-invites/accept', {'token': widget.token});
        ref.invalidate(communityProvider);
        route = '/c/${c['slug']}';
      }
      if (mounted) context.pushReplacement(route);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    return _AuthScaffold(
      title: t(widget.kind == 'judge' ? 'invite.judge_title' : 'invite.community_title'),
      children: [
        if (_error != null) ...[
          Notice(_error!, tone: NoticeTone.error),
          const SizedBox(height: 18),
          FilledButton(onPressed: () => context.go('/feed'), child: Text(t('auth.continue'))),
        ] else
          Row(
            children: [
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4)),
              const SizedBox(width: 12),
              Text(t('invite.accepting'), style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
      ],
    );
  }
}
