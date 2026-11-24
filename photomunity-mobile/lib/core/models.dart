// Backend şemalarının (app/schemas.py) Dart karşılıkları.

T? _opt<T>(Object? v) => v as T?;
double? _d(Object? v) => (v as num?)?.toDouble();

class UserCard {
  UserCard({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    required this.isPublic,
    required this.isPro,
  });
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final bool isPublic;
  final bool isPro;

  factory UserCard.fromJson(Map<String, dynamic> j) => UserCard(
    id: j['id'] as String,
    username: j['username'] as String,
    displayName: j['display_name'] as String,
    avatarUrl: _opt(j['avatar_url']),
    isPublic: j['is_public'] as bool? ?? true,
    isPro: j['is_pro'] as bool? ?? false,
  );
}

class Equipment {
  Equipment({
    this.id,
    required this.type,
    required this.brand,
    required this.model,
  });
  final String? id;
  final String type;
  final String brand;
  final String model;

  factory Equipment.fromJson(Map<String, dynamic> j) => Equipment(
    id: _opt(j['id']),
    type: j['type'] as String,
    brand: j['brand'] as String,
    model: j['model'] as String,
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'brand': brand,
    'model': model,
  };
}

class Me extends UserCard {
  Me({
    required super.id,
    required super.username,
    required super.displayName,
    super.avatarUrl,
    required super.isPublic,
    required super.isPro,
    required this.email,
    required this.emailVerified,
    this.coverUrl,
    this.bio,
    this.website,
    required this.specialties,
    required this.locale,
    this.city,
    this.country,
    this.latitude,
    this.longitude,
    required this.equipment,
    this.onboardingDone = true,
    this.hasPhotos = false,
  });

  final String email;
  final bool emailVerified;
  final String? coverUrl;
  final String? bio;
  final String? website;
  final List<String> specialties;
  final String locale;
  final String? city;
  final String? country;
  final double? latitude;
  final double? longitude;
  final List<Equipment> equipment;

  /// Kayıt sonrası tanıtım bitti ya da kapatıldı (eski hesaplar için hep true).
  final bool onboardingDone;
  final bool hasPhotos;

  /// "Profilini tamamla" adımları: profil fotoğrafı, hakkında, ekipman, ilk fotoğraf.
  List<bool> get onboardingSteps => [
    avatarUrl != null,
    (bio?.isNotEmpty ?? false) || specialties.isNotEmpty,
    equipment.isNotEmpty,
    hasPhotos,
  ];

  factory Me.fromJson(Map<String, dynamic> j) {
    final card = UserCard.fromJson(j);
    return Me(
      id: card.id,
      username: card.username,
      displayName: card.displayName,
      avatarUrl: card.avatarUrl,
      isPublic: card.isPublic,
      isPro: card.isPro,
      email: j['email'] as String,
      emailVerified: j['email_verified'] as bool? ?? false,
      coverUrl: _opt(j['cover_url']),
      bio: _opt(j['bio']),
      website: _opt(j['website']),
      specialties: ((j['specialties'] as List?) ?? const []).cast<String>(),
      locale: j['locale'] as String? ?? 'tr',
      city: _opt(j['city']),
      country: _opt(j['country']),
      latitude: _d(j['latitude']),
      longitude: _d(j['longitude']),
      equipment: ((j['equipment'] as List?) ?? const [])
          .map((e) => Equipment.fromJson(e as Map<String, dynamic>))
          .toList(),
      onboardingDone: j['onboarding_done'] as bool? ?? true,
      hasPhotos: j['has_photos'] as bool? ?? false,
    );
  }
}

class Profile extends UserCard {
  Profile({
    required super.id,
    required super.username,
    required super.displayName,
    super.avatarUrl,
    required super.isPublic,
    required super.isPro,
    this.bio,
    this.website,
    this.coverUrl,
    required this.specialties,
    this.city,
    this.country,
    required this.equipment,
    required this.followersCount,
    required this.followingCount,
    required this.photosCount,
    required this.isFollowing,
    required this.isMe,
    required this.canViewPhotos,
  });

  final String? bio;
  final String? website;
  final String? coverUrl;
  final List<String> specialties;
  final String? city;
  final String? country;
  final List<Equipment> equipment;
  final int followersCount;
  final int followingCount;
  final int photosCount;
  final bool isFollowing;
  final bool isMe;
  final bool canViewPhotos;

