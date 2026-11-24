export type EquipmentType = "body" | "lens" | "tripod" | "filter" | "flash" | "drone" | "other";

export type Equipment = { id: string; type: EquipmentType; brand: string; model: string };

export type UserCard = {
  id: string;
  username: string;
  display_name: string;
  avatar_url: string | null;
  is_public: boolean;
  is_pro: boolean;
};

export type Me = UserCard & {
  is_admin?: boolean;
  email: string;
  email_verified: boolean;
  bio: string | null;
  cover_url: string | null;
  website: string | null;
  specialties: string[];
  locale: "tr" | "en";
  city: string | null;
  country: string | null;
  latitude: number | null;
  longitude: number | null;
  created_at: string;
  equipment: Equipment[];
  /** Kayıt sonrası tanıtım bitti ya da kapatıldı; yalnızca yeni hesaplarda false */
  onboarding_done: boolean;
  /** En az bir yayınlanmış fotoğrafı var (tanıtımdaki son adım) */
  has_photos: boolean;
  /** Yeni yüklemelerde kullanılan varsayılan lisans ve indirme ayarı */
  default_license?: License;
  default_downloads_disabled?: boolean;
};

export type Profile = UserCard & {
  bio: string | null;
  cover_url: string | null;
  website: string | null;
  specialties: string[];
  city: string | null;
  country: string | null;
  equipment: Equipment[];
  followers_count: number;
  following_count: number;
  photos_count: number;
  is_following: boolean;
  is_me: boolean;
  can_view_photos: boolean;
  /** Kazanılan haftalık tema sayısı (profil rozeti) */
  theme_wins?: number;
};

export type ImageVariant = { url: string; width: number; height: number };
export type Variants = Partial<Record<"thumb" | "feed" | "full", ImageVariant>>;

export type PhotoCard = {
  id: string;
  user: UserCard;
  title: string | null;
  images: Variants;
  like_count: number;
  liked_by_me: boolean;
  published_at: string | null;
  /** Kart çipleri için çekim bilgisi özeti. */
  exif?: ExifSummary | null;
  /** Sahibin eklediği konumun adı (koordinat yok). */
  place?: string | null;
  /** Akış kartında yorum düğmesi ve son yorum önizlemesi */
  comment_count: number;
  comments_off: boolean;
  last_comment: { username: string; body: string } | null;
  /** Eleştiri modu: fotoğrafçı puanlı geri bildirim istiyor */
  critique_requested?: boolean;
  critique_question?: string | null;
  critique_count?: number;
};

export type ExifSummary = Pick<Exif, "aperture" | "shutter_display" | "iso" | "focal_length_mm">;

export type Exif = {
  camera_make: string | null;
  camera_model: string | null;
  lens: string | null;
  focal_length_mm: number | null;
  focal_length_35mm: number | null;
  aperture: number | null;
  shutter_display: string | null;
  iso: number | null;
  taken_at: string | null;
  white_balance: string | null;
  flash_fired: boolean | null;
};

export type Location = { latitude: number; longitude: number; name?: string | null };

export type PhotoStatus = "pending" | "processing" | "published" | "rejected";

export type PhotoDetail = PhotoCard & {
  description: string | null;
  tags: string[];
  width: number | null;
  height: number | null;
  exif: Exif | null;
  location: Location | null;
  status: PhotoStatus;
  rejection: { code: string; message: string }[] | null;
  suggested_location: Location | null;
  comment_policy: CommentPolicy;
  /** Bakan kişi şu an yorum yazabilir mi */
  can_comment: boolean;
  license?: License;
  downloads_disabled?: boolean;
};

export type License = "all_rights" | "cc_by" | "cc_by_nc" | "contact";

export type CommentPolicy = "everyone" | "followers" | "off";

export type PhotoComment = {
  id: string;
  photo_id: string;
  user: UserCard;
  body: string;
  created_at: string;
  parent_id: string | null;
  /** Alıntılanan yorum; silinmişse body null */
  quote: { id: string; user: UserCard; body: string | null } | null;
  reply_count: number;
  by_photo_owner: boolean;
  can_delete: boolean;
};

export type CommentPage = { items: PhotoComment[]; next_cursor: string | null; total: number };

export type Page<T> = { items: T[]; next_cursor: string | null };

export type AppNotification = {
  id: string;
  type: string;
  text: string;
  actor: UserCard | null;
  photo: { id: string; thumb_url: string | null } | null;
  data: Record<string, string>;
  read: boolean;
  created_at: string;
};

export type NotificationPage = Page<AppNotification> & { unread_count: number };

// ---------- Faz 2 ----------
export type CommunityRole = "owner" | "admin" | "member";

