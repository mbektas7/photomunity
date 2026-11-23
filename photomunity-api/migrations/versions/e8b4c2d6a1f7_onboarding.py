"""Kayıt sonrası tanıtım: users.onboarding_done_at (eski hesaplar tamamlanmış sayılır)

Revision ID: e8b4c2d6a1f7
Revises: d7e2a1f3c9b8
"""
import sqlalchemy as sa
from alembic import op

revision = "e8b4c2d6a1f7"
down_revision = "d7e2a1f3c9b8"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("onboarding_done_at", sa.DateTime(timezone=True), nullable=True))
    op.execute("UPDATE users SET onboarding_done_at = now()")


def downgrade() -> None:
    op.drop_column("users", "onboarding_done_at")