  factory Profile.fromJson(Map<String, dynamic> j) {
    final c = UserCard.fromJson(j);
    return Profile(
      id: c.id,
      username: c.username,
      displayName: c.displayName,
      avatarUrl: c.avatarUrl,
      isPublic: c.isPublic,
      isPro: c.isPro,
      coverUrl: _opt(j['cover_url']),
      bio: _opt(j['bio']),
      website: _opt(j['website']),
      specialties: ((j['specialties'] as List?) ?? const []).cast<String>(),
      city: _opt(j['city']),
      country: _opt(j['country']),
      equipment: ((j['equipment'] as List?) ?? const [])
          .map((e) => Equipment.fromJson(e as Map<String, dynamic>))
          .toList(),
      followersCount: j['followers_count'] as int? ?? 0,
      followingCount: j['following_count'] as int? ?? 0,
      photosCount: j['photos_count'] as int? ?? 0,
      isFollowing: j['is_following'] as bool? ?? false,
      isMe: j['is_me'] as bool? ?? false,
      canViewPhotos: j['can_view_photos'] as bool? ?? false,
    );
  }
}

class ImageVariant {
  ImageVariant(this.url, this.width, this.height);
  final String url;
  final int width;
  final int height;
  double get ratio => height == 0 ? 1.5 : width / height;

  factory ImageVariant.fromJson(Map<String, dynamic> j) =>
      ImageVariant(j['url'] as String, j['width'] as int, j['height'] as int);
}

class PhotoCard {
  PhotoCard({
    required this.id,
    required this.user,
    this.title,
    required this.images,
    required this.likeCount,
    required this.likedByMe,
    this.publishedAt,
    this.exif,
    this.place,
    this.commentCount = 0,
    this.commentsOff = false,
    this.lastComment,
  });
  final String id;
  final UserCard user;
  final String? title;
  final Map<String, ImageVariant> images;
  final int likeCount;
  final bool likedByMe;
  final DateTime? publishedAt;

  /// Akış kartında özet (diyafram, enstantane, ISO, odak); detayda tam EXIF.
  final Exif? exif;

  /// Sahibin eklediği konumun adı.
  final String? place;

  /// Akış kartında yorum düğmesi ve son yorum önizlemesi.
  final int commentCount;
  final bool commentsOff;
  final ({String username, String body})? lastComment;

  ImageVariant? get thumb => images['thumb'] ?? images['feed'];
  ImageVariant? get feed => images['feed'] ?? images['full'];
  ImageVariant? get full => images['full'] ?? images['feed'];
  double get ratio => (feed ?? thumb)?.ratio ?? 1.5;

  static Map<String, ImageVariant> _images(Object? v) =>
      ((v as Map?) ?? const {}).map(
        (k, e) => MapEntry(
          k as String,
          ImageVariant.fromJson(e as Map<String, dynamic>),
        ),
      );

  factory PhotoCard.fromJson(Map<String, dynamic> j) => PhotoCard(
    id: j['id'] as String,
    user: UserCard.fromJson(j['user'] as Map<String, dynamic>),
    title: _opt(j['title']),
    images: _images(j['images']),
    likeCount: j['like_count'] as int? ?? 0,
    likedByMe: j['liked_by_me'] as bool? ?? false,
    publishedAt: j['published_at'] == null
        ? null
        : DateTime.parse(j['published_at'] as String),
    exif: j['exif'] == null
        ? null
        : Exif.fromJson(j['exif'] as Map<String, dynamic>),
    place: _opt(j['place']),
    commentCount: j['comment_count'] as int? ?? 0,
    commentsOff: j['comments_off'] as bool? ?? false,
    lastComment: j['last_comment'] is Map
        ? (
            username: (j['last_comment'] as Map)['username'] as String,
            body: (j['last_comment'] as Map)['body'] as String,
          )
        : null,
  );
}

/// Sonuçlanmış bir yarışmada ilk üçe giren kare (profildeki "Ödüllü fotoğraflar").
class Award {
  Award.fromJson(Map<String, dynamic> j)
    : rank = j['rank'] as int,
      prize = _opt(j['prize']),
      contestId = j['contest_id'] as String,
      contestTitle = j['contest_title'] as String,
      photo = PhotoCard.fromJson(j['photo'] as Map<String, dynamic>);
  final int rank;
  final String? prize;
  final String contestId;
  final String contestTitle;
  final PhotoCard photo;
}

