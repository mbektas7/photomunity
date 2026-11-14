import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../core/api_client.dart';
import '../core/config.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/justified_wall.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Text(
        'Fotografya',
        style: Theme.of(context).appBarTheme.titleTextStyle
            ?.copyWith(fontSize: 28),
      ),
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
                    Text(
                      'Fotografya',
                      style: Theme.of(context).appBarTheme.titleTextStyle,
                    ),
                    const SizedBox(height: 40),
                    Text(
                      t('welcome.title'),
                      style: font(
                        44,
                        weight: 700,
                        height: 0.96,
                        spacing: -1.9,
                        color: p.ink,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      t('welcome.lead'),
                      style: font(17, height: 1.5, color: p.inkMuted),
                    ),
                    const SizedBox(height: 26),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: () => context.push('/register'),
                          child: Text(t('welcome.register')),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          onPressed: () => context.push('/login'),
                          child: Text(t('welcome.login')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            sliver: SliverJustifiedWall(
              photos: wall.items,
              target: 170,
              completeRowsOnly: true,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

/// Giriş ve kayıt ekranlarının ortak iskeleti.
class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.title, this.lead, required this.children});
  final String title;
  final String? lead;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            Text(
              title,
              style: font(
                34,
                weight: 700,
                height: 1.05,
                spacing: -1.2,
                color: p.ink,
              ),
            ),
            if (lead != null) ...[
              const SizedBox(height: 8),
              Text(lead!, style: font(16, height: 1.45, color: p.inkMuted)),
            ],
            const SizedBox(height: 28),
            ...children,
          ],
        ),
      ),
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
        clientId: AppConfig.googleIosClientId.isEmpty
            ? null
            : AppConfig.googleIosClientId,
        serverClientId: AppConfig.googleServerClientId,
      );
      _googleReady = true;
    }
    final account = await g.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) throw ApiException(0, 'social', '');
    return ref
        .read(authProvider.notifier)
        .oauth('google', idToken, displayName: account.displayName);
  }

  Future<bool> _apple() async {
    final c = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );
    if (c.identityToken == null) throw ApiException(0, 'social', '');
    final name = [
      c.givenName,
      c.familyName,
    ].whereType<String>().join(' ').trim();
    return ref
        .read(authProvider.notifier)
        .oauth(
          'apple',
          c.identityToken!,
          displayName: name.isEmpty ? null : name,
        );
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    if (!_googleEnabled && !_appleEnabled) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_appleEnabled)
          FilledButton.icon(
            onPressed: _busy ? null : () => _run(_apple),
            icon: const Icon(Icons.apple, size: 22),
            label: Text(t('auth.continue_apple')),
          ),
        if (_appleEnabled && _googleEnabled) const SizedBox(height: 10),
        if (_googleEnabled)
          OutlinedButton(
            onPressed: _busy ? null : () => _run(_google),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('G', style: font(18, weight: 700, color: p.ink)),
                const SizedBox(width: 10),
                Text(t('auth.continue_google')),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(
            children: [
              Expanded(child: Divider(color: p.line)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  t('auth.or_email'),
                  style: font(13, color: p.inkMuted),
                ),
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
      await ref
          .read(authProvider.notifier)
          .login(_email.text.trim(), _password.text);
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
                  decoration: InputDecoration(labelText: t('auth.email')),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  validator: (v) => _emailRe.hasMatch(v?.trim() ?? '')
                      ? null
                      : t('auth.invalid_email'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _password,
                  decoration: InputDecoration(labelText: t('auth.password')),
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => _submit(),
                  validator: (v) =>
                      (v ?? '').isEmpty ? t('auth.required') : null,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.push('/forgot-password'),
                    child: Text(t('auth.forgot')),
                  ),
                ),
                if (_error != null) ...[
                  Notice(_error!, tone: NoticeTone.error),
                  const SizedBox(height: 14),
                ],
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: BusyLabel(busy: _busy, label: t('auth.login_submit')),
                ),
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
    String? fieldError(String code) =>
        _error?.code == code ? _error!.message : null;
    final general =
        _error != null &&
            !{'email_taken', 'username_taken'}.contains(_error!.code)
        ? errorText(context, _error!)
        : null;

    return _AuthScaffold(
      title: t('auth.register_title'),
      lead: t('auth.register_lead'),
      children: [
        SocialButtons(
          onError: (m) => setState(() => _error = ApiException(0, 'social', m)),
        ),
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
                  ),
                  autofillHints: const [AutofillHints.name],
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? t('auth.required') : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _username,
                  decoration: InputDecoration(
                    labelText: t('auth.username'),
                    helperText: t('auth.username_hint'),
                    errorText: fieldError('username_taken'),
                  ),
                  autofillHints: const [AutofillHints.newUsername],
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  validator: (v) => _usernameRe.hasMatch(v?.trim() ?? '')
                      ? null
                      : t('auth.invalid_username'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _email,
                  decoration: InputDecoration(
                    labelText: t('auth.email'),
                    errorText: fieldError('email_taken'),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  validator: (v) => _emailRe.hasMatch(v?.trim() ?? '')
                      ? null
                      : t('auth.invalid_email'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _password,
                  decoration: InputDecoration(
                    labelText: t('auth.password'),
                    helperText: t('auth.password_hint'),
                  ),
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  onFieldSubmitted: (_) => _submit(),
                  validator: (v) =>
                      (v ?? '').length >= 8 ? null : t('auth.short_password'),
                ),
                const SizedBox(height: 20),
                if (general != null) ...[
                  Notice(general, tone: NoticeTone.error),
                  const SizedBox(height: 14),
                ],
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: BusyLabel(
                    busy: _busy,
                    label: t('auth.register_submit'),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  t('auth.terms'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
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
      await ref.read(apiProvider).postPublic('/auth/forgot-password', {
        'email': _email.text.trim(),
      });
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
