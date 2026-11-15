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
  );
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
      );

  final String? description;
  final List<String> tags;
  final int? width;
  final int? height;
  final GeoPoint? location;
  final GeoPoint? suggestedLocation;
  final String status; // pending | processing | published | rejected
  final List<String> rejection;

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
  final contest = data['contest_id'];
  final community = data['community_slug'];
  final photo = photoId ?? data['photo_id'];
  final user = username ?? data['username'];
  final conversation = data['conversation_id'];
  if (conversation != null) return '/messages/$conversation';
  if (contest != null) return '/contests/$contest';
  if (community != null) return '/c/$community';
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
      myRole = _opt(j['my_role']);

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
  final bool mine;

  ImageVariant? get feed => images['feed'] ?? images['full'] ?? images['thumb'];
  ImageVariant? get full => images['full'] ?? images['feed'];
  ImageVariant? get thumb => images['thumb'] ?? images['feed'];

  Entry._copy(Entry e, {int? myStars, int? myScore})
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
      mine = e.mine;

  Entry copyWith({int? myStars, int? myScore}) =>
      Entry._copy(this, myStars: myStars, myScore: myScore);
}

class Contest extends ContestCard {
  Contest.fromJson(super.j)
    : description = j['description'] as String,
      rules = _opt(j['rules']),
      anonymous = j['anonymous'] as bool? ?? true,
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
      super.fromJson();

  final String description;
  final String? rules;
  final bool anonymous;
  final List<({int rank, String title})> prizes;
  final String? myRole;
  final bool isJudge;
  final Entry? myEntry;
  final String shareUrl;
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
          : ContestCard.fromJson(j['contest'] as Map<String, dynamic>);

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
      createdAt = _dt(j['created_at']);
  final String id;
  final String conversationId;
  final String senderId;
  final String? body;
  final PhotoCard? photo;
  final GeoPoint? location;
  final DateTime createdAt;
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
