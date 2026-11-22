import enum
import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    JSON, BigInteger, Boolean, DateTime, Enum, Float, ForeignKey, Index, Integer, String, Text,
    UniqueConstraint, Uuid, false, func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class AuthProvider(str, enum.Enum):
    email = "email"
    google = "google"
    apple = "apple"


class EquipmentType(str, enum.Enum):
    body = "body"
    lens = "lens"
    tripod = "tripod"
    filter = "filter"
    flash = "flash"
    drone = "drone"
    other = "other"


class PhotoStatus(str, enum.Enum):
    pending = "pending"        # yükleme URL'i verildi
    processing = "processing"  # kalite kontrol ve türev üretimi
    published = "published"
    rejected = "rejected"


class TokenPurpose(str, enum.Enum):
    verify_email = "verify_email"
    reset_password = "reset_password"


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _created() -> Mapped[datetime]:
    # Uygulama tarafında mikrosaniye hassasiyetli; sıralamalar aynı saniyedeki kayıtlarda da kararlı kalır
    return mapped_column(DateTime(timezone=True), default=_now, server_default=func.now(), nullable=False)


class User(Base):
    __tablename__ = "users"
    __table_args__ = (Index("ix_users_geo", "latitude", "longitude"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    email_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    username: Mapped[str] = mapped_column(String(30), unique=True, index=True)
    display_name: Mapped[str] = mapped_column(String(80))
    bio: Mapped[str | None] = mapped_column(Text)
    avatar_url: Mapped[str | None] = mapped_column(String(500))
    cover_url: Mapped[str | None] = mapped_column(String(500))
    website: Mapped[str | None] = mapped_column(String(300))
    specialties: Mapped[list] = mapped_column(JSON, default=list)  # astro, street, portrait...
    locale: Mapped[str] = mapped_column(String(5), default="tr")
    is_public: Mapped[bool] = mapped_column(Boolean, default=True)
    city: Mapped[str | None] = mapped_column(String(120))
    country: Mapped[str | None] = mapped_column(String(2))  # ISO 3166-1 alpha-2
    # Gizlilik için ~5 km'ye yuvarlanmış koordinat. Faz 3'te PostGIS geography kolonuna taşınacak.
    latitude: Mapped[float | None] = mapped_column(Float)
    longitude: Mapped[float | None] = mapped_column(Float)
    is_pro: Mapped[bool] = mapped_column(Boolean, default=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    is_admin: Mapped[bool] = mapped_column(Boolean, default=False)
    avatar_key: Mapped[str | None] = mapped_column(String(500))
    cover_key: Mapped[str | None] = mapped_column(String(500))
    notification_prefs: Mapped[dict] = mapped_column(JSON, default=dict)  # {"push": {"photo_liked": false}}
    created_at: Mapped[datetime] = _created()


class AuthIdentity(Base):
    __tablename__ = "auth_identities"
    __table_args__ = (UniqueConstraint("provider", "provider_uid"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    provider: Mapped[AuthProvider] = mapped_column(Enum(AuthProvider, name="auth_provider"))
    provider_uid: Mapped[str] = mapped_column(String(320))
    password_hash: Mapped[str | None] = mapped_column(String(255))
    created_at: Mapped[datetime] = _created()


class RefreshSession(Base):
    __tablename__ = "refresh_sessions"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)  # JWT jti
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = _created()


class OneTimeToken(Base):
    __tablename__ = "one_time_tokens"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    purpose: Mapped[TokenPurpose] = mapped_column(Enum(TokenPurpose, name="token_purpose"))
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Equipment(Base):
    __tablename__ = "equipment"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    type: Mapped[EquipmentType] = mapped_column(Enum(EquipmentType, name="equipment_type"))
    brand: Mapped[str] = mapped_column(String(80))
    model: Mapped[str] = mapped_column(String(120))
    position: Mapped[int] = mapped_column(Integer, default=0)


class Photo(Base):
    __tablename__ = "photos"
    __table_args__ = (Index("ix_photos_geo", "latitude", "longitude"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    title: Mapped[str | None] = mapped_column(String(150))
    description: Mapped[str | None] = mapped_column(Text)
    tags: Mapped[list] = mapped_column(JSON, default=list)
    original_key: Mapped[str] = mapped_column(String(500))
    content_type: Mapped[str] = mapped_column(String(50))
    variants: Mapped[dict] = mapped_column(JSON, default=dict)  # {"thumb": {"key","width","height"}, ...}
    width: Mapped[int | None] = mapped_column(Integer)
    height: Mapped[int | None] = mapped_column(Integer)
    size_bytes: Mapped[int | None] = mapped_column(BigInteger)
    status: Mapped[PhotoStatus] = mapped_column(Enum(PhotoStatus, name="photo_status"), default=PhotoStatus.pending, index=True)
    rejection_codes: Mapped[list] = mapped_column(JSON, default=list)
    quality: Mapped[dict] = mapped_column(JSON, default=dict)
    # Kullanıcının bilinçli olarak eklediği konum (opsiyonel)
    latitude: Mapped[float | None] = mapped_column(Float)
    longitude: Mapped[float | None] = mapped_column(Float)
    location_name: Mapped[str | None] = mapped_column(String(200))
    created_at: Mapped[datetime] = _created()
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    hidden: Mapped[bool] = mapped_column(Boolean, default=False, index=True)  # moderasyon nedeniyle gizli

    user: Mapped[User] = relationship(lazy="raise")
    exif: Mapped["PhotoExif | None"] = relationship(lazy="raise", uselist=False)


class PhotoExif(Base):
    __tablename__ = "photo_exif"

    photo_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("photos.id", ondelete="CASCADE"), primary_key=True)
    camera_make: Mapped[str | None] = mapped_column(String(100))
    camera_model: Mapped[str | None] = mapped_column(String(100))
    lens: Mapped[str | None] = mapped_column(String(150))
    focal_length_mm: Mapped[float | None] = mapped_column(Float)
    focal_length_35mm: Mapped[int | None] = mapped_column(Integer)
    aperture: Mapped[float | None] = mapped_column(Float)
    exposure_time: Mapped[float | None] = mapped_column(Float)
    shutter_display: Mapped[str | None] = mapped_column(String(20))
    iso: Mapped[int | None] = mapped_column(Integer)
    taken_at: Mapped[datetime | None] = mapped_column(DateTime)
    white_balance: Mapped[str | None] = mapped_column(String(20))
    flash_fired: Mapped[bool | None] = mapped_column(Boolean)
    # EXIF GPS: kamuya açık değildir, yalnızca sahibine konum önerisi olarak gösterilir.
    gps_latitude: Mapped[float | None] = mapped_column(Float)
    gps_longitude: Mapped[float | None] = mapped_column(Float)
    raw: Mapped[dict] = mapped_column(JSON, default=dict)


class Like(Base):
    __tablename__ = "likes"

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    photo_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("photos.id", ondelete="CASCADE"), primary_key=True, index=True)
    created_at: Mapped[datetime] = _created()


class Follow(Base):
    __tablename__ = "follows"

    follower_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    followee_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True, index=True)
    created_at: Mapped[datetime] = _created()


class DeviceToken(Base):
    """Push bildirimleri için FCM token'ları (Faz 1 sonunda bildirim servisi bağlanacak)."""

    __tablename__ = "device_tokens"

    token: Mapped[str] = mapped_column(String(500), primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    platform: Mapped[str] = mapped_column(String(10))  # ios | android | web
    created_at: Mapped[datetime] = _created()


class Notification(Base):
    """Uygulama içi bildirim. Push, kullanıcının tercihlerine göre ayrıca gönderilir."""

    __tablename__ = "notifications"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    type: Mapped[str] = mapped_column(String(40))
    actor_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    photo_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("photos.id", ondelete="CASCADE"))
    data: Mapped[dict] = mapped_column(JSON, default=dict)
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, server_default=func.now(), index=True)

    actor: Mapped["User | None"] = relationship(foreign_keys=[actor_id], lazy="raise")
    photo: Mapped["Photo | None"] = relationship(lazy="raise")


class ReportReason(str, enum.Enum):
    spam = "spam"
    nudity = "nudity"
    violence = "violence"
    harassment = "harassment"
    copyright = "copyright"
    other = "other"


class Report(Base):
    __tablename__ = "reports"
    __table_args__ = (UniqueConstraint("reporter_id", "target_type", "target_id"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    reporter_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    target_type: Mapped[str] = mapped_column(String(10))  # photo | user
    target_id: Mapped[uuid.UUID] = mapped_column(Uuid, index=True)
    reason: Mapped[ReportReason] = mapped_column(Enum(ReportReason, name="report_reason"))
    note: Mapped[str | None] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(12), default="open", index=True)  # open | resolved
    resolution: Mapped[str | None] = mapped_column(String(20))
    created_at: Mapped[datetime] = _created()


# =====================================================================  Faz 2: Topluluklar


class CommunityRole(str, enum.Enum):
    owner = "owner"
    admin = "admin"
    member = "member"


class Community(Base):
    __tablename__ = "communities"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    slug: Mapped[str] = mapped_column(String(60), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(100))
    description: Mapped[str | None] = mapped_column(Text)
    city: Mapped[str | None] = mapped_column(String(120))
    country: Mapped[str | None] = mapped_column(String(2))
    logo_key: Mapped[str | None] = mapped_column(String(500))
    logo_url: Mapped[str | None] = mapped_column(String(500))
    cover_key: Mapped[str | None] = mapped_column(String(500))
    cover_url: Mapped[str | None] = mapped_column(String(500))
    owner_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    # Açıksa "Katıl" doğrudan üye yapmaz; istek oluşturur, yöneticiler onaylar
    join_approval: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    hidden: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false(), index=True)  # site yönetimi gizledi
    created_at: Mapped[datetime] = _created()


class CommunityJoinRequest(Base):
    """Onaylı katılım isteyen topluluğa bekleyen katılma isteği."""
    __tablename__ = "community_join_requests"

    community_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("communities.id", ondelete="CASCADE"), primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True, index=True)
    created_at: Mapped[datetime] = _created()

    user: Mapped[User] = relationship(lazy="raise")


class CommunityMember(Base):
    __tablename__ = "community_members"

    community_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("communities.id", ondelete="CASCADE"), primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True, index=True)
    role: Mapped[CommunityRole] = mapped_column(Enum(CommunityRole, name="community_role"), default=CommunityRole.member)
    joined_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, server_default=func.now(), index=True)

    user: Mapped[User] = relationship(lazy="raise")