/// Topluluğa katılma isteği (yönetici görünümü).
class JoinRequest {
  JoinRequest.fromJson(Map<String, dynamic> j)
    : user = UserCard.fromJson(j['user'] as Map<String, dynamic>),
      createdAt = DateTime.parse(j['created_at'] as String);
  final UserCard user;
  final DateTime createdAt;
}

class Exif {
  Exif.fromJson(Map<String, dynamic> j)
    : cameraMake = _opt(j['camera_make']),
      cameraModel = _opt(j['camera_model']),
      lens = _opt(j['lens']),
      focalLength = _d(j['focal_length_mm']),
      focal35 = _opt(j['focal_length_35mm']),
      aperture = _d(j['aperture']),
      shutter = _opt(j['shutter_display']),
      iso = _opt(j['iso']),
      takenAt = j['taken_at'] == null
          ? null
          : DateTime.parse(j['taken_at'] as String);

  final String? cameraMake;
  final String? cameraModel;
  final String? lens;
  final double? focalLength;
  final int? focal35;
  final double? aperture;
  final String? shutter;
  final int? iso;
  final DateTime? takenAt;

  String? get camera {
    if (cameraModel == null) return cameraMake;
    final make = cameraMake;
    if (make != null &&
        !cameraModel!.toLowerCase().startsWith(
          make.toLowerCase().split(' ').first,
        )) {
      return '$make $cameraModel';
    }
    return cameraModel;
  }
}

class GeoPoint {
  GeoPoint(this.latitude, this.longitude, [this.name]);
  final double latitude;
  final double longitude;
  final String? name;

  factory GeoPoint.fromJson(Map<String, dynamic> j) =>
      GeoPoint(_d(j['latitude'])!, _d(j['longitude'])!, _opt(j['name']));
  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'name': name,
  };
}

class PhotoDetail extends PhotoCard {
  PhotoDetail.fromJson(Map<String, dynamic> j)
    : description = _opt(j['description']),
      tags = ((j['tags'] as List?) ?? const []).cast<String>(),
      width = _opt(j['width']),
      height = _opt(j['height']),
      location = j['location'] == null
          ? null
          : GeoPoint.fromJson(j['location'] as Map<String, dynamic>),
      suggestedLocation = j['suggested_location'] == null
          ? null
          : GeoPoint.fromJson(j['suggested_location'] as Map<String, dynamic>),
      status = j['status'] as String,
      rejection = ((j['rejection'] as List?) ?? const [])
          .map((r) => (r as Map)['message'] as String)
          .toList(),
      commentPolicy = j['comment_policy'] as String? ?? 'everyone',
      canComment = j['can_comment'] as bool? ?? false,
      super(
        id: j['id'] as String,
        user: UserCard.fromJson(j['user'] as Map<String, dynamic>),
        title: _opt(j['title']),
        images: PhotoCard._images(j['images']),
        likeCount: j['like_count'] as int? ?? 0,
        likedByMe: j['liked_by_me'] as bool? ?? false,
        publishedAt: j['published_at'] == null
            ? null
            : DateTime.parse(j['published_at'] as String),
        exif: j['exif'] == null
            ? null
            : Exif.fromJson(j['exif'] as Map<String, dynamic>),
        place: _opt(j['place']),
        commentCount: j['comment_count'] as int? ?? 0,
      );

  final String? description;
  final List<String> tags;
  final int? width;
  final int? height;
  final GeoPoint? location;
  final GeoPoint? suggestedLocation;
  final String status; // pending | processing | published | rejected
  final List<String> rejection;
  final String commentPolicy; // everyone | followers | off
  final bool canComment;

  bool get isProcessing => status == 'processing' || status == 'pending';
}

class Page<T> {
  Page(this.items, this.nextCursor);
  final List<T> items;
  final String? nextCursor;
}

class AppNotification {
  AppNotification.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      type = j['type'] as String,
      text = j['text'] as String,
      actor = j['actor'] == null
          ? null
          : UserCard.fromJson(j['actor'] as Map<String, dynamic>),
      photoId = (j['photo'] as Map?)?['id'] as String?,
      photoThumb = (j['photo'] as Map?)?['thumb_url'] as String?,
      data = ((j['data'] as Map?) ?? const {}).map(
        (k, v) => MapEntry('$k', '$v'),
      ),
      read = j['read'] as bool? ?? false,
      createdAt = DateTime.parse(j['created_at'] as String);

