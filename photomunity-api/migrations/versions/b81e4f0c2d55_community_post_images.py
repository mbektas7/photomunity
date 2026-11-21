"""community news post images

Revision ID: b81e4f0c2d55
Revises: a7c3d2e91b40
Create Date: 2026-11-22 10:00:00
"""
from alembic import op
import sqlalchemy as sa


revision = 'b81e4f0c2d55'
down_revision = 'a7c3d2e91b40'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('community_posts', sa.Column('images', sa.JSON(), server_default='[]', nullable=False))


def downgrade() -> None:
    op.drop_column('community_posts', 'images')
