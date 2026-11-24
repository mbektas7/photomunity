import re
import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

from app.models import EquipmentType, PhotoStatus

USERNAME_RE = re.compile(r"^[a-z0-9_.]{3,30}$")
Locale = Literal["tr", "en"]
License = Literal["all_rights", "cc_by", "cc_by_nc", "contact"]


class ORM(BaseModel):
    model_config = ConfigDict(from_attributes=True)


def _username(v: str) -> str:
    v = v.strip().lower()
    if not USERNAME_RE.match(v):
        raise ValueError("Kullanıcı adı 3-30 karakter; harf, rakam, _ ve . içerebilir.")
    return v


# ---------- Auth ----------
class RegisterIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    username: str
    display_name: str = Field(min_length=1, max_length=80)
    locale: Locale = "tr"

    _u = field_validator("username")(_username)


class LoginIn(BaseModel):
    email: EmailStr
    password: str


class OAuthIn(BaseModel):
    id_token: str
    # Apple adı yalnızca ilk girişte istemciye verir; istemci buraya iletir.
    display_name: str | None = Field(default=None, max_length=80)
    username: str | None = None
    locale: Locale = "tr"


class RefreshIn(BaseModel):
    refresh_token: str


class TokenIn(BaseModel):
    token: str


class EmailIn(BaseModel):
    email: EmailStr


class ResetPasswordIn(BaseModel):
    token: str
    new_password: str = Field(min_length=8, max_length=128)


class ChangePasswordIn(BaseModel):
    current_password: str | None = None  # yalnızca sosyal girişle açılan hesaplarda boş olabilir
    new_password: str = Field(min_length=8, max_length=128)


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


# ---------- Users ----------
class EquipmentIn(BaseModel):
    type: EquipmentType
    brand: str = Field(min_length=1, max_length=80)
    model: str = Field(min_length=1, max_length=120)


class EquipmentOut(ORM, EquipmentIn):
    id: uuid.UUID


class UserCard(ORM):
    id: uuid.UUID
    username: str
    display_name: str
    avatar_url: str | None
    is_public: bool
    is_pro: bool


class MeOut(ORM):
    id: uuid.UUID
    email: str
    email_verified: bool
    username: str
    display_name: str
    bio: str | None
    avatar_url: str | None
    cover_url: str | None
    website: str | None
    specialties: list[str]
    locale: str
    is_public: bool
    city: str | None
    country: str | None
    latitude: float | None
    longitude: float | None
    is_pro: bool
    is_admin: bool = False
    onboarding_done: bool = True
    default_license: str = "all_rights"
    default_downloads_disabled: bool = False
    created_at: datetime


class MeDetail(MeOut):
    equipment: list[EquipmentOut] = []
    has_photos: bool = False  # tanıtımdaki "ilk fotoğrafını paylaş" adımı için


class AuthResponse(BaseModel):
    user: MeOut
    tokens: TokenPair
    is_new_user: bool = False


class MeUpdate(BaseModel):
    username: str | None = None
    display_name: str | None = Field(default=None, min_length=1, max_length=80)
    bio: str | None = Field(default=None, max_length=500)
    website: str | None = Field(default=None, max_length=300)
    specialties: list[str] | None = Field(default=None, max_length=10)
    locale: Locale | None = None
    is_public: bool | None = None
    city: str | None = Field(default=None, max_length=120)
    country: str | None = Field(default=None, min_length=2, max_length=2)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    onboarding_done: bool | None = None  # true: tanıtım bitti ya da kapatıldı
    default_license: License | None = None
    default_downloads_disabled: bool | None = None

    @field_validator("username")
    @classmethod
    def _u(cls, v):
        return _username(v) if v is not None else v


class ProfileOut(BaseModel):
    id: uuid.UUID
    username: str
    display_name: str
    bio: str | None
    avatar_url: str | None
    cover_url: str | None
    website: str | None
    specialties: list[str]
    is_public: bool
    is_pro: bool
    city: str | None
    country: str | None
    equipment: list[EquipmentOut]
    followers_count: int
    following_count: int
    photos_count: int
    is_following: bool
    is_me: bool
    can_view_photos: bool
    theme_wins: int = 0  # kazanılan haftalık tema sayısı (profil rozeti)


