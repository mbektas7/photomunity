"""Fotoğraf yorumları ve yorum ayarı; mesajlarda cevap, görsel, GIF ve tepki

Revision ID: d7e2a1f3c9b8
Revises: c4d19a7e5b30
"""
import sqlalchemy as sa
from alembic import op

revision = "d7e2a1f3c9b8"
down_revision = "c4d19a7e5b30"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("photos", sa.Column("comment_policy", sa.String(10), server_default="everyone", nullable=False))
    op.create_table(
        "comments",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("photo_id", sa.Uuid(), sa.ForeignKey("photos.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("parent_id", sa.Uuid(), sa.ForeignKey("comments.id", ondelete="CASCADE"), nullable=True),
        sa.Column("quote_id", sa.Uuid(), sa.ForeignKey("comments.id", ondelete="SET NULL"), nullable=True),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_comments_photo_id", "comments", ["photo_id"])
    op.create_index("ix_comments_user_id", "comments", ["user_id"])
    op.create_index("ix_comments_parent_id", "comments", ["parent_id"])
    op.create_index("ix_comments_created_at", "comments", ["created_at"])

    op.add_column("messages", sa.Column("reply_to_id", sa.Uuid(), sa.ForeignKey("messages.id", ondelete="SET NULL"), nullable=True))
    op.add_column("messages", sa.Column("image", sa.JSON(), nullable=True))
    op.add_column("messages", sa.Column("gif", sa.JSON(), nullable=True))
    op.create_table(
        "message_reactions",
        sa.Column("message_id", sa.Uuid(), sa.ForeignKey("messages.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("emoji", sa.String(16), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )


def downgrade() -> None:
    op.drop_table("message_reactions")
    op.drop_column("messages", "gif")
    op.drop_column("messages", "image")
    op.drop_column("messages", "reply_to_id")
    op.drop_table("comments")
    op.drop_column("photos", "comment_policy")