class CommunityInvite(Base):
    """Henüz hesabı olmayan birini yönetici olarak davet etmek için."""

    __tablename__ = "community_invites"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    community_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("communities.id", ondelete="CASCADE"), index=True)
    email: Mapped[str] = mapped_column(String(320), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    invited_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    accepted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class CommunityPost(Base):
    __tablename__ = "community_posts"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    community_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("communities.id", ondelete="CASCADE"), index=True)
    author_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    kind: Mapped[str] = mapped_column(String(10))  # photo | news | contest
    title: Mapped[str | None] = mapped_column(String(200))
    body: Mapped[str | None] = mapped_column(Text)
    photo_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("photos.id", ondelete="CASCADE"))
    contest_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("contests.id", ondelete="CASCADE"))
    # Haber fotoğrafları: [{"key", "url", "width", "height"}], en fazla 10, kırpılmadan
    images: Mapped[list] = mapped_column(JSON, default=list, server_default="[]")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, server_default=func.now(), index=True)

    author: Mapped[User] = relationship(lazy="raise")
    photo: Mapped["Photo | None"] = relationship(lazy="raise")


# =====================================================================  Faz 2: Yarışmalar


class Contest(Base):
    __tablename__ = "contests"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    community_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("communities.id", ondelete="CASCADE"), index=True)
    title: Mapped[str] = mapped_column(String(150))
    description: Mapped[str] = mapped_column(Text)
    rules: Mapped[str | None] = mapped_column(Text)
    submission_deadline: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    voting_end: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    results_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    judging_mode: Mapped[str] = mapped_column(String(10))  # jury | public
    anonymous: Mapped[bool] = mapped_column(Boolean, default=True)  # oylama bitene kadar fotoğrafçı gizli
    min_votes: Mapped[int] = mapped_column(Integer, default=5)  # halk oylamasında Bayes ortalaması için m
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    finalized_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    deadline_reminder_sent: Mapped[bool] = mapped_column(Boolean, default=False)
    hidden: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false(), index=True)  # site yönetimi gizledi
    cancelled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))  # site yönetimi iptal etti
    results: Mapped[list] = mapped_column(JSON, default=list)
    created_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    created_at: Mapped[datetime] = _created()

    community: Mapped[Community] = relationship(lazy="raise")


