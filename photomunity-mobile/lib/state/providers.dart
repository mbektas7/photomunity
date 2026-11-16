import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/push.dart';
import '../core/monetization.dart';
import '../core/realtime.dart';
import '../core/token_store.dart';

final tokenStoreProvider = Provider((ref) => TokenStore());

/// Uygulama dili; kullanıcının profil ayarından ya da cihaz dilinden gelir.
final localeProvider = Provider<Locale>((ref) {
  final code =
      ref.watch(authProvider).asData?.value?.locale ??
      PlatformDispatcher.instance.locale.languageCode;
  return Locale(code == 'en' ? 'en' : 'tr');
});

final apiProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    tokens: ref.watch(tokenStoreProvider),
    localeCode: () => ref.read(localeProvider).languageCode,
    onSessionExpired: () => ref.read(authProvider.notifier).sessionExpired(),
  );
});

// ---------------------------------------------------------------- Push

/// Bildirime dokunulunca açılacak rota; router bunu dinleyip gider.
final pendingRouteProvider = NotifierProvider<PendingRoute, String?>(
  PendingRoute.new,
);

class PendingRoute extends Notifier<String?> {
  @override
  String? build() => null;

  void open(String route) => state = route;
  void clear() => state = null;
}

final pushProvider = Provider<PushService>((ref) {
  final push = PushService(
    api: ref.watch(apiProvider),
    onOpen: (data) =>
        ref.read(pendingRouteProvider.notifier).open(routeFor(data)),
    onForeground: () => ref.invalidate(unreadCountProvider),
  );
  ref.onDispose(push.dispose);
  return push;
});

// ---------------------------------------------------------------- Oturum

final authProvider = AsyncNotifierProvider<AuthController, Me?>(
  AuthController.new,
);

class AuthController extends AsyncNotifier<Me?> {
  ApiClient get _api => ref.read(apiProvider);

  /// Yeni hesap cihaz diliyle açılır (localeProvider bu provider'ı izlediği için oradan okunmaz).
  String get _deviceLocale =>
      PlatformDispatcher.instance.locale.languageCode == 'en' ? 'en' : 'tr';

  /// Yeni açılan hesap ilk girişte ayarlara (profil + ekipman) yönlendirilir; yönlendirici okur.
  bool welcomePending = false;
  TokenStore get _tokens => ref.read(tokenStoreProvider);

  @override
  Future<Me?> build() async {
    if (await _tokens.read() == null) return null;
    try {
      return Me.fromJson(await _api.get<Map<String, dynamic>>('/me'));
    } on ApiException catch (e) {
      if (e.status == 401) {
        await _tokens.clear();
        return null;
      }
      rethrow;
    }
  }

  Future<bool> _signIn(String path, Map<String, dynamic> body) async {
    final res = await _api.postPublic(path, body);
    await _tokens.save(Tokens.fromJson(res['tokens'] as Map<String, dynamic>));
    final isNew = res['is_new_user'] as bool? ?? false;
    welcomePending = isNew;
    state = AsyncData(await build());
    return isNew;
  }

  Future<bool> login(String email, String password) =>
      _signIn('/auth/login', {'email': email, 'password': password});

  Future<bool> register(Map<String, dynamic> body) async {
    final res = await _api.postPublic('/auth/register', {
      ...body,
      'locale': _deviceLocale,
    });
    await _tokens.save(Tokens.fromJson(res['tokens'] as Map<String, dynamic>));
    welcomePending = true;
    state = AsyncData(await build());
    return true;
  }

  Future<bool> oauth(String provider, String idToken, {String? displayName}) =>
      _signIn('/auth/oauth/$provider', {
        'id_token': idToken,
        'display_name': ?displayName,
        'locale': _deviceLocale,
      });

  Future<void> refreshMe() async {
    state = AsyncData(Me.fromJson(await _api.get<Map<String, dynamic>>('/me')));
  }

  void setMe(Me me) => state = AsyncData(me);

  Future<void> logout() async {
    await ref.read(pushProvider).disable();
    final t = await _tokens.read();
    if (t != null) {
      try {
        await _api.postPublic('/auth/logout', {'refresh_token': t.refresh});
      } catch (_) {}
    }
    await _tokens.clear();
    _resetUserData();
    state = const AsyncData(null);
  }