class UserPage(BaseModel):
    items: list[UserCard]
    next_cursor: str | None


# ---------- Photos ----------
ALLOWED_CONTENT_TYPES = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/heic": ".heic",
    "image/heif": ".heif",
}


class UploadUrlIn(BaseModel):
    content_type: str
    size_bytes: int = Field(gt=0)


class UploadUrlOut(BaseModel):
    photo_id: uuid.UUID
    upload_url: str
    fields: dict[str, str]  # multipart POST alanları (S3 presigned POST)
    expires_in: int


class LocationIn(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    name: str | None = Field(default=None, max_length=200)


CommentPolicy = Literal["everyone", "followers", "off"]


class PhotoMetaIn(BaseModel):
    title: str | None = Field(default=None, max_length=150)
    description: str | None = Field(default=None, max_length=2000)
    tags: list[str] = Field(default_factory=list, max_length=15)
    location: LocationIn | None = None
    comment_policy: CommentPolicy | None = None
    critique_requested: bool | None = None
    critique_question: str | None = Field(default=None, max_length=300)
    license: License | None = None  # gönderilmezse kullanıcının default_license değeri
    downloads_disabled: bool | None = None  # gönderilmezse default_downloads_disabled


class PhotoUpdate(BaseModel):
    title: str | None = Field(default=None, max_length=150)
    description: str | None = Field(default=None, max_length=2000)
    tags: list[str] | None = Field(default=None, max_length=15)
    location: LocationIn | None = None
    clear_location: bool = False
    comment_policy: CommentPolicy | None = None
    critique_requested: bool | None = None
    critique_question: str | None = Field(default=None, max_length=300)  # "" gönderilirse soru silinir
    license: License | None = None
    downloads_disabled: bool | None = None


class ImageVariant(BaseModel):
    url: str
    width: int
    height: int


class ExifOut(ORM):
    camera_make: str | None
    camera_model: str | None
    lens: str | None
    focal_length_mm: float | None
    focal_length_35mm: int | None
    aperture: float | None
    shutter_display: str | None
    iso: int | None
    taken_at: datetime | None
    white_balance: str | None
    flash_fired: bool | None


class ExifSummary(ORM):
    """Kart altındaki çekim bilgisi çipleri için ExifOut'un alt kümesi."""
    aperture: float | None
    shutter_display: str | None
    iso: int | None
    focal_length_mm: float | None


class CommentPreview(BaseModel):
    username: str
    body: str


class PhotoCard(BaseModel):
    id: uuid.UUID
    user: UserCard
    title: str | None
    images: dict[str, ImageVariant]
    like_count: int
    liked_by_me: bool
    published_at: datetime | None
    # Akış kartı: çekim bilgisi çipleri ve yer adı (yalnızca sahibin eklediği konum adı; koordinat yok)
    exif: ExifSummary | None = None
    place: str | None = None
    # Akış kartında yorum düğmesi ve son yorum önizlemesi
    comment_count: int = 0
    comments_off: bool = False
    last_comment: CommentPreview | None = None
    # Eleştiri modu
    critique_requested: bool = False
    critique_question: str | None = None
    critique_count: int = 0


class PhotoDetail(PhotoCard):
    description: str | None
    tags: list[str]
    width: int | None
    height: int | None
    exif: ExifOut | None
    location: LocationIn | None
    status: PhotoStatus
    rejection: list[dict] | None = None        # yalnızca sahibine
    suggested_location: LocationIn | None = None  # EXIF GPS, yalnızca sahibine
    comment_policy: str = "everyone"
    comment_count: int = 0
    can_comment: bool = False  # bakan kişi şu an yorum yazabilir mi
    license: str = "all_rights"
    downloads_disabled: bool = False


class CommentIn(BaseModel):
    body: str = Field(min_length=1, max_length=2000)
    parent_id: uuid.UUID | None = None  # cevap verilen yorum (cevaba cevap, aynı üst yoruma bağlanır)
    quote_id: uuid.UUID | None = None   # alıntılanan yorum


class CommentQuote(BaseModel):
    id: uuid.UUID
    user: UserCard
    body: str | None  # silinmişse None


class CommentOut(BaseModel):
    id: uuid.UUID
    photo_id: uuid.UUID
    user: UserCard
    body: str
    created_at: datetime
    parent_id: uuid.UUID | None
    quote: CommentQuote | None = None
    reply_count: int = 0
    by_photo_owner: bool = False
    can_delete: bool = False


class CommentPage(BaseModel):
    items: list[CommentOut]
    next_cursor: str | None
    total: int = 0


class PhotoPage(BaseModel):
    items: list[PhotoCard]
    next_cursor: str | None


class AwardOut(BaseModel):
    """Sonuçlanmış bir yarışmada ilk üçe giren kare."""
    rank: int
    prize: str | None
    contest_id: uuid.UUID
    contest_title: str
    awarded_at: datetime | None
    photo: PhotoCard


# ---------- Bildirimler ----------
class NotificationPhoto(BaseModel):
    id: uuid.UUID
    thumb_url: str | None


class NotificationOut(BaseModel):
    id: uuid.UUID
    type: str
    text: str
    actor: UserCard | None
    photo: NotificationPhoto | None
    data: dict
    read: bool
    created_at: datetime


class NotificationPage(BaseModel):
    items: list[NotificationOut]
    next_cursor: str | None
    unread_count: int


class MarkReadIn(BaseModel):
    ids: list[uuid.UUID] | None = None  # boşsa tümü


class DeviceIn(BaseModel):
    token: str = Field(min_length=10, max_length=500)
    platform: Literal["ios", "android", "web"]


class NotificationSettings(BaseModel):
    push: dict[str, bool]


# ---------- Profil görselleri ----------
class ProfileImageUploadIn(BaseModel):
    kind: Literal["avatar", "cover", "message"]  # message: sohbete galeriden/kameradan gönderilecek görsel
    content_type: str
    size_bytes: int = Field(gt=0)


class ProfileImageCompleteIn(BaseModel):
    kind: Literal["avatar", "cover"]
    key: str


# ---------- Şikayet ----------
class ReportIn(BaseModel):
    target_type: Literal["photo", "user", "comment", "message"]
    target_id: uuid.UUID
    reason: Literal["spam", "nudity", "violence", "harassment", "copyright", "other"]
    note: str | None = Field(default=None, max_length=1000)


class ReportOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    reporter_id: uuid.UUID
    target_type: str
    target_id: uuid.UUID
    reason: str
    note: str | None
    status: str
    resolution: str | None
    created_at: datetime


class ResolveReportIn(BaseModel):
    action: Literal["dismiss", "hide_photo", "disable_user"]


# =====================================================================  Faz 2
class CommunityIn(BaseModel):
    name: str = Field(min_length=3, max_length=100)
    slug: str | None = Field(default=None, pattern=r"^[a-z0-9][a-z0-9-]{2,59}$")
    description: str | None = Field(default=None, max_length=3000)
    city: str | None = Field(default=None, max_length=120)
    country: str | None = Field(default=None, min_length=2, max_length=2)


class CommunityUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=3, max_length=100)
    join_approval: bool | None = None
    description: str | None = Field(default=None, max_length=3000)
    city: str | None = Field(default=None, max_length=120)
    country: str | None = Field(default=None, min_length=2, max_length=2)


