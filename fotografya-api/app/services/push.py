"""Firebase Cloud Messaging HTTP v1 istemcisi. Servis hesabıyla OAuth erişim token'ı üretir ve önbelleğe alır."""
import json
import logging
import time
from pathlib import Path

import httpx
import jwt

from app.core.config import get_settings

log = logging.getLogger("fotografya.push")
SCOPE = "https://www.googleapis.com/auth/firebase.messaging"


class FcmClient:
    def __init__(self, service_account: dict):
        self.sa = service_account
        self._token: str | None = None
        self._expires = 0.0

    async def _access_token(self, client: httpx.AsyncClient) -> str:
        if self._token and time.time() < self._expires - 60:
            return self._token
        now = int(time.time())
        assertion = jwt.encode(
            {"iss": self.sa["client_email"], "scope": SCOPE, "aud": self.sa["token_uri"], "iat": now, "exp": now + 3600},
            self.sa["private_key"],
            algorithm="RS256",
        )
        r = await client.post(self.sa["token_uri"], data={
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": assertion})
        r.raise_for_status()
        body = r.json()
        self._token, self._expires = body["access_token"], time.time() + body.get("expires_in", 3600)
        return self._token

    async def send(self, token: str, title: str, body: str, data: dict[str, str]) -> bool:
        """Gönderildiyse True; token artık geçersizse False döner (çağıran token'ı siler)."""
        url = f"https://fcm.googleapis.com/v1/projects/{self.sa['project_id']}/messages:send"
        message = {
            "message": {
                "token": token,
                "notification": {"title": title, "body": body},
                "data": data,
                "apns": {"payload": {"aps": {"sound": "default"}}},
                "android": {"priority": "high", "notification": {"channel_id": "default"}},
            }
        }
        async with httpx.AsyncClient(timeout=10) as client:
            try:
                headers = {"Authorization": f"Bearer {await self._access_token(client)}"}
                r = await client.post(url, json=message, headers=headers)
            except httpx.HTTPError:
                log.exception("FCM isteği başarısız")
                return True
        if r.status_code == 200:
            return True
        if r.status_code == 404 or "UNREGISTERED" in r.text or "INVALID_ARGUMENT" in r.text:
            return False
        log.warning("FCM %s: %s", r.status_code, r.text[:300])
        return True


_client: FcmClient | None = None
_loaded = False


def get_fcm() -> FcmClient | None:
    global _client, _loaded
    if not _loaded:
        _loaded = True
        s = get_settings()
        raw = s.fcm_service_account_json
        if not raw and s.fcm_service_account_file:
            raw = Path(s.fcm_service_account_file).read_text()
        if raw:
            _client = FcmClient(json.loads(raw))
        else:
            log.info("FCM yapılandırılmamış; push bildirimleri yalnızca log'a yazılır.")
    return _client