class ContestPrize(Base):
    __tablename__ = "contest_prizes"
    __table_args__ = (UniqueConstraint("contest_id", "rank"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    contest_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("contests.id", ondelete="CASCADE"), index=True)
    rank: Mapped[int] = mapped_column(Integer)
    title: Mapped[str] = mapped_column(String(200))


class ContestJudge(Base):
    __tablename__ = "contest_judges"
    __table_args__ = (UniqueConstraint("contest_id", "user_id"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    contest_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("contests.id", ondelete="CASCADE"), index=True)
    user_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    email: Mapped[str | None] = mapped_column(String(320))  # hesabı olmayan davetli
    token_hash: Mapped[str | None] = mapped_column(String(64), unique=True)
    weight: Mapped[float] = mapped_column(Float, default=1.0)
    created_at: Mapped[datetime] = _created()

    user: Mapped["User | None"] = relationship(lazy="raise")


class ContestEntry(Base):
    __tablename__ = "contest_entries"
    __table_args__ = (UniqueConstraint("contest_id", "user_id"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    contest_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("contests.id", ondelete="CASCADE"), index=True)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    photo_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("photos.id", ondelete="CASCADE"))
    disqualified: Mapped[bool] = mapped_column(Boolean, default=False)
    disqualify_reason: Mapped[str | None] = mapped_column(String(300))
    created_at: Mapped[datetime] = _created()

    user: Mapped[User] = relationship(lazy="raise")
    photo: Mapped[Photo] = relationship(lazy="raise")


class JuryScore(Base):
    __tablename__ = "jury_scores"

    entry_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("contest_entries.id", ondelete="CASCADE"), primary_key=True)
    judge_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("contest_judges.id", ondelete="CASCADE"), primary_key=True)
    score: Mapped[int] = mapped_column(Integer)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, server_default=func.now(), onupdate=_now)