class CommunityCard(BaseModel):
    id: uuid.UUID
    slug: str
    name: str
    city: str | None
    country: str | None
    logo_url: str | None
    member_count: int
    my_role: str | None
    join_approval: bool = False
    my_request: bool = False           # görüntüleyenin bekleyen katılma isteği var
    pending_requests: int | None = None  # yalnızca yöneticilere: bekleyen istek sayısı


class JoinRequestOut(BaseModel):
    user: UserCard
    created_at: datetime


class CommunityOut(CommunityCard):
    description: str | None
    cover_url: str | None
    owner: UserCard
    admins: list[UserCard]
    open_contests: int
    created_at: datetime


class MemberOut(BaseModel):
    user: UserCard
    role: str
    joined_at: datetime


class MemberPage(BaseModel):
    items: list[MemberOut]
    next_cursor: str | None


class AdminIn(BaseModel):
    username: str


class InviteIn(BaseModel):
    email: EmailStr


class CommunityImageCompleteIn(BaseModel):
    kind: Literal["logo", "cover"]
    key: str


class CommunityImageUploadIn(BaseModel):
    kind: Literal["logo", "cover"]
    content_type: str
    size_bytes: int = Field(gt=0)


class NewsImage(BaseModel):
    key: str = Field(max_length=300)
    url: str = Field(max_length=500)
    width: int = Field(gt=0)
    height: int = Field(gt=0)


