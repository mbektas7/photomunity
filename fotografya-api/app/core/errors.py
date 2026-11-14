from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.core.messages import translate


class AppError(Exception):
    def __init__(self, status_code: int, code: str, details: list[str] | None = None):
        self.status_code = status_code
        self.code = code
        self.details = details or []


def request_locale(request: Request) -> str:
    lang = request.headers.get("accept-language", "tr").lower()
    return "en" if lang.startswith("en") else "tr"


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def _handle(request: Request, exc: AppError):
        locale = request_locale(request)
        body = {"error": {"code": exc.code, "message": translate(exc.code, locale)}}
        if exc.details:
            body["error"]["details"] = [{"code": c, "message": translate(c, locale)} for c in exc.details]
        return JSONResponse(status_code=exc.status_code, content=body)
