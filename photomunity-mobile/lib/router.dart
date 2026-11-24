import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import 'widgets/design.dart';
import 'widgets/intro.dart';
import 'screens/auth_screens.dart';
import 'screens/community_screens.dart';
import 'screens/contest_screens.dart';
import 'screens/explore_screen.dart';
import 'screens/ar_screen.dart';
import 'screens/feed_screen.dart';
import 'screens/follow_list_screen.dart';
import 'screens/news_screens.dart';
import 'screens/guide_screens.dart';
import 'screens/planner_screen.dart';
import 'screens/pro_screen.dart';
import 'screens/manage_screens.dart';
import 'screens/map_screen.dart';
import 'screens/messages_screens.dart';
import 'screens/notifications_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/photo_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/communities_hub_screen.dart';
import 'screens/search_screen.dart';
import 'screens/tools_hub_screen.dart';
import 'screens/comments_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sky/dark_spots_screen.dart';
import 'screens/sky/moon_calendar_screen.dart';
import 'screens/sky/night_tools_screen.dart';
import 'screens/sky/sky_common.dart';
import 'screens/sky/sky_hub_screen.dart';
import 'screens/sky/sun_moon_screen.dart';
import 'screens/upload_screen.dart';
import 'screens/collection_screens.dart';
import 'screens/critique_screens.dart';
import 'screens/event_screens.dart';
import 'screens/gear_screen.dart';
import 'screens/sky/plan_screens.dart';
import 'screens/theme_screens.dart';
import 'screens/zoom_screen.dart';
import 'state/providers.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  // Oturum değiştiğinde yönlendirme kurallarını yeniden değerlendir
  final refresh = ValueNotifier(0);
  ref.listen(authProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  const publicPaths = {'/welcome', '/login', '/register', '/forgot-password'};
  // E-posta bağlantıları oturumdan bağımsız açılır
  const openPaths = {'/verify-email', '/reset-password'};
  // Giriş gerektiren bir bağlantıyla gelindiyse girişten sonra oraya dönülür
  String? afterLogin;

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/feed',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      if (auth.isLoading && !auth.hasValue) return '/splash';
      final signedIn = auth.asData?.value != null;
      final path = state.matchedLocation;
      // Web bağlantıları dil önekiyle gelebilir (/tr/p/…, /en/contests/…)
      final localized = RegExp(r'^/(tr|en)(/.*)?$').firstMatch(state.uri.path);
      if (localized != null) {
        final rest = localized.group(2) ?? '/feed';
        return state.uri.hasQuery ? '$rest?${state.uri.query}' : rest;
      }
      if (openPaths.contains(path)) return null;
      if (path == '/splash') {
        if (!signedIn) return '/welcome';
        final next = afterLogin;
        afterLogin = null;
        return next ?? '/feed';
      }
      if (path == '/settings' && !signedIn) return '/welcome';
      if (!signedIn && !publicPaths.contains(path)) {
        if (path.startsWith('/invite/') || path.startsWith('/contests/') || path.startsWith('/c/') ||
            path.startsWith('/p/') || path.startsWith('/u/')) {
          afterLogin = state.uri.toString();
        }
        return '/welcome';
      }
      if (signedIn && publicPaths.contains(path)) {
        if (ref.read(authProvider.notifier).welcomePending) return '/onboarding';
        final next = afterLogin;
        afterLogin = null;
        return next ?? '/feed';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(
        path: '/onboarding',
        builder: (_, s) => OnboardingScreen(key: ValueKey(s.uri.toString()), step: int.tryParse(s.uri.queryParameters['step'] ?? '') ?? 0),
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: '/verify-email',
        builder: (_, s) => VerifyEmailScreen(token: s.uri.queryParameters['token'] ?? ''),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (_, s) => ResetPasswordScreen(token: s.uri.queryParameters['token'] ?? ''),
      ),
      GoRoute(
        path: '/invite/:kind',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => InviteScreen(
          kind: s.pathParameters['kind']!,
          token: s.uri.queryParameters['token'] ?? '',
        ),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/feed', builder: (_, _) => const ModuleIntro(module: 'feed', child: FeedScreen())),
            ],
          ),
          StatefulShellBranch(
            routes: [
              // Alt menüdeki harita: tam ekran harita, menünün altında kalmayacak boşlukla
              GoRoute(
                path: '/maptab',
                builder: (_, _) => const ModuleIntro(module: 'map', child: MapScreen(inTab: true)),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/hub', builder: (_, _) => const ToolsHubScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/communities',
                builder: (_, s) => ModuleIntro(
                  module: 'communities',
                  child: CommunitiesScreen(segment: int.tryParse(s.uri.queryParameters['s'] ?? '')),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/me', builder: (_, _) => const ModuleIntro(module: 'profile', child: MyProfileScreen())),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/p/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => PhotoScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/p/:id/comments',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => CommentsScreen(photoId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/p/:id/critiques',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => ModuleIntro(module: 'critique', child: CritiqueScreen(photoId: s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/p/:id/zoom',
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, s) => CustomTransitionPage(
          key: s.pageKey,
          transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
          child: ZoomScreen(photoId: s.pathParameters['id']!),
        ),
      ),
      // ---- Revizyon 7
      GoRoute(
        path: '/themes',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const ModuleIntro(module: 'themes', child: WeeklyThemeScreen()),
      ),
      GoRoute(
        path: '/themes/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => ModuleIntro(module: 'themes', child: WeeklyThemeScreen(key: ValueKey(s.uri.toString()), id: s.pathParameters['id'])),
      ),
      GoRoute(
        path: '/critiques',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const ModuleIntro(module: 'critique', child: CritiqueRequestsScreen()),
      ),
      GoRoute(
        path: '/collections/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => ModuleIntro(module: 'collections', child: CollectionScreen(id: s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/events/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => ModuleIntro(module: 'events', child: EventScreen(id: s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/events/:id/edit',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => EventFormScreen(id: s.pathParameters['id']),
      ),
      GoRoute(
        path: '/c/:slug/events/new',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => EventFormScreen(slug: s.pathParameters['slug']),
      ),
      GoRoute(
        path: '/sky/plans',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => ModuleIntro(module: 'plans', child: PlansScreen(key: ValueKey(s.uri.toString()), scope: s.uri.queryParameters['scope'])),
      ),
      GoRoute(
        path: '/sky/plans/shared/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => SharedPlanScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/sky/plans/new',
        parentNavigatorKey: _rootKey,
        builder: (_, s) {
          final q = s.uri.queryParameters;
          DateTime? ms(String k) {
            final v = int.tryParse(q[k] ?? '');
            return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
          }

          return PlanEditScreen(
            key: ValueKey(s.uri.toString()),
            kind: q['kind'],
            lat: double.tryParse(q['lat'] ?? ''),
            lng: double.tryParse(q['lng'] ?? ''),
            name: q['name'],
            date: ms('date'),
            at: ms('at'),
          );
        },
      ),
      GoRoute(
        path: '/sky/plans/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => PlanEditScreen(key: ValueKey(s.uri.toString()), id: s.pathParameters['id']),
      ),
      GoRoute(
        path: '/gear',
        parentNavigatorKey: _rootKey,
        builder: (_, s) {
          final q = s.uri.queryParameters;
          return ModuleIntro(
            module: 'gear',
            child: GearScreen(key: ValueKey(s.uri.toString()), camera: q['camera'], lens: q['lens'], label: q['label']),
          );
        },
      ),
      GoRoute(
        path: '/upload',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => ModuleIntro(module: 'upload', child: UploadScreen(communitySlug: s.uri.queryParameters['community'])),
      ),
      GoRoute(
        path: '/explore',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const ModuleIntro(module: 'explore', child: ExploreScreen()),
      ),
      GoRoute(
        path: '/search',
        parentNavigatorKey: _rootKey,
        // Arama kutusu ana sayfanın üst çubuğundan açılıyormuş gibi: kısa bir solma geçişi
        pageBuilder: (_, s) => CustomTransitionPage(
          key: s.pageKey,
          transitionDuration: const Duration(milliseconds: 180),
          reverseTransitionDuration: const Duration(milliseconds: 150),
          transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
          child: UserSearchScreen(
            initialQuery: s.uri.queryParameters['q'] ?? '',
            communities: s.uri.queryParameters['k'] == 'c',
          ),
        ),
      ),
      GoRoute(
        path: '/u/:username/follows',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => FollowListScreen(
          username: s.pathParameters['username']!,
          tab: int.tryParse(s.uri.queryParameters['tab'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/u/:username',
        parentNavigatorKey: _rootKey,
        builder: (_, s) =>
            ProfileScreen(username: s.pathParameters['username']!),
      ),
      GoRoute(
        path: '/pro',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const ProScreen(),
      ),
      GoRoute(
        path: '/guide',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const GuideHubScreen(),
      ),
      GoRoute(
        path: '/guide/:slug',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => GuideScreen(slug: s.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/tools',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => ToolsScreen(focus: s.uri.queryParameters['c']),
      ),
      GoRoute(
        path: '/sky',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const ModuleIntro(module: 'sky', child: SkyHubScreen()),
      ),
      GoRoute(
        path: '/sky/dark',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const ModuleIntro(module: 'dark_spots', child: DarkSpotsScreen()),
      ),
      GoRoute(
        path: '/sky/moon',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const ModuleIntro(module: 'moon', child: MoonCalendarScreen()),
      ),
      GoRoute(
        path: '/sky/planner',
        parentNavigatorKey: _rootKey,
        builder: (_, s) {
          final ms = int.tryParse(s.uri.queryParameters['date'] ?? '');
          return ModuleIntro(
            module: 'sun_moon',
            child: SunMoonPlannerScreen(date: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms)),
          );
        },
      ),
      GoRoute(
        path: '/sky/tools',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => ModuleIntro(
          module: 'night_tools',
          child: NightToolsScreen(key: ValueKey(s.uri.toString()), tab: s.uri.queryParameters['tab']),
        ),
      ),
      GoRoute(
        path: '/sky/ar',
        parentNavigatorKey: _rootKey,
        builder: (_, s) {
          final ms = int.tryParse(s.uri.queryParameters['date'] ?? '');
          return Consumer(
            builder: (_, ref, _) {
              final place = ref.read(skyPlaceProvider);
              return ArSkyScreen(
                lat: place.lat,
                lng: place.lng,
                date: ms == null ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(ms),
              );
            },
          );
        },
      ),
      GoRoute(
        path: '/planner',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const PlannerScreen(),
      ),
      GoRoute(
        path: '/planner/ar',
        parentNavigatorKey: _rootKey,
        builder: (_, s) {
          final q = s.uri.queryParameters;
          return ArSkyScreen(
            lat: double.tryParse(q['lat'] ?? '') ?? 40.83,
            lng: double.tryParse(q['lng'] ?? '') ?? 41.16,
            date: DateTime.fromMillisecondsSinceEpoch(
              int.tryParse(q['date'] ?? '') ??
                  DateTime.now().millisecondsSinceEpoch,
            ),
          );
        },
      ),
      GoRoute(
        path: '/map',
        parentNavigatorKey: _rootKey,
        builder: (_, s) {
          final q = s.uri.queryParameters;
          final lat = double.tryParse(q['lat'] ?? '');
          final lng = double.tryParse(q['lng'] ?? '');
          return ModuleIntro(
            module: 'map',
            child: MapScreen(
              initial: lat != null && lng != null ? LatLng(lat, lng) : null,
              photos: q['photos'] == '1',
            ),
          );
        },
      ),
      GoRoute(
        path: '/messages',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const ModuleIntro(module: 'messages', child: ConversationsScreen()),
      ),
      GoRoute(
        path: '/messages/new/:username',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => ChatScreen(
          key: ValueKey(s.uri.toString()),
          username: s.pathParameters['username'],
          initialText: s.uri.queryParameters['text'],
        ),
      ),
      GoRoute(
        path: '/messages/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => ChatScreen(conversationId: s.pathParameters['id']),
      ),
      GoRoute(
        path: '/communities/new',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const NewCommunityScreen(),
      ),
      GoRoute(
        path: '/c/:slug/news/new',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => NewsComposeScreen(slug: s.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/c/:slug/posts/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => NewsDetailScreen(slug: s.pathParameters['slug']!, id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/c/:slug',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => CommunityScreen(slug: s.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/contests/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => ModuleIntro(module: 'contests', child: ContestScreen(id: s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/contests/:id/manage',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => ContestManageScreen(
          id: s.pathParameters['id']!,
          created: s.uri.queryParameters['created'] == '1',
        ),
      ),
      GoRoute(
        path: '/c/:slug/contests/new',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => NewContestScreen(slug: s.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/c/:slug/settings',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => CommunitySettingsScreen(
          slug: s.pathParameters['slug']!,
          created: s.uri.queryParameters['created'] == '1',
        ),
      ),
      GoRoute(
        path: '/contests/:id/jury',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => JuryScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/notifications',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/settings',
        parentNavigatorKey: _rootKey,
        builder: (_, s) =>
            SettingsScreen(welcome: s.uri.queryParameters['welcome'] == '1'),
      ),
    ],
  );
});

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  // Dallar menü sırasıyla aynı: 0 akış, 1 harita, 2 araçlar (ortadaki logo), 3 topluluk, 4 profil.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: shell,
      bottomNavigationBar: FloatingBottomNav(
        current: shell.currentIndex,
        // Aynı hedefe tekrar dokunmak o sekmenin başına döner
        onSelect: (b) => shell.goBranch(b, initialLocation: b == shell.currentIndex),
      ),
    );
  }
}
