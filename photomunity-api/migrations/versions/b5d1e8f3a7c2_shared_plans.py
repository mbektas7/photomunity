"""Revizyon 7b: paylaşılan çekim planları ve katılım

Revision ID: b5d1e8f3a7c2
Revises: a3b7d9e2f4c6
"""
import sqlalchemy as sa
from alembic import op

revision = "b5d1e8f3a7c2"
down_revision = "a3b7d9e2f4c6"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("shoot_plans", sa.Column("shared", sa.Boolean(), server_default=sa.false(), nullable=False))
    op.create_index("ix_shoot_plans_shared_target", "shoot_plans", ["shared", "target_at"])
    op.create_table(
        "plan_joins",
        sa.Column("plan_id", sa.Uuid(), sa.ForeignKey("shoot_plans.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("reminded_day_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("reminded_hour_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_plan_joins_user_id", "plan_joins", ["user_id"])


def downgrade() -> None:
    op.drop_table("plan_joins")
    op.drop_index("ix_shoot_plans_shared_target", table_name="shoot_plans")
    op.drop_column("shoot_plans", "shared")
