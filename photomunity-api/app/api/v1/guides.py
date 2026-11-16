from fastapi import APIRouter, Request

from app.content.guides import BY_SLUG, GUIDES
from app.core.errors import AppError, request_locale

router = APIRouter(prefix="/guides", tags=["guides"])


def _localized(g: dict, locale: str, full: bool) -> dict:
    text = g[locale]
    out = {"slug": g["slug"], "category": g["category"], "calculator": g["calculator"], "planner": g["planner"],
           "title": text["title"], "summary": text["summary"]}
    if full:
        out.update(settings=text["settings"], tips=text["tips"], mistakes=text["mistakes"])
    return out


@router.get("")
async def list_guides(request: Request):
    locale = request_locale(request)
    return [_localized(g, locale, full=False) for g in GUIDES]


@router.get("/{slug}")
async def get_guide(slug: str, request: Request):
    g = BY_SLUG.get(slug)
    if not g:
        raise AppError(404, "not_found")
    return _localized(g, request_locale(request), full=True)