  Future<void> deleteAccount() async {
    await ref.read(pushProvider).disable();
    await _api.delete<dynamic>('/auth/account');
    await _tokens.clear();
    _resetUserData();
    state = const AsyncData(null);
  }

  Future<void> changePassword(String? current, String next) async {
    final res = await _api.post<Map<String, dynamic>>('/auth/change-password', {
      'current_password': current,
      'new_password': next,
    });
    await _tokens.save(Tokens.fromJson(res));
  }

  void sessionExpired() {
    _resetUserData();
    state = const AsyncData(null);
  }

  void _resetUserData() {
    ref.invalidate(likeOverridesProvider);
    ref.invalidate(photoPagesProvider);
    ref.invalidate(profileProvider);
    ref.invalidate(photoProvider);
    ref.invalidate(unreadCountProvider);
    ref.invalidate(notificationsProvider);
  }
}

// ---------------------------------------------------------------- Fotoğraf listeleri

class PagesState {
  const PagesState({
    this.items = const [],
    this.cursor,
    this.loading = false,
    this.done = false,
    this.error,
  });
  final List<PhotoCard> items;
  final String? cursor;
  final bool loading;
  final bool done;
  final ApiException? error;

  bool get initialLoading => loading && items.isEmpty;

  PagesState copyWith({
    List<PhotoCard>? items,
    String? cursor,
    bool? loading,
    bool? done,
    ApiException? error,
    bool clearError = false,
  }) => PagesState(
    items: items ?? this.items,
    cursor: cursor ?? this.cursor,
    loading: loading ?? this.loading,
    done: done ?? this.done,
    error: clearError ? null : (error ?? this.error),
  );
}

/// İmleç tabanlı sonsuz liste. Argüman: `feed`, `explore` veya `users/<kullanıcı>/photos`.
final photoPagesProvider =
    NotifierProvider.family<PhotoPages, PagesState, String>(PhotoPages.new);

class PhotoPages extends Notifier<PagesState> {
  PhotoPages(this.path);
  final String path;

  @override
  PagesState build() {
    Future.microtask(loadMore);
    return const PagesState(loading: true);
  }

  Future<void> refresh() async {
    state = const PagesState(loading: true);
    await _load(null);
  }

  Future<void> loadMore() async {
    if (state.done || (state.loading && state.items.isNotEmpty)) return;
    await _load(state.cursor);
  }

  Future<void> _load(String? cursor) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final res = await ref
          .read(apiProvider)
          .get<Map<String, dynamic>>('/$path', query: {'before': ?cursor});
      if (!ref.mounted) return;
      final items = (res['items'] as List)
          .map((e) => PhotoCard.fromJson(e as Map<String, dynamic>))
          .toList();
      final next = res['next_cursor'] as String?;
      state = PagesState(
        items: [...state.items, ...items],
        cursor: next,
        done: next == null,
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, error: ApiException.from(e));
    }
  }
}

// ---------------------------------------------------------------- Detaylar

final photoProvider = FutureProvider.autoDispose.family<PhotoDetail, String>((
  ref,
  id,
) async {
  return PhotoDetail.fromJson(
    await ref.read(apiProvider).get<Map<String, dynamic>>('/photos/$id'),
  );
});

final profileProvider = FutureProvider.autoDispose.family<Profile, String>((
  ref,
  username,
) async {
  return Profile.fromJson(
    await ref.read(apiProvider).get<Map<String, dynamic>>('/users/$username'),
  );
});

// ---------------------------------------------------------------- Beğeniler

typedef LikeState = ({bool liked, int count});

/// İyimser beğeni: aynı fotoğrafın akış, keşfet ve detaydaki tüm kopyaları bu tablodan okur.
final likeOverridesProvider =
    NotifierProvider<LikeOverrides, Map<String, LikeState>>(LikeOverrides.new);

class LikeOverrides extends Notifier<Map<String, LikeState>> {
  @override
  Map<String, LikeState> build() => const {};

  Future<void> toggle(String id, LikeState current) async {
    final next = (
      liked: !current.liked,
      count: current.count + (current.liked ? -1 : 1),
    );
    state = {...state, id: next};
    try {
      final api = ref.read(apiProvider);
      next.liked
          ? await api.post<dynamic>('/photos/$id/like')
          : await api.delete<dynamic>('/photos/$id/like');
    } catch (_) {
      state = {...state, id: current};
    }
  }
}