class PublicVoter(Base):
    """Halk oylamasında bir kişi = bir e-posta. Giriş yapmış kullanıcının e-postası da aynı anahtara düşer."""

    __tablename__ = "public_voters"
    __table_args__ = (UniqueConstraint("contest_id", "email_normalized"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    contest_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("contests.id", ondelete="CASCADE"), index=True)
    email_normalized: Mapped[str] = mapped_column(String(320))
    user_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    ip_hash: Mapped[str | None] = mapped_column(String(32), index=True)
    created_at: Mapped[datetime] = _created()


class PublicVote(Base):
    __tablename__ = "public_votes"

    voter_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("public_voters.id", ondelete="CASCADE"), primary_key=True)
    entry_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("contest_entries.id", ondelete="CASCADE"), primary_key=True, index=True)
    stars: Mapped[int] = mapped_column(Integer)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, server_default=func.now(), onupdate=_now)


class VoteCode(Base):
    __tablename__ = "vote_codes"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    contest_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("contests.id", ondelete="CASCADE"), index=True)
    email_normalized: Mapped[str] = mapped_column(String(320), index=True)
    code_hash: Mapped[str] = mapped_column(String(64))
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


# =====================================================================  Faz 3: Mesajlaşma


class Conversation(Base):
    """İki kişi arasındaki tek sohbet. İlk mesaj alıcıda "istek" olarak bekler; kabul edilince açılır."""

    __tablename__ = "conversations"
    __table_args__ = (UniqueConstraint("user_low_id", "user_high_id"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_low_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    user_high_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    status: Mapped[str] = mapped_column(String(10), default="request")  # request | accepted | declined
    requested_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    created_at: Mapped[datetime] = _created()
    last_message_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, index=True)

    def other(self, user_id: uuid.UUID) -> uuid.UUID:
        return self.user_high_id if self.user_low_id == user_id else self.user_low_id


class ConversationRead(Base):
    __tablename__ = "conversation_reads"

    conversation_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("conversations.id", ondelete="CASCADE"), primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    last_read_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)


