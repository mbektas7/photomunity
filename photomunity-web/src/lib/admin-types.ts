import type { UserCard, Variants } from "@/lib/types";

export type Paged<T> = { items: T[]; total: number };

export type AdminUserRow = {
  id: string;
  username: string;
  display_name: string;
  email: string;
  avatar_url: string | null;
  is_pro: boolean;
  is_admin: boolean;
  is_active: boolean;
  email_verified: boolean;
  providers: string[];
  country: string | null;
  photo_count: number;
  follower_count: number;
  created_at: string;
};

export type AdminUserDetail = AdminUserRow & {
  city: string | null;
  last_login: string | null;
  platforms: string[];
  communities: number;
  communities_admin: number;
  subscription: { store: string; product_id: string | null; status: string; period_end: string | null } | null;
  report_count: number;
  is_owner: boolean;
};

export type AdminPhoto = {
  id: string;
  title: string | null;
  user: UserCard;
  images: Variants;
  status: "pending" | "processing" | "published" | "rejected";
  hidden: boolean;
  width: number | null;
  height: number | null;
  like_count: number;
  created_at: string;
};

export type AdminStats = {
  users: { total: number; week: number };
  photos: { total: number; week: number };
  pro: { total: number };
  reports: { open: number; overdue: number };
  communities: { total: number; month: number };
  contests: { running: number; judging: number };
  uploads: { date: string; count: number }[];
  pending: { grace: number; awaiting_results: { id: string; title: string; results_at: string }[] };
  recent_users: AdminUserRow[];
};

export type ReportGroup = {
  target_type: "photo" | "user" | "comment" | "message";
  target_id: string;
  status: "open" | "resolved";
  resolution: string | null;
  first_at: string;
  reasons: string[];
  reports: { id: string; reason: string; note: string | null; created_at: string; reporter: UserCard | null }[];
  photo: AdminPhoto | null;
  /** Yorum ve mesaj şikâyetlerinde içerik; sahibi (owner) yazandır */
  content: ReportContent | null;
  owner: AdminUserRow | null;
  owner_prior_reports: number;
};

export type ReportContent = {
  body: string | null;
  photo_id?: string | null;
  image_url?: string | null;
  gif_url?: string | null;
  created_at: string;
  removed: boolean;
};

export type CommunityMini = { id: string; slug: string; name: string; logo_url: string | null };

export type AdminCommunity = CommunityMini & {
  city: string | null;
  country: string | null;
  owner: UserCard | null;
  join_approval: boolean;
  hidden: boolean;
  member_count: number;
  post_count: number;
  contest_count: number;
  created_at: string;
};

export type AdminCommunityDetail = AdminCommunity & {
  admin_count: number;
  pending_requests: number;
  news_count: number;
  photo_post_count: number;
};

export type AdminContest = {
  id: string;
  title: string;
  community: CommunityMini;
  judging_mode: "jury" | "public";
  anonymous: boolean;
  status: "draft" | "open" | "judging" | "closed" | "finished" | "cancelled";
  hidden: boolean;
  entry_count: number;
  entrant_count: number;
  submission_deadline: string;
  voting_end: string;
  results_at: string;
  published_at: string | null;
};

export type AdminContestDetail = AdminContest & { judge_count: number; judges_done: number; reported_entries: number };

export type AdminSubscription = {
  id: string;
  user: UserCard | null;
  store: "app_store" | "play_store" | "stripe";
  product_id: string | null;
  status: "active" | "grace" | "cancelled" | "expired";
  will_renew: boolean;
  period_end: string | null;
};

export type Announcement = {
  id: string;
  channels: ("push" | "inbox" | "banner")[];
  title_tr: string;
  title_en: string;
  body_tr: string;
  body_en: string;
  link: string | null;
  audience: { kind: "all" | "pro" | "community" | "locale" | "country"; value: string | null };
  recipient_count: number;
  banner_until: string | null;
  created_at: string;
};

export type AdminMember = UserCard & { is_owner: boolean; since: string | null };

export type LogEntry = {
  id: string;
  action: string;
  kind: string;
  target_type: string | null;
  target_id: string | null;
  target_label: string | null;
  note: string | null;
  created_at: string;
  admin: UserCard | null;
};
