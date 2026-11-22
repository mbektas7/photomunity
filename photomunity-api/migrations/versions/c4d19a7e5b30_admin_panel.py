"""Yönetim paneli: işlem kaydı, duyurular, gizlenen topluluk/yarışma

Revision ID: c4d19a7e5b30
Revises: b81e4f0c2d55
"""
import sqlalchemy as sa
from alembic import op

revision = "c4d19a7e5b30"
down_revision = "b81e4f0c2d55"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("communities", sa.Column("hidden", sa.Boolean(), server_default=sa.false(), nullable=False))
    op.create_index("ix_communities_hidden", "communities", ["hidden"])
    op.add_column("contests", sa.Column("hidden", sa.Boolean(), server_default=sa.false(), nullable=False))
    op.create_index("ix_contests_hidden", "contests", ["hidden"])
    op.add_column("contests", sa.Column("cancelled_at", sa.DateTime(timezone=True), nullable=True))
    op.create_table(
        "admin_actions",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("admin_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("action", sa.String(40), nullable=False),
        sa.Column("kind", sa.String(20), nullable=False),
        sa.Column("target_type", sa.String(20), nullable=True),
        sa.Column("target_id", sa.String(60), nullable=True),
        sa.Column("target_label", sa.String(300), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_admin_actions_admin_id", "admin_actions", ["admin_id"])
    op.create_index("ix_admin_actions_kind", "admin_actions", ["kind"])
    op.create_index("ix_admin_actions_created_at", "admin_actions", ["created_at"])
    op.create_table(
        "announcements",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("admin_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("channels", sa.JSON(), nullable=False),
        sa.Column("title_tr", sa.String(120), nullable=False),
        sa.Column("title_en", sa.String(120), nullable=False),
        sa.Column("body_tr", sa.String(400), nullable=False),
        sa.Column("body_en", sa.String(400), nullable=False),
        sa.Column("link", sa.String(300), nullable=True),
        sa.Column("audience", sa.JSON(), nullable=False),
        sa.Column("recipient_count", sa.Integer(), nullable=False),
        sa.Column("banner_until", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_announcements_banner_until", "announcements", ["banner_until"])
    op.create_index("ix_announcements_created_at", "announcements", ["created_at"])
    # Panelin sahibi yönetici olarak başlar
    op.execute("UPDATE users SET is_admin = true WHERE username = 'mbektas7'")


def downgrade() -> None:
    op.drop_table("announcements")
    op.drop_table("admin_actions")
    op.drop_column("contests", "cancelled_at")
    op.drop_index("ix_contests_hidden", "contests")
    op.drop_column("contests", "hidden")
    op.drop_index("ix_communities_hidden", "communities")
    op.drop_column("communities", "hidden")