  final String id;
  final String type;
  final String text;
  final UserCard? actor;
  final String? photoId;
  final String? photoThumb;
  final Map<String, String> data;
  final bool read;
  final DateTime createdAt;

  /// Dokunulunca açılacak ekran (push verisiyle aynı mantık).
  String get route =>
      routeFor(data, photoId: photoId, username: actor?.username);
}

String routeFor(Map<String, String> data, {String? photoId, String? username}) {
  final link = data['link'];
  if (link != null && link.startsWith('/')) return link; // yönetim duyurusu
  final contest = data['contest_id'];
  final community = data['community_slug'];
  final photo = photoId ?? data['photo_id'];
  final user = username ?? data['username'];
  final conversation = data['conversation_id'];
  if (conversation != null) return '/messages/$conversation';
  if (contest != null) return '/contests/$contest';
  if (community != null) return '/c/$community';
  if (photo != null && data['comment_id'] != null) return '/p/$photo/comments';
  if (photo != null) return '/p/$photo';
  if (user != null) return '/u/$user';
  return '/notifications';
}

// =====================================================================  Faz 2

DateTime _dt(Object? v) => DateTime.parse(v as String).toLocal();

class CommunityCard {
  CommunityCard.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      slug = j['slug'] as String,
      name = j['name'] as String,
      city = _opt(j['city']),
      country = _opt(j['country']),
      logoUrl = _opt(j['logo_url']),
      memberCount = j['member_count'] as int? ?? 0,
      myRole = _opt(j['my_role']),
      joinApproval = j['join_approval'] as bool? ?? false,
      myRequest = j['my_request'] as bool? ?? false,
      pendingRequests = j['pending_requests'] as int?;

  /// Açıksa katılım yönetici onayıyla olur.
  final bool joinApproval;

  /// Görüntüleyenin bekleyen katılma isteği var.
  final bool myRequest;

  /// Yalnızca yöneticilere: bekleyen istek sayısı.
  final int? pendingRequests;

  final String id;
  final String slug;
  final String name;
  final String? city;
  final String? country;
  final String? logoUrl;
  final int memberCount;
  final String? myRole; // owner | admin | member
  bool get isAdmin => myRole == 'owner' || myRole == 'admin';
}

class Community extends CommunityCard {
  Community.fromJson(super.j)
    : description = _opt(j['description']),
      coverUrl = _opt(j['cover_url']),
      owner = UserCard.fromJson(j['owner'] as Map<String, dynamic>),
      admins = ((j['admins'] as List?) ?? const [])
          .map((e) => UserCard.fromJson(e as Map<String, dynamic>))
          .toList(),
      openContests = j['open_contests'] as int? ?? 0,
      super.fromJson();

  final String? description;
  final String? coverUrl;
  final UserCard owner;
  final List<UserCard> admins;
  final int openContests;
}

class Member {
  Member.fromJson(Map<String, dynamic> j)
    : user = UserCard.fromJson(j['user'] as Map<String, dynamic>),
      role = j['role'] as String;
  final UserCard user;
  final String role;
}

class ContestCard {
  ContestCard.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      title = j['title'] as String,
      status = j['status'] as String,
      judgingMode = j['judging_mode'] as String,
      submissionDeadline = _dt(j['submission_deadline']),
      votingEnd = _dt(j['voting_end']),
      resultsAt = _dt(j['results_at']),
      entryCount = j['entry_count'] as int? ?? 0,
      community = CommunityCard.fromJson(
        j['community'] as Map<String, dynamic>,
      );

  final String id;
  final String title;
  final String status; // draft | open | judging | closed | finished
  final String judgingMode; // jury | public
  final DateTime submissionDeadline;
  final DateTime votingEnd;
  final DateTime resultsAt;
  final int entryCount;
  final CommunityCard community;
}

class Entry {
  Entry.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      photoId = j['photo_id'] as String,
      title = _opt(j['title']),
      images = PhotoCard._images(j['images']),
      user = j['user'] == null
          ? null
          : UserCard.fromJson(j['user'] as Map<String, dynamic>),
      disqualified = j['disqualified'] as bool? ?? false,
      rank = _opt(j['rank']),
      score = _d(j['score']),
      prize = _opt(j['prize']),
      myStars = _opt(j['my_stars']),
      myScore = _opt(j['my_score']),
      myNote = _opt(j['my_note']),
      exif = j['exif'] == null
          ? null
          : Exif.fromJson(j['exif'] as Map<String, dynamic>),
      mine = j['mine'] as bool? ?? false;

