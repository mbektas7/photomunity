"""Yarışma kuralları: durum, puanlama, sonuçlandırma."""
import uuid
from collections import defaultdict
from datetime import datetime

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import as_aware, utcnow
from app.models import (
    CommunityMember, CommunityRole, Contest, ContestEntry, ContestJudge, ContestPrize, JuryScore, Notification, PublicVote,
)
from app.services.notifications import notify


def contest_status(c: Contest, now: datetime | None = None) -> str:
    """draft → open (katılım) → judging (oylama/jüri) → closed (sonuç bekleniyor) → finished."""
    now = now or utcnow()
    if c.published_at is None:
        return "draft"
    if now < as_aware(c.submission_deadline):
        return "open"
    if now < as_aware(c.voting_end):
        return "judging"
    if now < as_aware(c.results_at):
        return "closed"
    return "finished"


def validate_dates(deadline: datetime, voting_end: datetime, results_at: datetime, require_future: bool) -> bool:
    deadline, voting_end, results_at = as_aware(deadline), as_aware(voting_end), as_aware(results_at)
    if require_future and deadline <= utcnow():
        return False
    return deadline < voting_end <= results_at


async def community_role(db: AsyncSession, community_id: uuid.UUID, user_id: uuid.UUID | None) -> CommunityRole | None:
    if user_id is None:
        return None
    return await db.scalar(select(CommunityMember.role).where(
        CommunityMember.community_id == community_id, CommunityMember.user_id == user_id))


def is_admin_role(role: CommunityRole | None) -> bool:
    return role in (CommunityRole.owner, CommunityRole.admin)


async def compute_results(db: AsyncSession, contest: Contest) -> list[dict]:
    """Sıralı sonuç listesi. Puanı olmayan katılımlar sona, sırasız olarak eklenir."""
    entries = list(await db.scalars(select(ContestEntry).where(
        ContestEntry.contest_id == contest.id, ContestEntry.disqualified.is_(False)).order_by(ContestEntry.created_at)))
    prizes = {p.rank: p.title for p in await db.scalars(select(ContestPrize).where(ContestPrize.contest_id == contest.id))}
    rows: list[dict] = []

    if contest.judging_mode == "jury":
        judges = {j.id: j for j in await db.scalars(select(ContestJudge).where(
            ContestJudge.contest_id == contest.id, ContestJudge.user_id.is_not(None)))}
        chair = max(judges.values(), key=lambda j: (j.weight, -as_aware(j.created_at).timestamp()), default=None)
        scores: dict[uuid.UUID, dict[uuid.UUID, int]] = defaultdict(dict)
        if entries:
            for s in await db.scalars(select(JuryScore).where(JuryScore.entry_id.in_([e.id for e in entries]))):
                if s.judge_id in judges:
                    scores[s.entry_id][s.judge_id] = s.score
        for e in entries:
            given = scores.get(e.id, {})
            # Ağırlıklı ortalama: Σ(ağırlık × puan) / Σ(puan veren üyelerin ağırlığı)
            den = sum(judges[j].weight for j in given)
            score = sum(judges[j].weight * s for j, s in given.items()) / den if den else None
            tiebreak = given.get(chair.id, 0) if chair else 0  # eşitlikte en yüksek ağırlıklı üyenin (başkan) puanı
            rows.append({"entry": e, "score": score, "count": len(given), "tiebreak": tiebreak})
    else:
        stats: dict[uuid.UUID, list[int]] = defaultdict(list)
        if entries:
            for v in await db.scalars(select(PublicVote).where(PublicVote.entry_id.in_([e.id for e in entries]))):
                stats[v.entry_id].append(v.stars)
        all_votes = [s for votes in stats.values() for s in votes]
        global_mean = sum(all_votes) / len(all_votes) if all_votes else 0.0
        m = contest.min_votes
        for e in entries:
            votes = stats.get(e.id, [])
            v = len(votes)
            # Bayes ortalaması: az oy almış bir karenin 5 yıldızla zirveye oturmasını engeller
            score = (v / (v + m)) * (sum(votes) / v) + (m / (v + m)) * global_mean if v else None
            rows.append({"entry": e, "score": score, "count": v, "tiebreak": v})

    scored = sorted((r for r in rows if r["score"] is not None),
                    key=lambda r: (-r["score"], -r["tiebreak"], as_aware(r["entry"].created_at)))
    unscored = [r for r in rows if r["score"] is None]
    out = []
    for i, r in enumerate(scored, start=1):
        out.append({"entry_id": str(r["entry"].id), "rank": i, "score": round(r["score"], 3), "count": r["count"],
                    "prize": prizes.get(i)})
    for r in unscored:
        out.append({"entry_id": str(r["entry"].id), "rank": None, "score": None, "count": 0, "prize": None})
    return out


async def finalize_if_due(db: AsyncSession, contest: Contest) -> list[Notification]:
    """Sonuç ilan tarihi geçtiyse sonuçları dondurur ve katılımcılara bildirir. Commit çağırana aittir."""
    if contest.finalized_at is not None or contest_status(contest) != "finished":
        return []
    contest.results = await compute_results(db, contest)
    contest.finalized_at = utcnow()
    ranks = {r["entry_id"]: r["rank"] for r in contest.results}
    created = []
    for e in await db.scalars(select(ContestEntry).where(ContestEntry.contest_id == contest.id, ContestEntry.disqualified.is_(False))):
        rank = ranks.get(str(e.id))
        won = rank is not None and rank <= 3
        n = await notify(db, user_id=e.user_id, type="contest_won" if won else "contest_results", photo_id=e.photo_id,
                         data={"contest_id": str(contest.id), "contest": contest.title, **({"rank": rank} if won else {})})
        if n:
            created.append(n)
    return created


async def notify_members(db: AsyncSession, contest: Contest, community_name: str, type_: str, exclude_entrants: bool = False,
                         actor_id: uuid.UUID | None = None) -> list[Notification]:
    q = select(CommunityMember.user_id).where(CommunityMember.community_id == contest.community_id)
    if exclude_entrants:
        entered = select(ContestEntry.user_id).where(ContestEntry.contest_id == contest.id)
        q = q.where(CommunityMember.user_id.not_in(entered))
    created = []
    for user_id in await db.scalars(q):
        n = await notify(db, user_id=user_id, type=type_, actor_id=actor_id,
                         data={"contest_id": str(contest.id), "contest": contest.title, "community": community_name})
        if n:
            created.append(n)
    return created


async def entry_counts(db: AsyncSession, contest_ids: list[uuid.UUID]) -> dict[uuid.UUID, int]:
    if not contest_ids:
        return {}
    rows = await db.execute(select(ContestEntry.contest_id, func.count()).where(
        ContestEntry.contest_id.in_(contest_ids), ContestEntry.disqualified.is_(False)).group_by(ContestEntry.contest_id))
    return dict(rows.all())
