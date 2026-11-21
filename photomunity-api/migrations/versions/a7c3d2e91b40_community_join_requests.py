"""community join approval and join requests

Revision ID: a7c3d2e91b40
Revises: f55b89bd1527
Create Date: 2026-11-21 21:20:00
"""
from alembic import op
import sqlalchemy as sa


revision = 'a7c3d2e91b40'
down_revision = 'f55b89bd1527'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('communities', sa.Column('join_approval', sa.Boolean(), server_default=sa.false(), nullable=False))
    op.create_table(
        'community_join_requests',
        sa.Column('community_id', sa.Uuid(), nullable=False),
        sa.Column('user_id', sa.Uuid(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['community_id'], ['communities.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('community_id', 'user_id'),
    )
    op.create_index(op.f('ix_community_join_requests_user_id'), 'community_join_requests', ['user_id'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_community_join_requests_user_id'), table_name='community_join_requests')
    op.drop_table('community_join_requests')
    op.drop_column('communities', 'join_approval')