  final String id;
  final String photoId;
  final String? title;
  final Map<String, ImageVariant> images;
  final UserCard? user;
  final bool disqualified;
  final int? rank;
  final double? score;
  final String? prize;
  final int? myStars;
  final int? myScore;

  /// Jürinin bu kareye düştüğü özel not (yalnızca kendisi görür).
  final String? myNote;

  /// Çekim bilgisi (konum içermez); jüri ve seçmen görünümünde gelir.
  final Exif? exif;
  final bool mine;

  ImageVariant? get feed => images['feed'] ?? images['full'] ?? images['thumb'];
  ImageVariant? get full => images['full'] ?? images['feed'];
  ImageVariant? get thumb => images['thumb'] ?? images['feed'];

  Entry._copy(Entry e, {int? myStars, int? myScore, Object? myNote = _keep})
    : id = e.id,
      photoId = e.photoId,
      title = e.title,
      images = e.images,
      user = e.user,
      disqualified = e.disqualified,
      rank = e.rank,
      score = e.score,
      prize = e.prize,
      myStars = myStars ?? e.myStars,
      myScore = myScore ?? e.myScore,
      myNote = identical(myNote, _keep) ? e.myNote : myNote as String?,
      exif = e.exif,
      mine = e.mine;

  static const _keep = Object();

  /// [myNote] verilmezse mevcut not korunur; `null` notu siler.
  Entry copyWith({int? myStars, int? myScore, Object? myNote = _keep}) =>
      Entry._copy(this, myStars: myStars, myScore: myScore, myNote: myNote);
}

/// `/contests/{id}/results` satırı (yönetici önizlemesi ve sonuçlar).
class ResultRow {
  ResultRow.fromJson(Map<String, dynamic> j)
    : rank = _opt(j['rank']),
      score = _d(j['score']),
      count = j['count'] as int? ?? 0,
      prize = _opt(j['prize']),
      entry = Entry.fromJson(j['entry'] as Map<String, dynamic>),
      scores = (j['scores'] as List?)?.map((v) => (v as num).toInt()).toList();

  final int? rank;
  final double? score;

  /// Jüride puan veren üye sayısı, halk oylamasında oy sayısı.
  final int count;
  final String? prize;
  final Entry entry;

  /// Jüri üyelerinin tek tek puanları (yalnızca yöneticiye gelir).
  final List<int>? scores;
}

class Contest extends ContestCard {
  Contest.fromJson(super.j)
    : description = j['description'] as String,
      rules = _opt(j['rules']),
      anonymous = j['anonymous'] as bool? ?? true,
      minVotes = j['min_votes'] as int? ?? 5,
      prizes = ((j['prizes'] as List?) ?? const [])
          .map(
            (p) =>
                (rank: (p as Map)['rank'] as int, title: p['title'] as String),
          )
          .toList(),
      myRole = _opt(j['my_role']),
      isJudge = j['is_judge'] as bool? ?? false,
      myEntry = j['my_entry'] == null
          ? null
          : Entry.fromJson(j['my_entry'] as Map<String, dynamic>),
      shareUrl = j['share_url'] as String,
      judgeCount = j['judge_count'] as int? ?? 0,
      voteCount = j['vote_count'] as int? ?? 0,
      super.fromJson();

  final String description;
  final String? rules;
  final bool anonymous;
  final int minVotes;
  final List<({int rank, String title})> prizes;
  final String? myRole;
  final bool isJudge;
  final Entry? myEntry;
  final String shareUrl;

  /// Yalnızca sonuçlanan yarışmada dolu: puan veren jüri ve verilen oy sayısı.
  final int judgeCount;
  final int voteCount;
}

/// Haberdeki fotoğraf: sunucuda işlenmiş WebP ve boyutları.
class NewsImage {
  NewsImage.fromJson(Map<String, dynamic> j)
    : key = j['key'] as String,
      url = j['url'] as String,
      width = j['width'] as int,
      height = j['height'] as int;
  final String key;
  final String url;
  final int width;
  final int height;
  double get ratio => height == 0 ? 1.5 : width / height;
  Map<String, dynamic> toJson() => {'key': key, 'url': url, 'width': width, 'height': height};
}