LikeState likeOf(WidgetRef ref, PhotoCard p) =>
    ref.watch(likeOverridesProvider)[p.id] ??
    (liked: p.likedByMe, count: p.likeCount);

// ---------------------------------------------------------------- Bildirimler

final unreadCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final res = await ref
      .read(apiProvider)
      .get<Map<String, dynamic>>('/notifications/unread-count');
  return res['count'] as int? ?? 0;
});

class NotificationsState {
  const NotificationsState({
    this.items = const [],
    this.cursor,
    this.loading = false,
    this.done = false,
    this.error,
  });
  final List<AppNotification> items;
  final String? cursor;
  final bool loading;
  final bool done;
  final Object? error;
}

final notificationsProvider =
    NotifierProvider<NotificationsController, NotificationsState>(
      NotificationsController.new,
    );

class NotificationsController extends Notifier<NotificationsState> {
  @override
  NotificationsState build() {
    Future.microtask(refresh);
    return const NotificationsState(loading: true);
  }

  Future<void> refresh() async {
    state = const NotificationsState(loading: true);
    await _load(null);
    // Liste açıldığında okunmamışlar okundu sayılır
    try {
      await ref
          .read(apiProvider)
          .post<dynamic>('/notifications/read', <String, dynamic>{});
      ref.invalidate(unreadCountProvider);
    } catch (_) {}
  }

  Future<void> loadMore() async {
    if (state.done || state.loading) return;
    await _load(state.cursor);
  }

  Future<void> _load(String? cursor) async {
    state = NotificationsState(
      items: state.items,
      cursor: state.cursor,
      loading: true,
    );
    try {
      final res = await ref
          .read(apiProvider)
          .get<Map<String, dynamic>>(
            '/notifications',
            query: {'before': ?cursor},
          );
      if (!ref.mounted) return;
      final items = (res['items'] as List)
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList();
      final next = res['next_cursor'] as String?;
      state = NotificationsState(
        items: [...state.items, ...items],
        cursor: next,
        done: next == null,
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = NotificationsState(
        items: state.items,
        cursor: state.cursor,
        error: e,
      );
    }
  }
}

// ---------------------------------------------------------------- Faz 2: Topluluklar ve yarışmalar

/// Argüman: (arama, yalnızca üye olduklarım)
final communitiesProvider = FutureProvider.autoDispose
    .family<List<CommunityCard>, (String, bool)>((ref, arg) async {
      final (q, mine) = arg;
      final res = await ref
          .read(apiProvider)
          .get<List<dynamic>>(
            '/communities',
            query: {
              'limit': 60,
              if (q.isNotEmpty) 'q': q,
              if (mine) 'mine': true,
            },
          );
      return res
          .map((e) => CommunityCard.fromJson(e as Map<String, dynamic>))
          .toList();
    });

final communityProvider = FutureProvider.autoDispose.family<Community, String>((
  ref,
  slug,
) async {
  return Community.fromJson(
    await ref.read(apiProvider).get<Map<String, dynamic>>('/communities/$slug'),
  );
});

final communityPostsProvider = FutureProvider.autoDispose
    .family<List<CommunityPost>, String>((ref, slug) async {
      final res = await ref
          .read(apiProvider)
          .get<Map<String, dynamic>>(
            '/communities/$slug/posts',
            query: {'limit': 50},
          );
      return (res['items'] as List)
          .map((e) => CommunityPost.fromJson(e as Map<String, dynamic>))
          .toList();
    });

final communityContestsProvider = FutureProvider.autoDispose
    .family<List<ContestCard>, String>((ref, slug) async {
      final res = await ref
          .read(apiProvider)
          .get<List<dynamic>>('/communities/$slug/contests');
      return res
          .map((e) => ContestCard.fromJson(e as Map<String, dynamic>))
          .toList();
    });

final membersProvider = FutureProvider.autoDispose.family<List<Member>, String>(
  (ref, slug) async {
    final res = await ref
        .read(apiProvider)
        .get<Map<String, dynamic>>(
          '/communities/$slug/members',
          query: {'limit': 200},
        );
    return (res['items'] as List)
        .map((e) => Member.fromJson(e as Map<String, dynamic>))
        .toList();
  },
);

final contestsProvider = FutureProvider.autoDispose
    .family<List<ContestCard>, String>((ref, status) async {
      final res = await ref
          .read(apiProvider)
          .get<List<dynamic>>('/contests', query: {'status': status});
      return res
          .map((e) => ContestCard.fromJson(e as Map<String, dynamic>))
          .toList();
    });

final contestProvider = FutureProvider.autoDispose.family<Contest, String>((
  ref,
  id,
) async {
  return Contest.fromJson(
    await ref.read(apiProvider).get<Map<String, dynamic>>('/contests/$id'),
  );
});

/// Katılımlar; oylama/jüri sırasında yerel olarak (iyimser) güncellenir.
final entriesProvider = AsyncNotifierProvider.autoDispose
    .family<EntriesController, List<Entry>, String>(EntriesController.new);

class EntriesController extends AsyncNotifier<List<Entry>> {
  EntriesController(this.contestId);
  final String contestId;

