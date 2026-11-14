import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import 'core/l10n.dart';
import 'screens/auth_screens.dart';
import 'screens/community_screens.dart';
import 'screens/contest_screens.dart';
import 'screens/explore_screen.dart';
import 'screens/ar_screen.dart';
import 'screens/feed_screen.dart';
import 'screens/guide_screens.dart';
import 'screens/planner_screen.dart';
import 'screens/pro_screen.dart';
import 'screens/map_screen.dart';
import 'screens/messages_screens.dart';
import 'screens/notifications_screen.dart';
import 'screens/photo_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/upload_screen.dart';
import 'state/providers.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  // Oturum değiştiğinde yönlendirme kurallarını yeniden değerlendir
  final refresh = ValueNotifier(0);
  ref.listen(authProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  const publicPaths = {'/welcome', '/login', '/register', '/forgot-password'};

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/feed',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      if (auth.isLoading && !auth.hasValue) return '/splash';
      final signedIn = auth.asData?.value != null;
      final path = state.matchedLocation;
      if (path == '/splash') return signedIn ? '/feed' : '/welcome';
      if (path == '/settings' && !signedIn) return '/welcome';
      if (!signedIn && !publicPaths.contains(path)) return '/welcome';
      if (signedIn && publicPaths.contains(path)) {
        return ref.read(authProvider.notifier).welcomePending
            ? '/settings?welcome=1'
            : '/feed';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/feed', builder: (_, _) => const FeedScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/explore',
                builder: (_, _) => const ExploreScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/communities',
                builder: (_, _) => const CommunitiesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/upload', builder: (_, _) => const UploadScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/me', builder: (_, _) => const MyProfileScreen()),
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
          return MapScreen(
            initial: lat != null && lng != null ? LatLng(lat, lng) : null,
            photos: q['photos'] == '1',
          );
        },
      ),
      GoRoute(
        path: '/messages',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const ConversationsScreen(),
      ),
      GoRoute(
        path: '/messages/new/:username',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => ChatScreen(username: s.pathParameters['username']),
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
        path: '/c/:slug',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => CommunityScreen(slug: s.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/contests/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => ContestScreen(id: s.pathParameters['id']!),
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

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          // Aynı sekmeye tekrar dokunmak o sekmenin başına döner
          onDestinationSelected: (i) =>
              shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.photo_library_outlined),
              selectedIcon: const Icon(Icons.photo_library),
              label: t('nav.feed'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.explore_outlined),
              selectedIcon: const Icon(Icons.explore),
              label: t('nav.explore'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.groups_outlined),
              selectedIcon: const Icon(Icons.groups),
              label: t('nav.communities'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.add_box_outlined),
              selectedIcon: const Icon(Icons.add_box),
              label: t('nav.upload'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: t('nav.profile'),
            ),
          ],
        ),
      ),
    );
  }
}