class CommunityPost {
  CommunityPost.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      kind = j['kind'] as String,
      title = _opt(j['title']),
      body = _opt(j['body']),
      createdAt = _dt(j['created_at']),
      author = UserCard.fromJson(j['author'] as Map<String, dynamic>),
      photo = j['photo'] == null
          ? null
          : PhotoCard.fromJson(j['photo'] as Map<String, dynamic>),
      contest = j['contest'] == null
          ? null
          : ContestCard.fromJson(j['contest'] as Map<String, dynamic>),
      images = ((j['images'] as List?) ?? const [])
          .map((e) => NewsImage.fromJson(e as Map<String, dynamic>))
          .toList();

  /// Haber fotoğrafları (kırpılmadan gösterilir).
  final List<NewsImage> images;

  final String id;
  final String kind; // photo | news | contest
  final String? title;
  final String? body;
  final DateTime createdAt;
  final UserCard author;
  final PhotoCard? photo;
  final ContestCard? contest;
}

// =====================================================================  Faz 3

class MapCluster {
  MapCluster.fromJson(Map<String, dynamic> j)
    : lat = _d(j['lat'])!,
      lng = _d(j['lng'])!,
      count = j['count'] as int,
      thumbUrl = _opt(j['thumb_url']);
  final double lat;
  final double lng;
  final int count;
  final String? thumbUrl;
}

class MapPhotographer {
  MapPhotographer.fromJson(Map<String, dynamic> j)
    : user = UserCard.fromJson(j['user'] as Map<String, dynamic>),
      lat = _d(j['lat'])!,
      lng = _d(j['lng'])!,
      city = _opt(j['city']),
      specialties = ((j['specialties'] as List?) ?? const []).cast<String>();
  final UserCard user;
  final double lat;
  final double lng;
  final String? city;
  final List<String> specialties;
}

class MapPhotoPoint {
  MapPhotoPoint.fromJson(Map<String, dynamic> j)
    : photoId = j['photo_id'] as String,
      lat = _d(j['lat'])!,
      lng = _d(j['lng'])!,
      title = _opt(j['title']),
      thumbUrl = _opt(j['thumb_url']),
      user = UserCard.fromJson(j['user'] as Map<String, dynamic>);
  final String photoId;
  final double lat;
  final double lng;
  final String? title;
  final String? thumbUrl;
  final UserCard user;
}

class MessageQuote {
  MessageQuote({required this.id, required this.senderId, this.kind = 'text', this.preview});
  MessageQuote.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      senderId = j['sender_id'] as String,
      kind = j['kind'] as String? ?? 'text',
      preview = _opt(j['preview']);
  final String id;
  final String senderId;
  final String kind; // text | photo | image | gif | location
  final String? preview;
}

class GifItem {
  GifItem.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      kind = j['kind'] as String? ?? 'gif',
      url = j['url'] as String,
      width = j['width'] as int,
      height = j['height'] as int;
  final String id;
  final String kind; // gif | sticker
  final String url;
  final int width;
  final int height;
  double get ratio => height == 0 ? 1 : width / height;
}

class Reaction {
  const Reaction(this.userId, this.emoji);
  Reaction.fromJson(Map<String, dynamic> j)
    : userId = j['user_id'] as String,
      emoji = j['emoji'] as String;
  final String userId;
  final String emoji;
}