class NewsImageUploadIn(BaseModel):
    content_type: str
    size_bytes: int = Field(gt=0)


class NewsImageCompleteIn(BaseModel):
    key: str


class PostIn(BaseModel):
    kind: Literal["photo", "news"]
    title: str | None = Field(default=None, max_length=200)
    body: str | None = Field(default=None, max_length=5000)
    photo_id: uuid.UUID | None = None
    images: list[NewsImage] = Field(default_factory=list, max_length=10)


class PrizeIn(BaseModel):
    rank: int = Field(ge=1, le=10)
    title: str = Field(min_length=1, max_length=200)


class ContestIn(BaseModel):
    title: str = Field(min_length=3, max_length=150)
    description: str = Field(min_length=1, max_length=5000)
    rules: str | None = Field(default=None, max_length=5000)
    submission_deadline: datetime
    voting_end: datetime
    results_at: datetime
    judging_mode: Literal["jury", "public"]
    anonymous: bool = True
    min_votes: int = Field(default=5, ge=0, le=100)
    prizes: list[PrizeIn] = Field(default_factory=list, max_length=10)


class ContestUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=3, max_length=150)
    description: str | None = Field(default=None, max_length=5000)
    rules: str | None = Field(default=None, max_length=5000)
    submission_deadline: datetime | None = None
    voting_end: datetime | None = None
    results_at: datetime | None = None
    judging_mode: Literal["jury", "public"] | None = None
    anonymous: bool | None = None
    min_votes: int | None = Field(default=None, ge=0, le=100)
    prizes: list[PrizeIn] | None = Field(default=None, max_length=10)


class PrizeOut(BaseModel):
    rank: int
    title: str


class ContestCard(BaseModel):
    id: uuid.UUID
    title: str
    status: str
    judging_mode: str
    submission_deadline: datetime
    voting_end: datetime
    results_at: datetime
    entry_count: int
    community: CommunityCard


class EntryOut(BaseModel):
    id: uuid.UUID
    photo_id: uuid.UUID
    title: str | None
    images: dict[str, ImageVariant]
    user: UserCard | None  # anonim değerlendirmede gizli
    disqualified: bool = False
    disqualify_reason: str | None = None  # yalnızca yönetici listesinde
    number: int | None = None  # kalıcı başvuru numarası (#N), katılım sırası
    rank: int | None = None
    score: float | None = None
    prize: str | None = None
    my_stars: int | None = None
    my_score: int | None = None
    my_note: str | None = None
    exif: ExifOut | None = None  # jüri ve seçmen için çekim bilgisi (konum içermez)
    mine: bool = False  # anonim değerlendirmede de kişi kendi karesini tanır (kendine oy veremez)


class ContestOut(ContestCard):
    description: str
    rules: str | None
    anonymous: bool
    min_votes: int
    prizes: list[PrizeOut]
    published_at: datetime | None
    my_role: str | None  # admin | judge | None (yönetici olan jüri üyesi için "admin")
    is_judge: bool  # rolden bağımsız: yönetici aynı zamanda jüri olabilir
    my_entry: EntryOut | None
    share_url: str
    # Sonuç duyurusu için (yalnızca sonuçlanınca dolar)
    judge_count: int = 0
    vote_count: int = 0


class EntryIn(BaseModel):
    photo_id: uuid.UUID


class DisqualifyIn(BaseModel):
    reason: str = Field(min_length=1, max_length=300)


class JudgeIn(BaseModel):
    username: str | None = None
    email: EmailStr | None = None
    weight: float = Field(default=1.0, gt=0, le=10)