  @override
  Future<List<Entry>> build() async {
    final res = await ref
        .read(apiProvider)
        .get<List<dynamic>>('/contests/$contestId/entries');
    return res.map((e) => Entry.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> _optimistic(
    String entryId,
    Entry Function(Entry) change,
    Future<void> Function() call,
  ) async {
    final before = state.asData?.value;
    if (before == null) return;
    state = AsyncData([
      for (final e in before) e.id == entryId ? change(e) : e,
    ]);
    try {
      await call();
    } catch (e) {
      state = AsyncData(before);
      rethrow;
    }
  }

  Future<void> vote(String entryId, int stars) => _optimistic(
    entryId,
    (e) => e.copyWith(myStars: stars),
    () => ref.read(apiProvider).post<dynamic>('/contests/$contestId/votes', {
      'entry_id': entryId,
      'stars': stars,
    }),
  );

  Future<void> score(String entryId, int value) => _optimistic(
    entryId,
    (e) => e.copyWith(myScore: value),
    () => ref.read(apiProvider).put<dynamic>(
      '/contests/$contestId/jury/scores/$entryId',
      {'score': value},
    ),
  );
}

// ---------------------------------------------------------------- Faz 3: Mesajlaşma ve harita

final realtimeProvider = Provider<RealtimeService>((ref) {
  final rt = RealtimeService(
    ref.watch(tokenStoreProvider),
    beforeConnect: () =>
        ref.read(apiProvider).get<dynamic>('/messages/unread-count'),
  );
  // Oturuma göre bağlan / kes
  ref.listen(authProvider, (_, next) {
    next.asData?.value != null ? rt.start() : rt.stop();
  }, fireImmediately: true);
  // Gelen olayları önbelleğe işle
  final sub = rt.events.listen((e) {
    final cid = e['conversation_id'] as String?;
    if (e['type'] == 'message' && cid != null) {
      ref
          .read(messagesProvider(cid).notifier)
          .receive(ChatMessage.fromJson(e['message'] as Map<String, dynamic>));
      ref.invalidate(conversationsProvider);
      ref.invalidate(messageUnreadProvider);
      ref.invalidate(conversationProvider(cid));
    } else if (e['type'] == 'read' && cid != null) {
      ref.invalidate(conversationProvider(cid));
    }
  });
  ref.onDispose(() {
    sub.cancel();
    rt.dispose();
  });
  return rt;
});

final messageUnreadProvider =
    FutureProvider.autoDispose<({int inbox, int requests})>((ref) async {
      final r = await ref
          .read(apiProvider)
          .get<Map<String, dynamic>>('/messages/unread-count');
      return (
        inbox: r['inbox'] as int? ?? 0,
        requests: r['requests'] as int? ?? 0,
      );
    });

final conversationsProvider = FutureProvider.autoDispose
    .family<List<Conversation>, String>((ref, folder) async {
      final res = await ref
          .read(apiProvider)
          .get<List<dynamic>>('/conversations', query: {'folder': folder});
      return res
          .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
          .toList();
    });

final conversationProvider = FutureProvider.autoDispose
    .family<Conversation, String>((ref, id) async {
      return Conversation.fromJson(
        await ref
            .read(apiProvider)
            .get<Map<String, dynamic>>('/conversations/$id'),
      );
    });

class MessagesState {
  const MessagesState({
    this.items = const [],
    this.cursor,
    this.loading = false,
    this.done = false,
  });
  final List<ChatMessage> items; // eskiden yeniye
  final String? cursor;
  final bool loading;
  final bool done;
}

final messagesProvider =
    NotifierProvider.family<MessagesController, MessagesState, String>(
      MessagesController.new,
    );

class MessagesController extends Notifier<MessagesState> {
  MessagesController(this.conversationId);
  final String conversationId;

  @override
  MessagesState build() {
    Future.microtask(loadOlder);
    return const MessagesState(loading: true);
  }

  Future<void> loadOlder() async {
    if (state.done || (state.loading && state.items.isNotEmpty)) return;
    state = MessagesState(
      items: state.items,
      cursor: state.cursor,
      loading: true,
    );
    try {
      final res = await ref
          .read(apiProvider)
          .get<Map<String, dynamic>>(
            '/conversations/$conversationId/messages',
            query: {'before': ?state.cursor},
          );
      if (!ref.mounted) return;
      final older = (res['items'] as List)
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      final next = res['next_cursor'] as String?;
      state = MessagesState(
        items: [...older, ...state.items],
        cursor: next,
        done: next == null,
      );
    } catch (_) {
      if (ref.mounted) {
        state = MessagesState(items: state.items, cursor: state.cursor);
      }
    }
  }

  /// WebSocket ya da kendi gönderdiğimiz mesaj; tekrar eklenmez.
  void receive(ChatMessage m) {
    if (state.items.any((x) => x.id == m.id)) return;
    state = MessagesState(
      items: [...state.items, m],
      cursor: state.cursor,
      done: state.done,
    );
  }
}

final photographerMapProvider = FutureProvider.autoDispose
    .family<
      ({List<MapCluster> clusters, List<MapPhotographer> items, int total}),
      (String, int, String)
    >((ref, arg) async {
      final (bbox, zoom, specialty) = arg;
      final r = await ref
          .read(apiProvider)
          .get<Map<String, dynamic>>(
            '/map/photographers',
            query: {
              'bbox': bbox,
              'zoom': zoom,
              if (specialty.isNotEmpty) 'specialty': specialty,
            },
          );
      return (
        clusters: (r['clusters'] as List)
            .map((e) => MapCluster.fromJson(e as Map<String, dynamic>))
            .toList(),
        items: (r['photographers'] as List)
            .map((e) => MapPhotographer.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: r['total'] as int,
      );
    });

final photoMapProvider = FutureProvider.autoDispose
    .family<
      ({List<MapCluster> clusters, List<MapPhotoPoint> items, int total}),
      (String, int)
    >((ref, arg) async {
      final (bbox, zoom) = arg;
      final r = await ref
          .read(apiProvider)
          .get<Map<String, dynamic>>(
            '/map/photos',
            query: {'bbox': bbox, 'zoom': zoom},
          );
      return (
        clusters: (r['clusters'] as List)
            .map((e) => MapCluster.fromJson(e as Map<String, dynamic>))
            .toList(),
        items: (r['photos'] as List)
            .map((e) => MapPhotoPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: r['total'] as int,
      );
    });

// ---------------------------------------------------------------- Faz 4: Reklamlar ve Pro

final adsProvider = Provider<AdsService>((ref) => AdsService());

final purchasesProvider = Provider<PurchasesService>((ref) {
  final svc = PurchasesService();
  ref.listen(authProvider, (prev, next) {
    final id = next.asData?.value?.id;
    if (id != null && id != prev?.asData?.value?.id) {
      svc.identify(id);
    } else if (id == null && prev?.asData?.value != null) {
      svc.reset();
    }
  }, fireImmediately: true);
  return svc;
});

typedef BillingStatus = ({
  bool isPro,
  String? store,
  String? status,
  DateTime? periodEnd,
  bool willRenew,
});

final billingProvider = FutureProvider.autoDispose<BillingStatus>((ref) async {
  final r = await ref
      .read(apiProvider)
      .get<Map<String, dynamic>>('/billing/status');
  return (
    isPro: r['is_pro'] as bool? ?? false,
    store: r['store'] as String?,
    status: r['status'] as String?,
    periodEnd: r['period_end'] == null
        ? null
        : DateTime.parse(r['period_end'] as String).toLocal(),
    willRenew: r['will_renew'] as bool? ?? false,
  );
});