class ChatMessage {
  ChatMessage.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      conversationId = j['conversation_id'] as String,
      senderId = j['sender_id'] as String,
      body = _opt(j['body']),
      photo = j['photo'] == null
          ? null
          : PhotoCard.fromJson(j['photo'] as Map<String, dynamic>),
      location = j['location'] == null
          ? null
          : GeoPoint.fromJson(j['location'] as Map<String, dynamic>),
      replyTo = j['reply_to'] == null
          ? null
          : MessageQuote.fromJson(j['reply_to'] as Map<String, dynamic>),
      image = j['image'] == null
          ? null
          : ImageVariant.fromJson(j['image'] as Map<String, dynamic>),
      gif = j['gif'] == null
          ? null
          : GifItem.fromJson(j['gif'] as Map<String, dynamic>),
      reactions = ((j['reactions'] as List?) ?? const [])
          .map((e) => Reaction.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt = _dt(j['created_at']),
      sendState = null,
      payload = null;

  /// Gönder'e basınca hemen sohbete düşen yerel mesaj; sunucu yanıtı gelince gerçeğiyle değişir.
  ChatMessage.pending({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required Map<String, dynamic> this.payload,
    this.body,
    this.gif,
    this.replyTo,
  }) : photo = null,
       location = null,
       image = null,
       reactions = const [],
       createdAt = DateTime.now(),
       sendState = 'sending';

  ChatMessage._copy(ChatMessage m, this.reactions, {String? state, bool keepState = true})
    : sendState = keepState ? m.sendState : state,
      payload = m.payload,
      id = m.id,
      conversationId = m.conversationId,
      senderId = m.senderId,
      body = m.body,
      photo = m.photo,
      location = m.location,
      replyTo = m.replyTo,
      image = m.image,
      gif = m.gif,
      createdAt = m.createdAt;

  ChatMessage withReactions(List<Reaction> r) => ChatMessage._copy(this, r);
  ChatMessage withSendState(String? state) => ChatMessage._copy(this, reactions, state: state, keepState: false);

  /// null: gönderildi · 'sending': gidiyor · 'failed': gidemedi (yeniden denenebilir)
  final String? sendState;

  /// Yerel mesajın yeniden denemede kullanılacak gövdesi.
  final Map<String, dynamic>? payload;
  bool get isLocal => sendState != null;

  final String id;
  final String conversationId;
  final String senderId;
  final String? body;
  final PhotoCard? photo;
  final GeoPoint? location;
  final MessageQuote? replyTo;
  final ImageVariant? image;
  final GifItem? gif;
  final List<Reaction> reactions;
  final DateTime createdAt;

  /// Moderasyonla içeriği kaldırılmış mesaj.
  bool get removed =>
      body == null && photo == null && location == null && image == null && gif == null;
}

class PhotoComment {
  PhotoComment.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      photoId = j['photo_id'] as String,
      user = UserCard.fromJson(j['user'] as Map<String, dynamic>),
      body = j['body'] as String,
      createdAt = _dt(j['created_at']),
      parentId = _opt(j['parent_id']),
      quoteUser = j['quote'] == null
          ? null
          : UserCard.fromJson((j['quote'] as Map)['user'] as Map<String, dynamic>),
      quoteBody = j['quote'] == null ? null : _opt((j['quote'] as Map)['body']),
      hasQuote = j['quote'] != null,
      replyCount = j['reply_count'] as int? ?? 0,
      byPhotoOwner = j['by_photo_owner'] as bool? ?? false,
      canDelete = j['can_delete'] as bool? ?? false;

  PhotoComment._copy(PhotoComment c, this.replyCount)
    : id = c.id,
      photoId = c.photoId,
      user = c.user,
      body = c.body,
      createdAt = c.createdAt,
      parentId = c.parentId,
      hasQuote = c.hasQuote,
      quoteUser = c.quoteUser,
      quoteBody = c.quoteBody,
      byPhotoOwner = c.byPhotoOwner,
      canDelete = c.canDelete;

  PhotoComment withReplyCount(int n) => PhotoComment._copy(this, n < 0 ? 0 : n);

  final String id;
  final String photoId;
  final UserCard user;
  final String body;
  final DateTime createdAt;
  final String? parentId;
  final bool hasQuote;
  final UserCard? quoteUser;
  final String? quoteBody; // null + hasQuote: alıntılanan yorum silindi
  final int replyCount;
  final bool byPhotoOwner;
  final bool canDelete;
}

class Conversation {
  Conversation.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      other = UserCard.fromJson(j['other'] as Map<String, dynamic>),
      status = j['status'] as String,
      isRequestToMe = j['is_request_to_me'] as bool? ?? false,
      lastMessage = j['last_message'] == null
          ? null
          : ChatMessage.fromJson(j['last_message'] as Map<String, dynamic>),
      unread = j['unread'] as int? ?? 0,
      lastMessageAt = _dt(j['last_message_at']),
      otherLastReadAt = j['other_last_read_at'] == null
          ? null
          : _dt(j['other_last_read_at']);
  final String id;
  final UserCard other;
  final String status; // request | accepted | declined
  final bool isRequestToMe;
  final ChatMessage? lastMessage;
  final int unread;
  final DateTime lastMessageAt;
  final DateTime? otherLastReadAt;
}
