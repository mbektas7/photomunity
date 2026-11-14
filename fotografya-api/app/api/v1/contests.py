import hashlib
import uuid
from datetime import timedelta

from fastapi import APIRouter, BackgroundTasks, Depends, Header, Query, Request, Response
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.deps import get_current_user, get_optional_user
from app.core.config import get_settings
from app.core.database import get_db
from app.core.errors import AppError, request_locale
from app.core.security import hash_token, new_opaque_token, utcnow
from app.models import (
    Community, CommunityPost, Contest, ContestEntry, ContestJudge, ContestPrize, JuryScore, Photo, PhotoStatus,
    PublicVote, PublicVoter, User, VoteCode,
)
from app.schemas import (
    ContestCard, ContestIn, ContestOut, ContestSummary, ContestUpdate, DisqualifyIn, EntryIn, EntryOut, ImageVariant,
    JudgeIn, JudgeOut, JudgeUpdate, PrizeOut, ResultRow, ScoreIn, StarsIn, TokenIn, UserCard, VoteCodeIn, VoteVerifyIn,
)
from app.services import storage
from app.services.contests import (
    community_role, compute_results, contest_status, entry_counts, finalize_if_due, is_admin_role, notify_members,
    validate_dates,
)
from app.services.email import send_template
from app.services.notifications import deliver, notify
from app.services.ratelimit import client_ip, rate_limit
from app.services.voting import (
    hash_code, hash_ip, is_disposable, new_code, normalize_email, read_voter_token, verify_turnstile, voter_token,
)

router = APIRouter(tags=["contests"])


# ---------------------------------------------------------------- yardımcılar
async def _contest(db: AsyncSession, contest_id: uuid.UUID) -> Contest:
    c = await db.scalar(select(Contest).where(Contest.id == contest_id).options(selectinload(Contest.community)))
    if not c:
        raise AppError(404, "not_found")
    return c


async def _is_admin(db: AsyncSession, c: Contest, user: User | None) -> bool:
    return bool(user) and is_admin_role(await community_role(db, c.community_id, user.id))


async def _require_admin(db: AsyncSession, c: Contest, user: User) -> None:
    if not await _is_admin(db, c, user):
        raise AppError(403, "forbidden")


async def _judge(db: AsyncSession, c: Contest, user: User | None) -> ContestJudge | None:
    if not user:
        return None
    return await db.scalar(select(ContestJudge).where(ContestJudge.contest_id == c.id, ContestJudge.user_id == user.id))


async def _finalize(db: AsyncSession, c: Contest, background: BackgroundTasks | None = None) -> None:
    created = await finalize_if_due(db, c)
    if c.finalized_at is not None and created is not None:
        await db.commit()
        if created and background is not None:
            background.add_task(deliver, [n.id for n in created])


def _images(photo: Photo) -> dict[str, ImageVariant]:
    return {k: ImageVariant(url=storage.public_url(v["key"]), width=v["width"], height=v["height"])
            for k, v in (photo.variants or {}).items()}


def entry_out(e: ContestEntry, reveal: bool, **extra) -> EntryOut:
    return EntryOut(id=e.id, photo_id=e.photo_id, title=e.photo.title, images=_images(e.photo),
                    user=UserCard.model_validate(e.user) if reveal else None, disqualified=e.disqualified, **extra)


def _entries_query(contest_id: uuid.UUID, include_disqualified: bool = False):
    q = (select(ContestEntry).where(ContestEntry.contest_id == contest_id)
         .options(selectinload(ContestEntry.photo), selectinload(ContestEntry.user)))
    return q if include_disqualified else q.where(ContestEntry.disqualified.is_(False))


def _shuffle(entries: list[ContestEntry], seed: str) -> list[ContestEntry]:
    """Her seçmene sabit ama farklı bir sıra: listenin başındaki karelerin avantajını ortadan kaldırır."""
    return sorted(entries, key=lambda e: hashlib.sha256(f"{seed}:{e.id}".encode()).hexdigest())


