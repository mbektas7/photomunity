"""İşlemsel e-postalar (TR/EN). RESEND_API_KEY yoksa e-posta log'a yazılır."""
import html
import logging

import httpx

from app.core.config import get_settings

log = logging.getLogger("photomunity.email")

TEMPLATES = {
    "verify_email": {
        "tr": ("E-posta adresini doğrula", "Photomunity'ye hoş geldin! Hesabını doğrulamak için butona dokun.", "E-postamı doğrula"),
        "en": ("Verify your email", "Welcome to Photomunity! Tap the button to verify your account.", "Verify my email"),
    },
    "reset_password": {
        "tr": ("Şifreni sıfırla", "Şifre sıfırlama talebi aldık. Bu sen değilsen e-postayı yok sayabilirsin.", "Yeni şifre belirle"),
        "en": ("Reset your password", "We received a password reset request. If it wasn't you, ignore this email.", "Set a new password"),
    },
    "community_invite": {
        "tr": ("Topluluk yöneticiliğine davet edildin", "Bir Photomunity topluluğunda yönetici olarak davet edildin. Kabul etmek için bu e-posta adresiyle hesap oluştur ya da giriş yap.", "Daveti kabul et"),
        "en": ("You're invited to help run a community", "You've been invited as an admin of a Photomunity community. Sign up or log in with this email address to accept.", "Accept invitation"),
    },
    "judge_invite": {
        "tr": ("Jüri daveti", "Bir Photomunity fotoğraf yarışmasında jüri üyesi olarak davet edildin. Kabul etmek için bu e-posta adresiyle hesap oluştur ya da giriş yap.", "Daveti kabul et"),
        "en": ("Invitation to judge", "You've been invited to judge a Photomunity photo contest. Sign up or log in with this email address to accept.", "Accept invitation"),
    },
    "vote_code": {
        "tr": ("Oy verme kodun: {code}", "Fotoğraf yarışmasında oy vermek için bu kodu gir: <strong style=\"font-size:28px;letter-spacing:4px\">{code}</strong><br>Kod 10 dakika geçerlidir. Bu isteği sen yapmadıysan e-postayı yok sayabilirsin.", None),
        "en": ("Your voting code: {code}", "Enter this code to vote in the photo contest: <strong style=\"font-size:28px;letter-spacing:4px\">{code}</strong><br>The code is valid for 10 minutes. If you didn't request it, ignore this email.", None),
    },
    "password_changed": {
        "tr": ("Şifren değişti", "Hesabının şifresi değiştirildi. Bu sen değilsen hemen bizimle iletişime geç.", None),
        "en": ("Your password was changed", "Your account password was changed. If this wasn't you, contact us right away.", None),
    },
}


def render(template: str, locale: str, link: str | None = None, code: str | None = None) -> tuple[str, str]:
    subject, body, cta = TEMPLATES[template].get(locale, TEMPLATES[template]["en"])
    if code is not None:
        subject, body = subject.format(code=html.escape(code)), body.format(code=html.escape(code))
    button = (
        f'<p style="margin:32px 0"><a href="{html.escape(link)}" style="background:#111;color:#fff;'
        f'padding:14px 22px;border-radius:999px;text-decoration:none;font-weight:600">{cta}</a></p>'
        if link and cta else ""
    )
    page = (
        '<div style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;max-width:520px;margin:auto;'
        'padding:32px;color:#111">'
        '<p style="font-size:20px;font-weight:700;letter-spacing:-0.02em">Photomunity</p>'
        f'<h1 style="font-size:24px;letter-spacing:-0.02em">{subject}</h1>'
        f'<p style="font-size:16px;line-height:1.5;color:#444">{body}</p>{button}</div>'
    )
    return subject, page


async def send_template(to: str, template: str, locale: str, link: str | None = None, code: str | None = None) -> None:
    s = get_settings()
    subject, page = render(template, locale, link, code)
    if not s.resend_api_key:
        log.info("E-posta (dev) -> %s | %s | %s", to, subject, link or code or "")
        return
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.post(
                "https://api.resend.com/emails",
                headers={"Authorization": f"Bearer {s.resend_api_key}"},
                json={"from": s.email_from, "to": [to], "subject": subject, "html": page},
            )
            r.raise_for_status()
    except httpx.HTTPError:
        log.exception("E-posta gönderilemedi: %s", to)
