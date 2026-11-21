from functools import lru_cache

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

_DEV_JWT_SECRET = "change-me-in-production"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "Photomunity API"
    environment: str = "development"  # development | test | production
    api_prefix: str = "/api/v1"
    frontend_url: str = "http://localhost:3000"
    cors_origins: list[str] = ["http://localhost:3000"]

    database_url: str = "postgresql+asyncpg://photomunity:photomunity@localhost:5432/photomunity"
    redis_url: str = "redis://localhost:6379/0"

    # JWT
    jwt_secret: str = _DEV_JWT_SECRET
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 15
    refresh_token_days: int = 30

    # OAuth: geçerli "aud" değerleri (web + iOS + Android client id'leri)
    google_client_ids: list[str] = []
    apple_client_ids: list[str] = []  # iOS bundle id + web Services ID

    # S3 uyumlu depolama (AWS S3 / MinIO). Yükleme presigned POST ile yapılır; Cloudflare R2 bunu desteklemez.
    s3_endpoint_url: str | None = None
    # Tarayıcının/uygulamanın yükleme yaptığı adres. Kendi sunucunda MinIO kullanırken API iç ağdan
    # (http://minio:9000) bağlanır, imzalı yükleme adresi ise dışarıdan erişilen alan adını gösterir.
    s3_public_endpoint_url: str | None = None
    s3_region: str = "auto"
    s3_access_key: str = ""
    s3_secret_key: str = ""
    s3_bucket: str = "photomunity"
    cdn_base_url: str = ""  # yalnızca photos/ önekini yayınlayan CDN
    upload_url_ttl_seconds: int = 900

    # E-posta (Resend). Anahtar yoksa e-postalar log'a yazılır.
    resend_api_key: str = ""
    email_from: str = "Photomunity <no-reply@photomunity.com>"

    # Kalite eşikleri
    min_long_edge_px: int = 1080      # 1080×1350, 1080×1440, 1080×608 (Instagram boyutları) kabul edilir
    min_file_bytes: int = 0           # alt dosya boyutu sınırı yok; kalite çözünürlük ve netlikle ölçülür
    max_file_bytes: int = 40_000_000
    min_sharpness: float = 60.0          # karo bazlı Laplacian varyansı (90. yüzdelik)
    max_highlight_clip: float = 0.20     # patlamış piksel oranı
    max_shadow_clip: float = 0.50        # tamamen siyah piksel oranı (astro için cömert)

    # Profil görselleri
    max_profile_image_bytes: int = 15_000_000
    min_avatar_px: int = 200
    min_cover_width_px: int = 1080   # yükleme kuralıyla aynı: 1080 genişlikteki fotoğraflar kapak olabilir

    # Push bildirimleri (Firebase Cloud Messaging HTTP v1). Servis hesabı JSON'u dosya yolu veya içerik olarak.
    fcm_service_account_file: str | None = None
    fcm_service_account_json: str | None = None

    # İstek sınırlama (Redis varsa Redis'te, yoksa süreç belleğinde)
    rate_limit_enabled: bool = True
    trust_proxy_headers: bool = False  # yalnızca güvenilir bir ters vekil arkasında açın

    # Moderasyon
    moderation_provider: str = "none"  # none | rekognition
    moderation_min_confidence: float = 80.0
    report_auto_hide_threshold: int = 5  # bu kadar farklı kişi şikayet ederse fotoğraf incelemeye kadar gizlenir

    # Yarışmalar / halk oylaması
    turnstile_secret: str = ""  # Cloudflare Turnstile; boşsa bot doğrulaması atlanır
    vote_code_minutes: int = 10
    suspicious_voters_per_ip: int = 5  # aynı IP'den bu kadar seçmen yönetici özetinde işaretlenir

    # Pro abonelik
    pro_price_monthly_display: str = "$1.99"   # web vitrin fiyatı; mobilde fiyat mağazadan gelir
    pro_price_yearly_display: str = "$17.99"
    stripe_secret_key: str = ""
    stripe_webhook_secret: str = ""
    stripe_price_monthly: str = ""  # price_... (Stripe Dashboard)
    stripe_price_yearly: str = ""
    revenuecat_webhook_auth: str = ""   # RevenueCat webhook'unda tanımlanan Authorization başlığı
    revenuecat_secret_key: str = ""     # anında senkron için REST API (sk_...)
    revenuecat_entitlement: str = "pro"
    pro_upload_limit_per_hour: int = 200

    @model_validator(mode="after")
    def _production_guard(self) -> "Settings":
        """Üretimde geliştirme varsayılanlarıyla açılmayı engeller."""
        if self.environment != "production":
            return self
        problems = []
        if self.jwt_secret == _DEV_JWT_SECRET or len(self.jwt_secret) < 32:
            problems.append("JWT_SECRET en az 32 karakterlik rastgele bir değer olmalı (openssl rand -hex 32)")
        if any("localhost" in o for o in self.cors_origins) or "localhost" in self.frontend_url:
            problems.append("FRONTEND_URL ve CORS_ORIGINS gerçek alan adını göstermeli")
        if not self.s3_access_key or not self.s3_secret_key or self.s3_access_key == "minioadmin":
            problems.append("S3_ACCESS_KEY / S3_SECRET_KEY üretim depolamasının anahtarları olmalı")
        if not self.cdn_base_url or "localhost" in self.cdn_base_url:
            problems.append("CDN_BASE_URL fotoğrafların yayınlandığı adres olmalı")
        if problems:
            raise ValueError("Üretim ayarları eksik: " + "; ".join(problems))
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
