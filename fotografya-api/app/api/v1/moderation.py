import uuid

from fastapi import APIRouter, Depends, Query, Response
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.config import get_settings
from app.core.database import get_db
from app.core.errors import AppError
from app.models import Photo, Report, ReportReason, User
from app.schemas import ReportIn, ReportOut, ResolveReportIn
from app.services.ratelimit import rate_limit

router = APIRouter(tags=["moderation"])


async def require_admin(user: User = Depends(get_current_user)) -> User:
    if not user.is_admin:
        raise AppError(403, "forbidden")
    return user


@router.post("/reports", status_code=201, dependencies=[rate_limit("report", 20, 3600, by="user")])
async def create_report(body: ReportIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    target = await db.get(Photo if body.target_type == "photo" else User, body.target_id)
    if not target:
        raise AppError(404, "not_found")
    if await db.scalar(select(Report.id).where(Report.reporter_id == user.id, Report.target_type == body.target_type,
                                               Report.target_id == body.target_id)):
        raise AppError(409, "already_reported")
    db.add(Report(reporter_id=user.id, target_type=body.target_type, target_id=body.target_id,
                  reason=ReportReason(body.reason), note=body.note))
    await db.flush()

    # Yeterince farklı kişi şikayet ettiyse fotoğraf yönetici incelemesine kadar gizlenir
    if body.target_type == "photo":
        count = await db.scalar(select(func.count(func.distinct(Report.reporter_id))).where(
            Report.target_type == "photo", Report.target_id == body.target_id, Report.status == "open"))
        if count >= get_settings().report_auto_hide_threshold:
            target.hidden = True
    await db.commit()
    return {"status": "received"}


@router.get("/admin/reports", response_model=list[ReportOut])
async def list_reports(status: str = Query("open"), limit: int = Query(100, le=500),
                       _: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    rows = await db.scalars(select(Report).where(Report.status == status).order_by(Report.created_at.desc()).limit(limit))
    return [ReportOut.model_validate(r) for r in rows]


@router.post("/admin/reports/{report_id}/resolve", status_code=204)
async def resolve_report(report_id: uuid.UUID, body: ResolveReportIn, _: User = Depends(require_admin),
                         db: AsyncSession = Depends(get_db)):
    report = await db.get(Report, report_id)
    if not report:
        raise AppError(404, "not_found")
    if body.action == "hide_photo" and report.target_type == "photo":
        photo = await db.get(Photo, report.target_id)
        if photo:
            photo.hidden = True
    elif body.action == "disable_user":
        user_id = report.target_id
        if report.target_type == "photo":
            photo = await db.get(Photo, report.target_id)
            user_id = photo.user_id if photo else None
        target = await db.get(User, user_id) if user_id else None
        if target:
            target.is_active = False
    elif body.action == "dismiss" and report.target_type == "photo":
        # Otomatik gizlenmiş fotoğraf şikayetler reddedilince geri açılır
        photo = await db.get(Photo, report.target_id)
        if photo:
            photo.hidden = False
    # Aynı hedefe ait tüm açık şikayetler birlikte kapanır
    others = await db.scalars(select(Report).where(Report.target_type == report.target_type,
                                                   Report.target_id == report.target_id, Report.status == "open"))
    for r in others:
        r.status, r.resolution = "resolved", body.action
    await db.commit()
    return Response(status_code=204)