export type CommunityCard = {
  id: string;
  slug: string;
  name: string;
  city: string | null;
  country: string | null;
  logo_url: string | null;
  member_count: number;
  my_role: CommunityRole | null;
  join_approval: boolean;
  /** Görüntüleyenin bekleyen katılma isteği var */
  my_request: boolean;
  /** Yalnızca yöneticilere: bekleyen istek sayısı */
  pending_requests: number | null;
};

export type Community = CommunityCard & {
  description: string | null;
  cover_url: string | null;
  owner: UserCard;
  admins: UserCard[];
  open_contests: number;
  created_at: string;
};

export type Member = { user: UserCard; role: CommunityRole; joined_at: string };

export type ContestStatus = "draft" | "open" | "judging" | "closed" | "finished";

export type ContestCard = {
  id: string;
  title: string;
  status: ContestStatus;
  judging_mode: "jury" | "public";
  submission_deadline: string;
  voting_end: string;
  results_at: string;
  entry_count: number;
  community: CommunityCard;
};

export type Entry = {
  id: string;
  photo_id: string;
  title: string | null;
  images: Variants;
  user: UserCard | null;
  disqualified: boolean;
  rank: number | null;
  score: number | null;
  prize: string | null;
  my_stars: number | null;
  my_score: number | null;
  /** Jüri üyesinin bu kareye düştüğü özel not (yalnızca kendisi görür) */
  my_note?: string | null;
  number?: number | null;
  disqualify_reason?: string | null;
  mine: boolean;
  exif?: Exif | null;
};

export type Contest = ContestCard & {
  description: string;
  rules: string | null;
  anonymous: boolean;
  min_votes: number;
  prizes: { rank: number; title: string }[];
  published_at: string | null;
  my_role: "admin" | "judge" | null;
  is_judge: boolean;
  my_entry: Entry | null;
  share_url: string;
  /** Yalnızca sonuçlar açıklandıktan sonra dolar */
  judge_count?: number;
  vote_count?: number;
};

export type Judge = { id: string; user: UserCard | null; email: string | null; weight: number; pending: boolean; scored: number };

export type ResultRow = {
  rank: number | null;
  score: number | null;
  count: number;
  prize: string | null;
  entry: Entry;
  /** Tek tek jüri puanları (yalnızca yönetici, jüri modu) */
  scores?: number[] | null;
};

export type ContestSummary = { entries: number; disqualified: number; voters: number; votes: number; suspicious_ips: number; judges: Judge[] };

export type CommunityPost = {
  id: string;
  kind: "photo" | "news" | "contest";
  title: string | null;
  body: string | null;
  created_at: string;
  author: UserCard;
  photo: PhotoCard | null;
  contest: ContestCard | null;
  /** Haber fotoğrafları; kırpılmadan gösterilir */
  images: NewsImage[];
};

export type NewsImage = { key: string; url: string; width: number; height: number };

// ---------- Faz 3 ----------
export type MapCluster = { lat: number; lng: number; count: number; thumb_url: string | null };
export type MapPhotographer = { user: UserCard; lat: number; lng: number; city: string | null; country: string | null; specialties: string[] };
export type MapPhotoPoint = { photo_id: string; lat: number; lng: number; title: string | null; thumb_url: string | null; user: UserCard };
export type PhotographerMapData = { clusters: MapCluster[]; photographers: MapPhotographer[]; total: number };
export type PhotoMapData = { clusters: MapCluster[]; photos: MapPhotoPoint[]; total: number };

export type ChatMessage = {
  id: string;
  conversation_id: string;
  sender_id: string;
  body: string | null;
  photo: PhotoCard | null;
  location: Location | null;
  created_at: string;
  reply_to: MessageQuote | null;
  /** Galeriden gönderilen görsel; yalnızca bu sohbette görünür */
  image: ImageVariant | null;
  gif: Gif | null;
  reactions: Reaction[];
};

export type MessageQuote = { id: string; sender_id: string; kind: "text" | "photo" | "image" | "gif" | "location"; preview: string | null };
export type Gif = { id: string; kind: "gif" | "sticker"; url: string; width: number; height: number };
export type Reaction = { user_id: string; emoji: string };

export type Conversation = {
  id: string;
  other: UserCard;
  status: "request" | "accepted" | "declined";
  is_request_to_me: boolean;
  last_message: ChatMessage | null;
  unread: number;
  last_message_at: string;
  other_last_read_at: string | null;
};
export type MessagePageData = { items: ChatMessage[]; next_cursor: string | null };

// ---------- Faz 4 ----------
export type BillingStatus = {
  is_pro: boolean;
  store: "app_store" | "play_store" | "stripe" | null;
  status: "active" | "grace" | "cancelled" | null;
  period_end: string | null;
  will_renew: boolean;
  can_manage_on_web: boolean;
  prices: { monthly: string; yearly: string };
};

