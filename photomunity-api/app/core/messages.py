"""TR/EN hata ve kalite mesajları. İstemci `code` alanına göre kendi çevirisini de gösterebilir."""

MESSAGES: dict[str, dict[str, str]] = {
    "not_authenticated": {"tr": "Giriş yapmanız gerekiyor.", "en": "Authentication required."},
    "invalid_token": {"tr": "Oturum geçersiz veya süresi dolmuş.", "en": "Invalid or expired session."},
    "invalid_credentials": {"tr": "E-posta veya şifre hatalı.", "en": "Incorrect email or password."},
    "invalid_oauth_token": {"tr": "Sosyal giriş doğrulanamadı.", "en": "Social sign-in could not be verified."},
    "email_required": {"tr": "Bu giriş yöntemi için e-posta gerekli.", "en": "An email address is required."},
    "email_taken": {"tr": "Bu e-posta zaten kayıtlı.", "en": "This email is already registered."},
    "username_taken": {"tr": "Bu kullanıcı adı alınmış.", "en": "This username is taken."},
    "account_disabled": {"tr": "Hesap devre dışı.", "en": "Account is disabled."},
    "invalid_link": {"tr": "Bağlantı geçersiz veya süresi dolmuş.", "en": "Link is invalid or expired."},
    "not_found": {"tr": "Bulunamadı.", "en": "Not found."},
    "forbidden": {"tr": "Bu işlem için yetkiniz yok.", "en": "You are not allowed to do this."},
    "private_profile": {"tr": "Bu profil kapalı; fotoğrafları görmek için takip edin.", "en": "This profile is private; follow to see photos."},
    "cannot_follow_self": {"tr": "Kendinizi takip edemezsiniz.", "en": "You cannot follow yourself."},
    "invalid_state": {"tr": "Bu işlem şu anki durumda yapılamaz.", "en": "This action is not possible in the current state."},
    # Kalite kontrolü
    "file_too_small": {"tr": "Dosya en az {min_mb} MB olmalı.", "en": "File must be at least {min_mb} MB."},
    "file_too_large": {"tr": "Dosya en fazla {max_mb} MB olabilir.", "en": "File can be at most {max_mb} MB."},
    "unsupported_format": {"tr": "Desteklenen formatlar: JPEG, PNG, WebP, HEIC.", "en": "Supported formats: JPEG, PNG, WebP, HEIC."},
    "corrupt_image": {"tr": "Görsel okunamadı.", "en": "The image could not be read."},
    "resolution_too_low": {"tr": "Uzun kenar en az {min_px} piksel olmalı.", "en": "Long edge must be at least {min_px} px."},
    "too_blurry": {"tr": "Görsel bulanık görünüyor.", "en": "The image looks blurry."},
    "overexposed": {"tr": "Görselde çok fazla patlamış (beyaz) alan var.", "en": "Too many blown-out highlights."},
    "underexposed": {"tr": "Görsel aşırı karanlık.", "en": "The image is too dark."},
    "too_many_requests": {"tr": "Çok fazla deneme yaptın. Biraz bekleyip tekrar dene.", "en": "Too many attempts. Wait a moment and try again."},
    "inappropriate_content": {"tr": "Görsel topluluk kurallarına uygun görünmüyor.", "en": "The image doesn't appear to follow the community guidelines."},
    "image_too_small": {"tr": "Görsel çok küçük. Profil fotoğrafı en az 200 piksel, kapak en az 600 piksel genişliğinde olmalı.", "en": "The image is too small. Avatars need at least 200 px, covers at least 600 px wide."},
    "already_reported": {"tr": "Bunu zaten bildirdin; inceleniyor.", "en": "You've already reported this; it's being reviewed."},
    "invalid_key": {"tr": "Yükleme bulunamadı, tekrar dene.", "en": "Upload not found, please try again."},
    "slug_taken": {"tr": "Bu adres başka bir topluluk tarafından kullanılıyor.", "en": "This address is taken by another community."},
    "owner_cannot_leave": {"tr": "Topluluğun sahibi topluluktan ayrılamaz.", "en": "The owner can't leave the community."},
    "not_member": {"tr": "Bu işlem için topluluğa üye olmalısın.", "en": "You need to join the community first."},
    "invite_email_mismatch": {"tr": "Bu davet başka bir e-posta adresine gönderildi. O adresle giriş yap.", "en": "This invitation was sent to a different email. Sign in with that address."},
    "contest_locked": {"tr": "Yarışma yayınlandıktan sonra bu alan değiştirilemez.", "en": "This can't be changed after the contest is published."},
    "invalid_dates": {"tr": "Tarihler sırayla olmalı: son gönderim < oylama bitişi ≤ sonuç ilanı, ve son gönderim ileri bir tarih.", "en": "Dates must be in order: submission deadline < voting end ≤ results, and the deadline must be in the future."},
    "judges_required": {"tr": "Jüri değerlendirmesi için en az bir jüri üyesi ekle.", "en": "Add at least one judge for jury judging."},
    "contest_not_open": {"tr": "Bu yarışma şu anda katılıma açık değil.", "en": "This contest isn't open for entries right now."},
    "contest_not_judging": {"tr": "Değerlendirme dönemi henüz başlamadı ya da bitti.", "en": "The judging period hasn't started or is over."},
    "already_entered": {"tr": "Bu yarışmaya zaten bir fotoğrafla katıldın.", "en": "You've already entered this contest."},
    "photo_not_eligible": {"tr": "Yalnızca sana ait, yayında olan bir fotoğrafla katılabilirsin.", "en": "You can only enter with your own published photo."},
    "not_a_judge": {"tr": "Bu yarışmada jüri üyesi değilsin.", "en": "You're not a judge in this contest."},
    "voting_not_public": {"tr": "Bu yarışma jüri tarafından değerlendiriliyor.", "en": "This contest is judged by a jury."},
    "cannot_vote_own": {"tr": "Kendi fotoğrafına oy veremezsin.", "en": "You can't vote for your own photo."},
    "invalid_code": {"tr": "Kod hatalı ya da süresi dolmuş.", "en": "The code is wrong or has expired."},
    "disposable_email": {"tr": "Geçici e-posta adresleriyle oy verilemez.", "en": "Disposable email addresses can't be used to vote."},
    "verification_failed": {"tr": "Bot doğrulaması başarısız. Sayfayı yenileyip tekrar dene.", "en": "Bot check failed. Refresh and try again."},
    "results_not_ready": {"tr": "Sonuçlar henüz ilan edilmedi.", "en": "Results haven't been announced yet."},
    "voter_required": {"tr": "Oy vermek için giriş yap ya da e-postanı doğrula.", "en": "Sign in or verify your email to vote."},
    "cannot_message": {"tr": "Bu kişiye mesaj gönderilemiyor.", "en": "You can't message this person."},
    "request_pending": {"tr": "Mesaj isteğin henüz kabul edilmedi. Kabul edilene kadar en fazla 3 mesaj gönderebilirsin.", "en": "Your message request hasn't been accepted yet. You can send up to 3 messages until then."},
    "empty_message": {"tr": "Boş mesaj gönderilemez.", "en": "You can't send an empty message."},
    "invalid_bbox": {"tr": "Harita alanı geçersiz.", "en": "Invalid map area."},
    "billing_not_configured": {"tr": "Ödeme şu anda kullanılamıyor.", "en": "Payments aren't available right now."},
    "invalid_signature": {"tr": "İmza doğrulanamadı.", "en": "Signature verification failed."},
    "already_pro": {"tr": "Zaten Pro üyesin.", "en": "You're already Pro."},
    "no_web_subscription": {"tr": "Web üzerinden alınmış bir aboneliğin yok; aboneliğini satın aldığın mağazadan yönetebilirsin.", "en": "You don't have a web subscription; manage it in the store where you bought it."},
    "storage_missing": {"tr": "Yüklenen dosya bulunamadı, tekrar yükleyin.", "en": "Uploaded file not found, please upload again."},
}


def message_params() -> dict:
    from app.core.config import get_settings

    s = get_settings()
    return {
        "min_mb": round(s.min_file_bytes / 1_000_000, 1),
        "max_mb": round(s.max_file_bytes / 1_000_000),
        "min_px": s.min_long_edge_px,
    }


def translate(code: str, locale: str) -> str:
    entry = MESSAGES.get(code)
    if not entry:
        return code
    return entry.get(locale, entry["en"]).format(**message_params())