async def contest_cards(db: AsyncSession, contests: list[Contest], viewer: User | None) -> list[ContestCard]:
    from app.api.v1.communities import community_cards

    communities = {c.community_id: None for c in contests}
    rows = list(await db.scalars(select(Community).where(Community.id.in_(list(communities)))))
    comm_cards = {card.id: card for card in await community_cards(db, rows, viewer)}
    counts = await entry_counts(db, [c.id for c in contests])
    return [ContestCard(id=c.id, title=c.title, status=contest_status(c), judging_mode=c.judging_mode,
                        submission_deadline=c.submission_deadline, voting_end=c.voting_end, results_at=c.results_at,
                        entry_count=counts.get(c.id, 0), community=comm_cards[c.community_id]) for c in contests]


async def contest_out(db: AsyncSession, c: Contest, viewer: User | None) -> ContestOut:
    [card] = await contest_cards(db, [c], viewer)
    prizes = await db.scalars(select(ContestPrize).where(ContestPrize.contest_id == c.id).order_by(ContestPrize.rank))
    judge = await _judge(db, c, viewer)
    role = "admin" if await _is_admin(db, c, viewer) else ("judge" if judge else None)
    mine = None
    if viewer:
        e = await db.scalar(_entries_query(c.id, include_disqualified=True).where(ContestEntry.user_id == viewer.id))
        mine = entry_out(e, reveal=True) if e else None
    return ContestOut(**card.model_dump(), description=c.description, rules=c.rules, anonymous=c.anonymous,
                      min_votes=c.min_votes, prizes=[PrizeOut(rank=p.rank, title=p.title) for p in prizes],
                      published_at=c.published_at, my_role=role, is_judge=judge is not None, my_entry=mine,
                      share_url=f"{get_settings().frontend_url}/contests/{c.id}")


async def _replace_prizes(db: AsyncSession, contest_id: uuid.UUID, prizes) -> None:
    await db.execute(delete(ContestPrize).where(ContestPrize.contest_id == contest_id))
    seen = set()
    for p in prizes:
        if p.rank not in seen:
            seen.add(p.rank)
            db.add(ContestPrize(contest_id=contest_id, rank=p.rank, title=p.title.strip()))