// ---------- Revizyon 7
export type ThemeStatus = "scheduled" | "active" | "ended" | "finished";

export type ThemeEntry = { id: string; theme_id: string; created_at: string; rank: number | null; photo: PhotoCard };

export type Theme = {
  id: string;
  number: number;
  /** İsteğin diline göre */
  title: string;
  description: string | null;
  starts_at: string;
  ends_at: string;
  status: ThemeStatus;
  entry_count: number;
  my_entry: ThemeEntry | null;
  winner: ThemeEntry | null;
  finalized_at: string | null;
};

export type ThemeAdmin = {
  id: string;
  number: number;
  title_tr: string;
  title_en: string;
  description_tr: string | null;
  description_en: string | null;
  starts_at: string;
  ends_at: string;
  status: ThemeStatus;
  entry_count: number;
  winner_entry_id: string | null;
  finalized_at: string | null;
  created_at: string;
};

export type ThemeWin = { theme_id: string; number: number; title: string; won_at: string | null; like_count: number; photo: PhotoCard };

export const CRITERIA = ["composition", "light", "focus", "editing"] as const;
export type Criterion = (typeof CRITERIA)[number];

export type Critique = Record<Criterion, number> & {
  id: string;
  photo_id: string;
  user: UserCard;
  author_specialties: string[];
  average: number;
  good: string | null;
  improve: string | null;
  helpful_count: number;
  helpful_by_me: boolean;
  mine: boolean;
  can_delete: boolean;
  created_at: string;
  updated_at: string;
};

export type CritiqueList = {
  count: number;
  averages: Record<Criterion | "overall", number | null>;
  items: Critique[];
  my_critique: Critique | null;
  can_critique: boolean;
  critique_requested: boolean;
  critique_question: string | null;
};

export type CollectionCard = {
  id: string;
  title: string;
  description: string | null;
  photo_count: number;
  /** İlk en fazla 3 karenin görsel türevleri */
  covers: Variants[];
  position: number;
  updated_at: string;
  contains_photo?: boolean | null;
};

export type Collection = CollectionCard & { owner: UserCard; is_mine: boolean; photos: PhotoCard[]; created_at: string };

export type EventStatus = "upcoming" | "ongoing" | "past" | "cancelled";

export type EventCard = {
  id: string;
  community: CommunityCard;
  title: string;
  starts_at: string;
  ends_at: string | null;
  location_name: string;
  latitude: number | null;
  longitude: number | null;
  capacity: number | null;
  attendee_count: number;
  attending: boolean;
  status: EventStatus;
  cancelled_at: string | null;
};

export type CommunityEvent = EventCard & {
  description: string | null;
  bring: string | null;
  created_by: UserCard | null;
  created_at: string;
  attendees_preview: UserCard[];
  my_role: CommunityRole | null;
  can_manage: boolean;
  /** Toplulukların grup sohbeti yok; hep null */
  conversation_id: string | null;
};

export type EventList = { upcoming: EventCard[]; past: EventCard[] };

export const PLAN_KINDS = ["milkyway", "golden", "blue", "moonrise", "meteor", "other"] as const;
export type PlanKind = (typeof PLAN_KINDS)[number];

export type Plan = {
  id: string;
  kind: PlanKind;
  title: string | null;
  latitude: number;
  longitude: number;
  place_name: string | null;
  target_at: string;
  remind: boolean;
  weather_alert: boolean;
  notes: string | null;
  created_at: string;
  last_cloud_cover: number | null;
  weather_checked_at: string | null;
  status: "upcoming" | "past";
  /** Takip edenlerle paylaşıldı mı (eski API yanıtlarında olmayabilir) */
  shared?: boolean;
  join_count?: number;
  /** En fazla 8 katılımcı */
  joiners?: UserCard[];
};

/** Paylaşılan plan: sahibi ve katılımcılarıyla (GET /plans/shared, /plans/{id}). */
export type SharedPlan = {
  id: string;
  kind: PlanKind;
  title: string | null;
  latitude: number;
  longitude: number;
  place_name: string | null;
  target_at: string;
  notes: string | null;
  owner: UserCard;
  join_count: number;
  joined: boolean;
  joiners: UserCard[];
  status: "upcoming" | "past";
};

export type GearStats = {
  camera: string | null;
  lens: string | null;
  photo_count: number;
  photographer_count: number;
  top_photographers: UserCard[];
  /** En sık kullanılan etiketler (eski API yanıtlarında olmayabilir) */
  top_tags?: { tag: string; count: number }[];
  common_settings: {
    median_shutter_seconds: number | null;
    median_shutter_display: string | null;
    median_aperture: number | null;
    median_iso: number | null;
    median_focal_length_mm: number | null;
    sample_size: number;
  };
};

export type GearName = { kind: "camera" | "lens"; name: string; photo_count: number };
