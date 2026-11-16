import { NextRequest, NextResponse } from "next/server";
import { API_URL, applyTokens, clearTokens, readTokens } from "@/lib/session";

const TARGETS: Record<string, string> = {
  login: "auth/login",
  register: "auth/register",
  google: "auth/oauth/google",
  apple: "auth/oauth/apple",
};

export async function POST(req: NextRequest, ctx: { params: Promise<{ action: string }> }) {
  const { action } = await ctx.params;

  if (action === "logout") {
    const { refresh } = await readTokens();
    if (refresh) {
      await fetch(`${API_URL}/auth/logout`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ refresh_token: refresh }),
      }).catch(() => undefined);
    }
    const res = NextResponse.json({ ok: true });
    clearTokens(res);
    return res;
  }

  const target = TARGETS[action];
  if (!target) return NextResponse.json({ error: { code: "not_found", message: "Not found" } }, { status: 404 });

  const upstream = await fetch(`${API_URL}/${target}`, {
    method: "POST",
    headers: { "content-type": "application/json", "accept-language": req.headers.get("accept-language") ?? "tr" },
    body: await req.text(),
    cache: "no-store",
  });
  const data = await upstream.json().catch(() => ({}));
  if (!upstream.ok) return NextResponse.json(data, { status: upstream.status });

  // Token'lar tarayıcıya JSON olarak hiç verilmez; yalnızca httpOnly çerezde durur.
  const res = NextResponse.json({ user: data.user, is_new_user: data.is_new_user }, { status: upstream.status });
  applyTokens(res, data.tokens);
  return res;
}