class JudgeUpdate(BaseModel):
    weight: float = Field(gt=0, le=10)


class JudgeOut(BaseModel):
    id: uuid.UUID
    user: UserCard | None
    email: str | None
    weight: float
    pending: bool
    scored: int


class ScoreIn(BaseModel):
    score: int = Field(ge=1, le=10)
    note: str | None = Field(default=None, max_length=1000)


class StarsIn(BaseModel):
    entry_id: uuid.UUID
    stars: int = Field(ge=1, le=5)


class VoteCodeIn(BaseModel):
    email: EmailStr
    turnstile_token: str | None = None


class VoteVerifyIn(BaseModel):
    email: EmailStr
    code: str = Field(min_length=6, max_length=6)


class ResultRow(BaseModel):
    rank: int | None
    score: float | None
    count: int  # jüride puan veren üye sayısı, halkta oy sayısı
    prize: str | None
    entry: EntryOut
    scores: list[int] | None = None  # jüri üyelerinin tek tek puanları (yalnızca yöneticiye)


class ContestSummary(BaseModel):
    entries: int
    disqualified: int
    voters: int
    votes: int
    suspicious_ips: int
    judges: list[JudgeOut]


# =====================================================================  Faz 3
class GifIn(BaseModel):
    id: str = Field(min_length=1, max_length=64, pattern=r"^[A-Za-z0-9]+$")
    kind: Literal["gif", "sticker"] = "gif"


class MessageIn(BaseModel):
    body: str | None = Field(default=None, max_length=4000)
    photo_id: uuid.UUID | None = None
    location: LocationIn | None = None
    reply_to_id: uuid.UUID | None = None
    image_key: str | None = Field(default=None, max_length=300)  # /me/images/upload-url ile yüklenen dosya
    gif: GifIn | None = None


class StartConversationIn(MessageIn):
    username: str


class MessageOut(BaseModel):
    id: uuid.UUID
    conversation_id: uuid.UUID
    sender_id: uuid.UUID
    body: str | None
    photo: PhotoCard | None = None
    location: LocationIn | None = None
    created_at: datetime
    reply_to: "MessageQuote | None" = None
    image: ImageVariant | None = None
    gif: "GifOut | None" = None
    reactions: list["ReactionOut"] = Field(default_factory=list)


class MessageQuote(BaseModel):
    id: uuid.UUID
    sender_id: uuid.UUID
    kind: str  # text | photo | image | gif | location
    preview: str | None


class GifOut(BaseModel):
    id: str
    kind: str
    url: str
    width: int
    height: int


class ReactionOut(BaseModel):
    user_id: uuid.UUID
    emoji: str


class ReactionIn(BaseModel):
    emoji: str = Field(min_length=1, max_length=16)


class ConversationOut(BaseModel):
    id: uuid.UUID
    other: UserCard
    status: str  # request | accepted | declined
    is_request_to_me: bool
    last_message: MessageOut | None
    unread: int
    last_message_at: datetime
    other_last_read_at: datetime | None  # "görüldü" bilgisi


class MessagePage(BaseModel):
    items: list[MessageOut]
    next_cursor: str | None


class MapPhotographer(BaseModel):
    user: UserCard
    lat: float
    lng: float
    city: str | None
    country: str | None
    specialties: list[str]


class MapPhotoPoint(BaseModel):
    photo_id: uuid.UUID
    lat: float
    lng: float
    title: str | None
    thumb_url: str | None
    user: UserCard


class MapCluster(BaseModel):
    lat: float
    lng: float
    count: int
    thumb_url: str | None = None  # fotoğraf katmanında kümenin en yeni karesi


class PhotographerMap(BaseModel):
    clusters: list[MapCluster]
    photographers: list[MapPhotographer]
    total: int


class PhotoMap(BaseModel):
    clusters: list[MapCluster]
    photos: list[MapPhotoPoint]
    total: int


# =====================================================================  Faz 4
class BillingStatus(BaseModel):
    is_pro: bool
    store: str | None  # app_store | play_store | stripe
    status: str | None
    period_end: datetime | None
    will_renew: bool
    can_manage_on_web: bool
    prices: dict[str, str]


