"""Google ve Apple id_token doğrulaması (JWKS ile imza, issuer ve audience kontrolü)."""
from dataclasses import dataclass

import jwt
from jwt import PyJWKClient

from app.core.config import get_settings

PROVIDERS = {
    "google": ("https://www.googleapis.com/oauth2/v3/certs", {"https://accounts.google.com", "accounts.google.com"}),
    "apple": ("https://appleid.apple.com/auth/keys", {"https://appleid.apple.com"}),
}
_jwks: dict[str, PyJWKClient] = {}


class OAuthError(Exception):
    pass


@dataclass
class OAuthProfile:
    sub: str
    email: str | None
    email_verified: bool
    name: str | None


def verify_id_token(provider: str, token: str) -> OAuthProfile:
    """Senkron (JWKS ağ çağrısı yapar); FastAPI içinde run_in_threadpool ile çağrılır."""
    s = get_settings()
    jwks_url, issuers = PROVIDERS[provider]
    audiences = s.google_client_ids if provider == "google" else s.apple_client_ids
    if not audiences:
        raise OAuthError(f"{provider} client id yapılandırılmamış")
    try:
        client = _jwks.setdefault(jwks_url, PyJWKClient(jwks_url, cache_keys=True))
        key = client.get_signing_key_from_jwt(token).key
        claims = jwt.decode(token, key, algorithms=["RS256", "ES256"], audience=audiences,
                            options={"require": ["exp", "iat", "sub", "iss"]})
    except jwt.PyJWTError as e:
        raise OAuthError(str(e)) from e
    if claims["iss"] not in issuers:
        raise OAuthError("issuer")
    verified = claims.get("email_verified")
    return OAuthProfile(
        sub=claims["sub"],
        email=claims.get("email"),
        email_verified=verified is True or str(verified).lower() == "true",
        name=claims.get("name"),
    )