class Message(Base):
    __tablename__ = "messages"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    conversation_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("conversations.id", ondelete="CASCADE"), index=True)
    sender_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    body: Mapped[str | None] = mapped_column(Text)
    photo_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("photos.id", ondelete="SET NULL"))
    latitude: Mapped[float | None] = mapped_column(Float)
    longitude: Mapped[float | None] = mapped_column(Float)
    location_name: Mapped[str | None] = mapped_column(String(200))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, server_default=func.now(), index=True)

    photo: Mapped["Photo | None"] = relationship(lazy="raise")


class Block(Base):
    __tablename__ = "blocks"

    blocker_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    blocked_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True, index=True)
    created_at: Mapped[datetime] = _created()


# =====================================================================  Faz 4: Pro abonelik


class Subscription(Base):
    """Bir mağazadaki (App Store, Google Play, Stripe) abonelik kaydı. Kullanıcının Pro olup olmadığı
    tüm kayıtlarından türetilir: herhangi biri geçerliyse Pro'dur (platformdan bağımsız)."""

    __tablename__ = "subscriptions"
    __table_args__ = (UniqueConstraint("external_id"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    store: Mapped[str] = mapped_column(String(16))  # app_store | play_store | stripe
    external_id: Mapped[str] = mapped_column(String(200))  # RevenueCat original_transaction_id / Stripe subscription id
    product_id: Mapped[str | None] = mapped_column(String(200))
    status: Mapped[str] = mapped_column(String(16))  # active | grace | cancelled | expired
    will_renew: Mapped[bool] = mapped_column(Boolean, default=True)
    period_end: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, onupdate=_now)


class StripeCustomer(Base):
    __tablename__ = "stripe_customers"

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    customer_id: Mapped[str] = mapped_column(String(100), unique=True)


class ProcessedWebhook(Base):
    """Aynı webhook olayının iki kez işlenmesini önler (mağazalar yeniden dener)."""

    __tablename__ = "processed_webhooks"

    event_id: Mapped[str] = mapped_column(String(200), primary_key=True)
    created_at: Mapped[datetime] = _created()


# =====================================================================  Site yönetimi


class AdminAction(Base):
    """Yönetim panelinde yapılan her işlemin kaydı."""

    __tablename__ = "admin_actions"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    admin_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), index=True)
    action: Mapped[str] = mapped_column(String(40))  # photo_hide, user_disable, announcement_send ...
    kind: Mapped[str] = mapped_column(String(20), index=True)  # moderation | user | content | announcement | team
    target_type: Mapped[str | None] = mapped_column(String(20))
    target_id: Mapped[str | None] = mapped_column(String(60))
    target_label: Mapped[str | None] = mapped_column(String(300))
    note: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, server_default=func.now(), index=True)

    admin: Mapped["User | None"] = relationship(lazy="raise")


class Announcement(Base):
    """Yönetimin duyurusu: push, uygulama içi bildirim ve/veya ana sayfa bandı. Metinler TR ve EN."""

    __tablename__ = "announcements"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    admin_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    channels: Mapped[list] = mapped_column(JSON, default=list)  # push | inbox | banner
    title_tr: Mapped[str] = mapped_column(String(120))
    title_en: Mapped[str] = mapped_column(String(120))
    body_tr: Mapped[str] = mapped_column(String(400))
    body_en: Mapped[str] = mapped_column(String(400))
    link: Mapped[str | None] = mapped_column(String(300))  # uygulama içi yol, örn. /contests/...
    audience: Mapped[dict] = mapped_column(JSON, default=dict)  # {"kind": "all|pro|community|locale|country", "value": ...}
    recipient_count: Mapped[int] = mapped_column(Integer, default=0)
    banner_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, server_default=func.now(), index=True)
