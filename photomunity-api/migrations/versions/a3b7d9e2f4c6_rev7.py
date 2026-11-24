"""Revizyon 7: haftalık tema, eleştiri modu, koleksiyonlar, topluluk etkinlikleri, çekim planları, lisans ayarları

Revision ID: a3b7d9e2f4c6
Revises: f1a7c3e9b2d4
"""
import sqlalchemy as sa
from alembic import op

revision = "a3b7d9e2f4c6"
down_revision = "f1a7c3e9b2d4"
branch_labels = None
depends_on = None


def _fk(table: str, ondelete: str = "CASCADE"):
    return sa.ForeignKey(f"{table}.id", ondelete=ondelete)


def upgrade() -> None:
    # ---- Lisans ve eleştiri alanları
    op.add_column("users", sa.Column("default_license", sa.String(12), server_default="all_rights", nullable=False))
    op.add_column("users", sa.Column("default_downloads_disabled", sa.Boolean(), server_default=sa.false(), nullable=False))
    op.add_column("photos", sa.Column("critique_requested", sa.Boolean(), server_default=sa.false(), nullable=False))
    op.add_column("photos", sa.Column("critique_question", sa.String(300), nullable=True))
    op.add_column("photos", sa.Column("license", sa.String(12), server_default="all_rights", nullable=False))
    op.add_column("photos", sa.Column("downloads_disabled", sa.Boolean(), server_default=sa.false(), nullable=False))
    op.create_index("ix_photos_critique_requested", "photos", ["critique_requested"])

    # ---- Haftalık tema
    op.create_table(
        "weekly_themes",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("number", sa.Integer(), nullable=False, unique=True),
        sa.Column("title_tr", sa.String(100), nullable=False),
        sa.Column("title_en", sa.String(100), nullable=False),
        sa.Column("description_tr", sa.String(1000), nullable=True),
        sa.Column("description_en", sa.String(1000), nullable=True),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_by", sa.Uuid(), _fk("users", "SET NULL"), nullable=True),
        sa.Column("finalized_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("winner_entry_id", sa.Uuid(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_weekly_themes_starts_at", "weekly_themes", ["starts_at"])
    op.create_index("ix_weekly_themes_ends_at", "weekly_themes", ["ends_at"])
    op.create_table(
        "theme_entries",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("theme_id", sa.Uuid(), _fk("weekly_themes"), nullable=False),
        sa.Column("user_id", sa.Uuid(), _fk("users"), nullable=False),
        sa.Column("photo_id", sa.Uuid(), _fk("photos"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("theme_id", "user_id"),
    )
    op.create_index("ix_theme_entries_theme_id", "theme_entries", ["theme_id"])
    op.create_index("ix_theme_entries_user_id", "theme_entries", ["user_id"])
    op.create_index("ix_theme_entries_photo_id", "theme_entries", ["photo_id"])

    # ---- Eleştiri
    op.create_table(
        "critiques",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("photo_id", sa.Uuid(), _fk("photos"), nullable=False),
        sa.Column("user_id", sa.Uuid(), _fk("users"), nullable=False),
        sa.Column("composition", sa.Integer(), nullable=False),
        sa.Column("light", sa.Integer(), nullable=False),
        sa.Column("focus", sa.Integer(), nullable=False),
        sa.Column("editing", sa.Integer(), nullable=False),
        sa.Column("good", sa.Text(), nullable=True),
        sa.Column("improve", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("photo_id", "user_id"),
    )
    op.create_index("ix_critiques_photo_id", "critiques", ["photo_id"])
    op.create_index("ix_critiques_user_id", "critiques", ["user_id"])
    op.create_table(
        "critique_helpful",
        sa.Column("critique_id", sa.Uuid(), _fk("critiques"), primary_key=True),
        sa.Column("user_id", sa.Uuid(), _fk("users"), primary_key=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_critique_helpful_user_id", "critique_helpful", ["user_id"])

    # ---- Koleksiyonlar
    op.create_table(
        "collections",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("user_id", sa.Uuid(), _fk("users"), nullable=False),
        sa.Column("title", sa.String(100), nullable=False),
        sa.Column("description", sa.String(500), nullable=True),
        sa.Column("position", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_collections_user_id", "collections", ["user_id"])
    op.create_table(
        "collection_items",
        sa.Column("collection_id", sa.Uuid(), _fk("collections"), primary_key=True),
        sa.Column("photo_id", sa.Uuid(), _fk("photos"), primary_key=True),
        sa.Column("position", sa.Integer(), nullable=False, server_default="0"),
    )
    op.create_index("ix_collection_items_photo_id", "collection_items", ["photo_id"])

    # ---- Topluluk etkinlikleri
    op.create_table(
        "community_events",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("community_id", sa.Uuid(), _fk("communities"), nullable=False),
        sa.Column("title", sa.String(150), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("location_name", sa.String(200), nullable=False),
        sa.Column("latitude", sa.Float(), nullable=True),
        sa.Column("longitude", sa.Float(), nullable=True),
        sa.Column("capacity", sa.Integer(), nullable=True),
        sa.Column("bring", sa.String(500), nullable=True),
        sa.Column("created_by", sa.Uuid(), _fk("users", "SET NULL"), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("cancelled_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("reminder_sent", sa.Boolean(), server_default=sa.false(), nullable=False),
    )
    op.create_index("ix_community_events_community_id", "community_events", ["community_id"])
    op.create_index("ix_community_events_starts_at", "community_events", ["starts_at"])
    op.create_table(
        "event_attendees",
        sa.Column("event_id", sa.Uuid(), _fk("community_events"), primary_key=True),
        sa.Column("user_id", sa.Uuid(), _fk("users"), primary_key=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_event_attendees_user_id", "event_attendees", ["user_id"])

    # ---- Çekim planları
    op.create_table(
        "shoot_plans",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("user_id", sa.Uuid(), _fk("users"), nullable=False),
        sa.Column("kind", sa.String(12), nullable=False),
        sa.Column("title", sa.String(120), nullable=True),
        sa.Column("latitude", sa.Float(), nullable=False),
        sa.Column("longitude", sa.Float(), nullable=False),
        sa.Column("place_name", sa.String(200), nullable=True),
        sa.Column("target_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("remind", sa.Boolean(), nullable=False),
        sa.Column("weather_alert", sa.Boolean(), nullable=False),
        sa.Column("notes", sa.String(1000), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("reminded_day_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("reminded_hour_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("weather_alerted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("weather_checked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_cloud_cover", sa.Integer(), nullable=True),
    )
    op.create_index("ix_shoot_plans_user_id", "shoot_plans", ["user_id"])
    op.create_index("ix_shoot_plans_target_at", "shoot_plans", ["target_at"])


def downgrade() -> None:
    op.drop_table("shoot_plans")
    op.drop_table("event_attendees")
    op.drop_table("community_events")
    op.drop_table("collection_items")
    op.drop_table("collections")
    op.drop_table("critique_helpful")
    op.drop_table("critiques")
    op.drop_table("theme_entries")
    op.drop_table("weekly_themes")
    op.drop_index("ix_photos_critique_requested", table_name="photos")
    for col in ("downloads_disabled", "license", "critique_question", "critique_requested"):
        op.drop_column("photos", col)
    op.drop_column("users", "default_downloads_disabled")
    op.drop_column("users", "default_license")
