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
};

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
  mine: boolean;
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
};

export type Judge = { id: string; user: UserCard | null; email: string | null; weight: number; pending: boolean; scored: number };

export type ResultRow = { rank: number | null; score: number | null; count: number; prize: string | null; entry: Entry };

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
};

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