class CheckoutIn(BaseModel):
    plan: Literal["monthly", "yearly"]


# =====================================================================  Revizyon 7
# ---------- Haftalık tema
class ThemeIn(BaseModel):
    title_tr: str = Field(min_length=1, max_length=100)
    title_en: str = Field(min_length=1, max_length=100)
    description_tr: str | None = Field(default=None, max_length=1000)
    description_en: str | None = Field(default=None, max_length=1000)
    starts_at: datetime
    ends_at: datetime


class ThemeUpdate(BaseModel):
    title_tr: str | None = Field(default=None, min_length=1, max_length=100)
    title_en: str | None = Field(default=None, min_length=1, max_length=100)
    description_tr: str | None = Field(default=None, max_length=1000)
    description_en: str | None = Field(default=None, max_length=1000)
    starts_at: datetime | None = None
    ends_at: datetime | None = None


class ThemeEntryOut(BaseModel):
    id: uuid.UUID
    theme_id: uuid.UUID
    created_at: datetime
    rank: int | None = None  # yalnızca sort=top listesinde ve kazananda
    photo: PhotoCard


class ThemeEntryPage(BaseModel):
    items: list[ThemeEntryOut]
    next_cursor: str | None


class ThemeOut(BaseModel):
    id: uuid.UUID
    number: int
    title: str        # isteğin diline göre (Accept-Language)
    description: str | None
    starts_at: datetime
    ends_at: datetime
    status: str       # scheduled | active | ended (sonuç işleniyor) | finished
    entry_count: int
    my_entry: ThemeEntryOut | None = None
    winner: ThemeEntryOut | None = None
    finalized_at: datetime | None = None


class ThemePage(BaseModel):
    items: list[ThemeOut]
    next_cursor: str | None


class ThemeAdminOut(BaseModel):
    id: uuid.UUID
    number: int
    title_tr: str
    title_en: str
    description_tr: str | None
    description_en: str | None
    starts_at: datetime
    ends_at: datetime
    status: str
    entry_count: int
    winner_entry_id: uuid.UUID | None
    finalized_at: datetime | None
    created_at: datetime


class ThemeWinOut(BaseModel):
    theme_id: uuid.UUID
    number: int
    title: str
    won_at: datetime | None
    like_count: int
    photo: PhotoCard


# ---------- Eleştiri
class CritiqueIn(BaseModel):
    composition: int = Field(ge=1, le=5)
    light: int = Field(ge=1, le=5)
    focus: int = Field(ge=1, le=5)
    editing: int = Field(ge=1, le=5)
    good: str | None = Field(default=None, max_length=1000)
    improve: str | None = Field(default=None, max_length=1000)


class CritiqueOut(BaseModel):
    id: uuid.UUID
    photo_id: uuid.UUID
    user: UserCard
    author_specialties: list[str]  # alt başlık için (ör. ["landscape", "astro"]); deneyim yılı alanı yok
    composition: int
    light: int
    focus: int
    editing: int
    average: float
    good: str | None
    improve: str | None
    helpful_count: int
    helpful_by_me: bool
    mine: bool
    can_delete: bool
    created_at: datetime
    updated_at: datetime


class CritiqueAverages(BaseModel):
    composition: float | None
    light: float | None
    focus: float | None
    editing: float | None
    overall: float | None


class CritiqueList(BaseModel):
    count: int
    averages: CritiqueAverages
    items: list[CritiqueOut]
    my_critique: CritiqueOut | None
    can_critique: bool
    critique_requested: bool
    critique_question: str | None


# ---------- Koleksiyonlar
class CollectionIn(BaseModel):
    title: str = Field(min_length=1, max_length=100)
    description: str | None = Field(default=None, max_length=500)
    photo_ids: list[uuid.UUID] = Field(default_factory=list, max_length=200)


class CollectionUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=100)
    description: str | None = Field(default=None, max_length=500)


class CollectionPhotosIn(BaseModel):
    photo_ids: list[uuid.UUID] = Field(max_length=200)


class CollectionPhotoIn(BaseModel):
    photo_id: uuid.UUID


class CollectionOrderIn(BaseModel):
    collection_ids: list[uuid.UUID] = Field(max_length=50)