# ---------------------------------------------------------------- yarışma
@router.post("/communities/{slug}/contests", response_model=ContestOut, status_code=201)
async def create_contest(slug: str, body: ContestIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    community = await db.scalar(select(Community).where(Community.slug == slug))
    if not community:
        raise AppError(404, "not_found")
    if not is_admin_role(await community_role(db, community.id, user.id)):
        raise AppError(403, "forbidden")
    if not validate_dates(body.submission_deadline, body.voting_end, body.results_at, require_future=True):
        raise AppError(422, "invalid_dates")
    c = Contest(id=uuid.uuid4(), community_id=community.id, created_by=user.id, results=[],
                **body.model_dump(exclude={"prizes"}))
    db.add(c)
    await db.flush()
    await _replace_prizes(db, c.id, body.prizes)
    await db.commit()
    return await contest_out(db, await _contest(db, c.id), user)


@router.patch("/contests/{contest_id}", response_model=ContestOut)
async def update_contest(contest_id: uuid.UUID, body: ContestUpdate, user: User = Depends(get_current_user),
                         db: AsyncSession = Depends(get_db)):
    c = await _contest(db, contest_id)
    await _require_admin(db, c, user)
    data = body.model_dump(exclude_unset=True, exclude={"prizes"})
    if c.published_at is not None and set(data) - {"title", "description", "rules"}:
        # Yayından sonra tarih, değerlendirme yöntemi gibi kurallar değişmez: katılımcıların güveni için
        raise AppError(409, "contest_locked")
    for k, v in data.items():
        setattr(c, k, v)
    if not validate_dates(c.submission_deadline, c.voting_end, c.results_at, require_future=False):
        raise AppError(422, "invalid_dates")
    if body.prizes is not None:
        if contest_status(c) in ("closed", "finished"):
            raise AppError(409, "contest_locked")
        await _replace_prizes(db, c.id, body.prizes)
    await db.commit()
    return await contest_out(db, await _contest(db, c.id), user)


@router.post("/contests/{contest_id}/publish", response_model=ContestOut)
async def publish_contest(contest_id: uuid.UUID, background: BackgroundTasks, user: User = Depends(get_current_user),
                          db: AsyncSession = Depends(get_db)):
    c = await _contest(db, contest_id)
    await _require_admin(db, c, user)
    if c.published_at is not None:
        raise AppError(409, "invalid_state")
    if not validate_dates(c.submission_deadline, c.voting_end, c.results_at, require_future=True):
        raise AppError(422, "invalid_dates")
    if c.judging_mode == "jury" and not await db.scalar(select(func.count()).select_from(ContestJudge).where(ContestJudge.contest_id == c.id)):
        raise AppError(422, "judges_required")
    c.published_at = utcnow()
    db.add(CommunityPost(community_id=c.community_id, author_id=user.id, kind="contest", title=c.title, contest_id=c.id))
    created = await notify_members(db, c, c.community.name, "contest_new", actor_id=user.id)
    await db.commit()
    background.add_task(deliver, [n.id for n in created])
    return await contest_out(db, c, user)


@router.delete("/contests/{contest_id}", status_code=204)
async def delete_contest(contest_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    c = await _contest(db, contest_id)
    await _require_admin(db, c, user)
    if c.published_at is not None:
        raise AppError(409, "contest_locked")
    await db.delete(c)
    await db.commit()
    return Response(status_code=204)


@router.get("/contests/{contest_id}", response_model=ContestOut)
async def get_contest(contest_id: uuid.UUID, background: BackgroundTasks, viewer: User | None = Depends(get_optional_user),
                      db: AsyncSession = Depends(get_db)):
    c = await _contest(db, contest_id)
    if c.published_at is None and not await _is_admin(db, c, viewer):
        raise AppError(404, "not_found")
    await _finalize(db, c, background)
    return await contest_out(db, c, viewer)


@router.get("/communities/{slug}/contests", response_model=list[ContestCard])
async def community_contests(slug: str, viewer: User | None = Depends(get_optional_user), db: AsyncSession = Depends(get_db)):
    community = await db.scalar(select(Community).where(Community.slug == slug))
    if not community:
        raise AppError(404, "not_found")
    q = select(Contest).where(Contest.community_id == community.id)
    if not (viewer and is_admin_role(await community_role(db, community.id, viewer.id))):
        q = q.where(Contest.published_at.is_not(None))
    return await contest_cards(db, list(await db.scalars(q.order_by(Contest.submission_deadline.desc()))), viewer)


@router.get("/contests", response_model=list[ContestCard])
async def discover_contests(status: str = Query("open", pattern="^(open|judging|finished)$"), limit: int = Query(30, le=100),
                            viewer: User | None = Depends(get_optional_user), db: AsyncSession = Depends(get_db)):
    rows = list(await db.scalars(select(Contest).where(Contest.published_at.is_not(None))
                                 .order_by(Contest.submission_deadline.desc()).limit(500)))
    picked = [c for c in rows if contest_status(c) == status][:limit]
    if status != "finished":
        picked.sort(key=lambda c: c.submission_deadline if status == "open" else c.voting_end)
    return await contest_cards(db, picked, viewer)


# ---------------------------------------------------------------- jüri yönetimi
async def _judge_outs(db: AsyncSession, c: Contest) -> list[JudgeOut]:
    judges = list(await db.scalars(select(ContestJudge).where(ContestJudge.contest_id == c.id)
                                   .options(selectinload(ContestJudge.user)).order_by(ContestJudge.weight.desc())))
    counts = dict((await db.execute(select(JuryScore.judge_id, func.count()).where(
        JuryScore.judge_id.in_([j.id for j in judges])).group_by(JuryScore.judge_id))).all()) if judges else {}
    return [JudgeOut(id=j.id, user=UserCard.model_validate(j.user) if j.user else None, email=j.email if not j.user else None,
                     weight=j.weight, pending=j.user_id is None, scored=counts.get(j.id, 0)) for j in judges]


@router.get("/contests/{contest_id}/judges", response_model=list[JudgeOut])
async def list_judges(contest_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    c = await _contest(db, contest_id)
    await _require_admin(db, c, user)
    return await _judge_outs(db, c)


@router.post("/contests/{contest_id}/judges", response_model=list[JudgeOut], status_code=201)
async def add_judge(contest_id: uuid.UUID, body: JudgeIn, request: Request, background: BackgroundTasks,
                    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    c = await _contest(db, contest_id)
    await _require_admin(db, c, user)
    if c.judging_mode != "jury" or contest_status(c) in ("closed", "finished"):
        raise AppError(409, "contest_locked")
    if not body.username and not body.email:
        raise AppError(422, "invalid_state")
    target = None
    if body.username:
        target = await db.scalar(select(User).where(User.username == body.username.lower(), User.is_active.is_(True)))
        if not target:
            raise AppError(404, "not_found")
    elif body.email:
        target = await db.scalar(select(User).where(User.email == body.email.lower(), User.is_active.is_(True)))

    if target:
        existing = await db.scalar(select(ContestJudge).where(ContestJudge.contest_id == c.id, ContestJudge.user_id == target.id))
        if existing:
            existing.weight = body.weight
            await db.commit()
        else:
            db.add(ContestJudge(contest_id=c.id, user_id=target.id, weight=body.weight))
            n = await notify(db, user_id=target.id, type="contest_judge_invite", actor_id=user.id,
                             data={"contest_id": str(c.id), "contest": c.title})
            await db.commit()
            if n:
                background.add_task(deliver, [n.id])
    else:
        token = new_opaque_token()
        db.add(ContestJudge(contest_id=c.id, email=body.email.lower(), token_hash=hash_token(token), weight=body.weight))
        await db.commit()
        link = f"{get_settings().frontend_url}/invite/judge?token={token}"
        background.add_task(send_template, body.email.lower(), "judge_invite", request_locale(request), link)
    return await _judge_outs(db, c)


@router.patch("/contests/{contest_id}/judges/{judge_id}", response_model=list[JudgeOut])
async def update_judge(contest_id: uuid.UUID, judge_id: uuid.UUID, body: JudgeUpdate, user: User = Depends(get_current_user),
                       db: AsyncSession = Depends(get_db)):
    c = await _contest(db, contest_id)
    await _require_admin(db, c, user)
    if contest_status(c) in ("closed", "finished"):
        raise AppError(409, "contest_locked")
    j = await db.get(ContestJudge, judge_id)
    if not j or j.contest_id != c.id:
        raise AppError(404, "not_found")
    j.weight = body.weight
    await db.commit()
    return await _judge_outs(db, c)


@router.delete("/contests/{contest_id}/judges/{judge_id}", status_code=204)
async def remove_judge(contest_id: uuid.UUID, judge_id: uuid.UUID, user: User = Depends(get_current_user),
                       db: AsyncSession = Depends(get_db)):
    c = await _contest(db, contest_id)
    await _require_admin(db, c, user)
    if contest_status(c) in ("closed", "finished"):
        raise AppError(409, "contest_locked")
    j = await db.get(ContestJudge, judge_id)
    if j and j.contest_id == c.id:
        await db.delete(j)
        await db.commit()
    return Response(status_code=204)


@router.post("/contest-judge-invites/accept", response_model=ContestOut)
async def accept_judge_invite(body: TokenIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    j = await db.scalar(select(ContestJudge).where(ContestJudge.token_hash == hash_token(body.token)))
    if not j:
        raise AppError(400, "invalid_link")
    if (j.email or "").lower() != user.email.lower():
        raise AppError(403, "invite_email_mismatch")
    c = await _contest(db, j.contest_id)
    if await _judge(db, c, user):
        await db.delete(j)  # zaten jüri; davet satırı fazlalık
    else:
        j.user_id, j.token_hash, j.email = user.id, None, None
    await db.commit()
    return await contest_out(db, c, user)


# ---------------------------------------------------------------- katılım
@router.post("/contests/{contest_id}/entries", response_model=EntryOut, status_code=201)
async def enter_contest(contest_id: uuid.UUID, body: EntryIn, user: User = Depends(get_current_user),
                        db: AsyncSession = Depends(get_db)):
    c = await _contest(db, contest_id)
    if contest_status(c) != "open":
        raise AppError(409, "contest_not_open")
    photo = await db.get(Photo, body.photo_id)
    if not photo or photo.user_id != user.id or photo.status != PhotoStatus.published or photo.hidden:
        raise AppError(422, "photo_not_eligible")
    if await db.scalar(select(ContestEntry.id).where(ContestEntry.contest_id == c.id, ContestEntry.user_id == user.id)):
        raise AppError(409, "already_entered")
    entry = ContestEntry(contest_id=c.id, user_id=user.id, photo_id=photo.id)
    db.add(entry)
    await db.commit()
    e = await db.scalar(_entries_query(c.id).where(ContestEntry.id == entry.id))
    return entry_out(e, reveal=True)


@router.delete("/contests/{contest_id}/entries/me", status_code=204)
async def withdraw_entry(contest_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    c = await _contest(db, contest_id)
    if contest_status(c) != "open":
        raise AppError(409, "contest_not_open")
    await db.execute(delete(ContestEntry).where(ContestEntry.contest_id == c.id, ContestEntry.user_id == user.id))
    await db.commit()
    return Response(status_code=204)


@router.post("/contests/{contest_id}/entries/{entry_id}/disqualify", status_code=204)
async def disqualify(contest_id: uuid.UUID, entry_id: uuid.UUID, body: DisqualifyIn, background: BackgroundTasks,
                     user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    c = await _contest(db, contest_id)
    await _require_admin(db, c, user)
    if contest_status(c) == "finished":
        raise AppError(409, "contest_locked")
    e = await db.get(ContestEntry, entry_id)
    if not e or e.contest_id != c.id:
        raise AppError(404, "not_found")
    e.disqualified, e.disqualify_reason = True, body.reason
    n = await notify(db, user_id=e.user_id, type="contest_entry_disqualified", photo_id=e.photo_id,
                     data={"contest_id": str(c.id), "contest": c.title})
    await db.commit()
    if n:
        background.add_task(deliver, [n.id])
    return Response(status_code=204)


# ---------------------------------------------------------------- seçmen kimliği
async def _voter(db: AsyncSession, c: Contest, user: User | None, token: str | None, create: bool,
                 request: Request | None = None) -> PublicVoter | None:
    """Giriş yapmış kullanıcı e-postasıyla, misafir ise doğrulanmış kod token'ıyla tanınır. Bir e-posta = bir seçmen."""
    if user:
        email = normalize_email(user.email)
        voter = await db.scalar(select(PublicVoter).where(PublicVoter.contest_id == c.id, PublicVoter.email_normalized == email))
        if not voter and create:
            voter = PublicVoter(contest_id=c.id, email_normalized=email, user_id=user.id,
                                ip_hash=hash_ip(client_ip(request)) if request else None)
            db.add(voter)
            await db.flush()
        return voter
    if token:
        voter_id = read_voter_token(token, c.id)
        return await db.get(PublicVoter, voter_id) if voter_id else None
    return None


@router.get("/contests/{contest_id}/entries", response_model=list[EntryOut])
async def list_entries(contest_id: uuid.UUID, request: Request, background: BackgroundTasks,
                       view: str | None = Query(None, pattern="^admin$"),
                       x_voter_token: str | None = Header(default=None),
                       viewer: User | None = Depends(get_optional_user), db: AsyncSession = Depends(get_db)):
    c = await _contest(db, contest_id)
    status = contest_status(c)
    admin = await _is_admin(db, c, viewer)
    if status == "draft" and not admin:
        raise AppError(404, "not_found")

    if status == "finished":
        await _finalize(db, c, background)
        rows = {r["entry_id"]: r for r in c.results}
        entries = list(await db.scalars(_entries_query(c.id)))
        ordered = sorted(entries, key=lambda e: (rows.get(str(e.id), {}).get("rank") or 10**6, e.created_at))
        return [entry_out(e, reveal=True, rank=rows.get(str(e.id), {}).get("rank"), score=rows.get(str(e.id), {}).get("score"),
                          prize=rows.get(str(e.id), {}).get("prize"), mine=viewer is not None and e.user_id == viewer.id)
                for e in ordered]

    # Yönetim listesi açıkça istenir (?view=admin); yönetici oylama sayfasında herkes gibi seçmen görünümünü alır
    if admin and (view == "admin" or status in ("draft", "open")):
        entries = list(await db.scalars(_entries_query(c.id, include_disqualified=True).order_by(ContestEntry.created_at)))
        return [entry_out(e, reveal=True) for e in entries]

    if status == "open":
        return []  # katılım sürerken kareler yalnızca yöneticilere görünür

    entries = [e for e in await db.scalars(_entries_query(c.id))]
    reveal = not c.anonymous
    if c.judging_mode == "jury":
        judge = await _judge(db, c, viewer)
        if not judge:
            return []
        mine = dict((await db.execute(select(JuryScore.entry_id, JuryScore.score).where(JuryScore.judge_id == judge.id))).all())
        return [entry_out(e, reveal=reveal, my_score=mine.get(e.id), mine=e.user_id == judge.user_id)
                for e in _shuffle(entries, str(judge.id))]

    voter = await _voter(db, c, viewer, x_voter_token, create=False)
    stars = {}
    if voter:
        stars = dict((await db.execute(select(PublicVote.entry_id, PublicVote.stars).where(PublicVote.voter_id == voter.id))).all())
    seed = str(voter.id) if voter else (str(viewer.id) if viewer else hash_ip(client_ip(request)))
    def is_mine(e: ContestEntry) -> bool:
        if viewer is not None:
            return e.user_id == viewer.id
        return voter is not None and normalize_email(e.user.email) == voter.email_normalized

    return [entry_out(e, reveal=reveal, my_stars=stars.get(e.id), mine=is_mine(e)) for e in _shuffle(entries, seed)]


# ---------------------------------------------------------------- jüri puanlaması
@router.put("/contests/{contest_id}/jury/scores/{entry_id}", status_code=204)
async def score_entry(contest_id: uuid.UUID, entry_id: uuid.UUID, body: ScoreIn, user: User = Depends(get_current_user),
                      db: AsyncSession = Depends(get_db)):
    c = await _contest(db, contest_id)
    judge = await _judge(db, c, user)
    if not judge:
        raise AppError(403, "not_a_judge")
    if contest_status(c) != "judging":
        raise AppError(409, "contest_not_judging")
    e = await db.get(ContestEntry, entry_id)
    if not e or e.contest_id != c.id or e.disqualified:
        raise AppError(404, "not_found")
    if e.user_id == user.id:
        raise AppError(403, "cannot_vote_own")
    existing = await db.get(JuryScore, (e.id, judge.id))
    if existing:
        existing.score = body.score
    else:
        db.add(JuryScore(entry_id=e.id, judge_id=judge.id, score=body.score))
    await db.commit()
    return Response(status_code=204)


# ---------------------------------------------------------------- halk oylaması
def _require_public_judging(c: Contest) -> None:
    if c.judging_mode != "public":
        raise AppError(409, "voting_not_public")
    if contest_status(c) != "judging":
        raise AppError(409, "contest_not_judging")


@router.post("/contests/{contest_id}/vote/request-code", status_code=202, dependencies=[rate_limit("vote_code_ip", 10, 3600)])
async def request_vote_code(contest_id: uuid.UUID, body: VoteCodeIn, request: Request, background: BackgroundTasks,
                            db: AsyncSession = Depends(get_db)):
    c = await _contest(db, contest_id)
    _require_public_judging(c)
    if not await verify_turnstile(body.turnstile_token, client_ip(request)):
        raise AppError(400, "verification_failed")
    if is_disposable(body.email):
        raise AppError(422, "disposable_email")
    email = normalize_email(body.email)
    recent = await db.scalar(select(func.count()).select_from(VoteCode).where(
        VoteCode.contest_id == c.id, VoteCode.email_normalized == email, VoteCode.expires_at > utcnow() - timedelta(minutes=10)))
    if recent >= 3:
        raise AppError(429, "too_many_requests")
    code = new_code()
    db.add(VoteCode(contest_id=c.id, email_normalized=email, code_hash=hash_code(c.id, email, code),
                    expires_at=utcnow() + timedelta(minutes=get_settings().vote_code_minutes)))
    await db.commit()
    # Kod kullanıcının yazdığı adrese gider; normalleştirilmiş adres yalnızca tekilleştirme anahtarıdır
    background.add_task(send_template, body.email, "vote_code", request_locale(request), None, code)
    return {"status": "sent"}


@router.post("/contests/{contest_id}/vote/verify", dependencies=[rate_limit("vote_verify_ip", 30, 3600)])
async def verify_vote_code(contest_id: uuid.UUID, body: VoteVerifyIn, request: Request, db: AsyncSession = Depends(get_db)):
    c = await _contest(db, contest_id)
    _require_public_judging(c)
    email = normalize_email(body.email)
    row = await db.scalar(select(VoteCode).where(VoteCode.contest_id == c.id, VoteCode.email_normalized == email,
                                                 VoteCode.used_at.is_(None), VoteCode.expires_at > utcnow())
                          .order_by(VoteCode.expires_at.desc()))
    if not row or row.attempts >= 5:
        raise AppError(400, "invalid_code")
    if row.code_hash != hash_code(c.id, email, body.code):
        row.attempts += 1
        await db.commit()
        raise AppError(400, "invalid_code")
    row.used_at = utcnow()
    voter = await db.scalar(select(PublicVoter).where(PublicVoter.contest_id == c.id, PublicVoter.email_normalized == email))
    if not voter:
        voter = PublicVoter(contest_id=c.id, email_normalized=email, ip_hash=hash_ip(client_ip(request)))
        db.add(voter)
    await db.commit()
    return {"voter_token": voter_token(voter.id, c.id, c.voting_end), "expires_at": c.voting_end}


@router.post("/contests/{contest_id}/votes", status_code=204, dependencies=[rate_limit("vote", 600, 3600)])
async def vote(contest_id: uuid.UUID, body: StarsIn, request: Request, x_voter_token: str | None = Header(default=None),
               viewer: User | None = Depends(get_optional_user), db: AsyncSession = Depends(get_db)):
    c = await _contest(db, contest_id)
    _require_public_judging(c)
    voter = await _voter(db, c, viewer, x_voter_token, create=True, request=request)
    if not voter:
        raise AppError(401, "voter_required")
    entry = await db.scalar(select(ContestEntry).where(ContestEntry.id == body.entry_id).options(selectinload(ContestEntry.user)))
    if not entry or entry.contest_id != c.id or entry.disqualified:
        raise AppError(404, "not_found")
    if entry.user_id == voter.user_id or normalize_email(entry.user.email) == voter.email_normalized:
        raise AppError(403, "cannot_vote_own")
    existing = await db.get(PublicVote, (voter.id, entry.id))
    if existing:
        existing.stars = body.stars
    else:
        db.add(PublicVote(voter_id=voter.id, entry_id=entry.id, stars=body.stars))
    await db.commit()
    return Response(status_code=204)


# ---------------------------------------------------------------- sonuçlar ve yönetici özeti
@router.get("/contests/{contest_id}/results", response_model=list[ResultRow])
async def results(contest_id: uuid.UUID, background: BackgroundTasks, viewer: User | None = Depends(get_optional_user),
                  db: AsyncSession = Depends(get_db)):
    c = await _contest(db, contest_id)
    status = contest_status(c)
    if status == "finished":
        await _finalize(db, c, background)
        rows, reveal = c.results, True
    elif status in ("judging", "closed") and await _is_admin(db, c, viewer):
        rows, reveal = await compute_results(db, c), True  # yöneticiye ara sonuç önizlemesi
    else:
        raise AppError(403, "results_not_ready")
    entries = {str(e.id): e for e in await db.scalars(_entries_query(c.id))}
    return [ResultRow(rank=r["rank"], score=r["score"], count=r["count"], prize=r["prize"],
                      entry=entry_out(entries[r["entry_id"]], reveal=reveal))
            for r in rows if r["entry_id"] in entries]


@router.get("/contests/{contest_id}/summary", response_model=ContestSummary)
async def summary(contest_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    c = await _contest(db, contest_id)
    await _require_admin(db, c, user)
    total = await db.scalar(select(func.count()).select_from(ContestEntry).where(ContestEntry.contest_id == c.id))
    dq = await db.scalar(select(func.count()).select_from(ContestEntry).where(ContestEntry.contest_id == c.id, ContestEntry.disqualified.is_(True)))
    voters = await db.scalar(select(func.count()).select_from(PublicVoter).where(PublicVoter.contest_id == c.id))
    votes = await db.scalar(select(func.count()).select_from(PublicVote).join(PublicVoter, PublicVoter.id == PublicVote.voter_id)
                            .where(PublicVoter.contest_id == c.id))
    per_ip = select(PublicVoter.ip_hash, func.count().label("n")).where(
        PublicVoter.contest_id == c.id, PublicVoter.ip_hash.is_not(None)).group_by(PublicVoter.ip_hash).subquery()
    suspicious = await db.scalar(select(func.count()).select_from(per_ip).where(per_ip.c.n >= get_settings().suspicious_voters_per_ip))
    return ContestSummary(entries=total or 0, disqualified=dq or 0, voters=voters or 0, votes=votes or 0,
                          suspicious_ips=suspicious or 0, judges=await _judge_outs(db, c))
