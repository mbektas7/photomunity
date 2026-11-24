"""Jüri üyesinin başvuruya özel notu: jury_scores.note

Revision ID: f1a7c3e9b2d4
Revises: e8b4c2d6a1f7
"""
import sqlalchemy as sa
from alembic import op

revision = "f1a7c3e9b2d4"
down_revision = "e8b4c2d6a1f7"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("jury_scores", sa.Column("note", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("jury_scores", "note")