class CollectionCard(BaseModel):
    id: uuid.UUID
    title: str
    description: str | None
    photo_count: int
    covers: list[dict[str, ImageVariant]]  # ilk en fazla 3 karenin görsel türevleri (thumb/feed/full)
    position: int
    updated_at: datetime
    contains_photo: bool | None = None  # yalnızca GET /me/collections?photo_id=... ile


class CollectionOut(CollectionCard):
    owner: UserCard
    is_mine: bool
    photos: list[PhotoCard]
    created_at: datetime


# ---------- Topluluk etkinlikleri
class EventIn(BaseModel):
    title: str = Field(min_length=1, max_length=150)
    description: str | None = Field(default=None, max_length=3000)
    starts_at: datetime
    ends_at: datetime | None = None
    location_name: str = Field(min_length=1, max_length=200)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    capacity: int | None = Field(default=None, ge=1, le=10000)
    bring: str | None = Field(default=None, max_length=500)


class EventUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=150)
    description: str | None = Field(default=None, max_length=3000)
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    location_name: str | None = Field(default=None, min_length=1, max_length=200)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    capacity: int | None = Field(default=None, ge=1, le=10000)
    bring: str | None = Field(default=None, max_length=500)


class EventCard(BaseModel):
    id: uuid.UUID
    community: CommunityCard
    title: str
    starts_at: datetime
    ends_at: datetime | None
    location_name: str
    latitude: float | None
    longitude: float | None
    capacity: int | None
    attendee_count: int
    attending: bool
    status: str  # upcoming | ongoing | past | cancelled
    cancelled_at: datetime | None


class EventOut(EventCard):
    description: str | None
    bring: str | None
    created_by: UserCard | None
    created_at: datetime
    attendees_preview: list[UserCard]  # en fazla 8
    my_role: str | None  # topluluktaki rolüm: owner | admin | member | None
    can_manage: bool
    conversation_id: uuid.UUID | None = None  # toplulukların grup sohbeti yok; şimdilik hep null


class EventList(BaseModel):
    upcoming: list[EventCard]  # yaklaşan ve süren, en yakın önce
    past: list[EventCard]      # geçmiş, en yeni önce


# ---------- Çekim planları
PlanKind = Literal["milkyway", "golden", "blue", "moonrise", "meteor", "other"]


class PlanIn(BaseModel):
    kind: PlanKind
    title: str | None = Field(default=None, max_length=120)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    place_name: str | None = Field(default=None, max_length=200)
    target_at: datetime
    remind: bool = True
    weather_alert: bool = False
    notes: str | None = Field(default=None, max_length=1000)


class PlanUpdate(BaseModel):
    kind: PlanKind | None = None
    title: str | None = Field(default=None, max_length=120)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    place_name: str | None = Field(default=None, max_length=200)
    target_at: datetime | None = None
    remind: bool | None = None
    weather_alert: bool | None = None
    notes: str | None = Field(default=None, max_length=1000)


class PlanOut(ORM):
    id: uuid.UUID
    kind: str
    title: str | None
    latitude: float
    longitude: float
    place_name: str | None
    target_at: datetime
    remind: bool
    weather_alert: bool
    notes: str | None
    created_at: datetime
    reminded_day_at: datetime | None
    reminded_hour_at: datetime | None
    weather_alerted_at: datetime | None
    weather_checked_at: datetime | None
    last_cloud_cover: int | None
    status: str = "upcoming"  # upcoming | past


class PlanPage(BaseModel):
    items: list[PlanOut]
    next_cursor: str | None


# ---------- Ekipman keşfi
class GearSettings(BaseModel):
    median_shutter_seconds: float | None
    median_shutter_display: str | None
    median_aperture: float | None
    median_iso: int | None
    median_focal_length_mm: float | None
    sample_size: int


class GearStats(BaseModel):
    camera: str | None
    lens: str | None
    photo_count: int
    photographer_count: int
    top_photographers: list[UserCard]
    common_settings: GearSettings


class GearName(BaseModel):
    kind: str  # camera | lens
    name: str
    photo_count: int


MessageOut.model_rebuild()
