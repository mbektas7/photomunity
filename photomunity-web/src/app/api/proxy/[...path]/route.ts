import { NextRequest, NextResponse } from "next/server";
import { API_URL, applyTokens, clearTokens, readTokens, refreshTokens, type Tokens } from "@/lib/session";

type Ctx = { params: Promise<{ path: string[] }> };

async function handle(req: NextRequest, ctx: Ctx) {
  const { path } = await ctx.params;
  const route = path.join("/");
  const url = `${API_URL}/${path.map(encodeURIComponent).join("/")}${req.nextUrl.search}`;
  const body = req.method === "GET" || req.method === "HEAD" ? undefined : await req.text();

  let { access } = await readTokens();
  const { refresh } = await readTokens();
  let refreshed: Tokens | null = null;

  if (!access && refresh) {
    refreshed = await refreshTokens(refresh);
    access = refreshed?.access_token;
  }

  const send = (token?: string) =>
    fetch(url, {
      method: req.method,
      headers: {
        "content-type": req.headers.get("content-type") ?? "application/json",
        "accept-language": req.headers.get("accept-language") ?? "tr",
        ...(req.headers.get("x-voter-token") ? { "x-voter-token": req.headers.get("x-voter-token")! } : {}),
        ...(token ? { authorization: `Bearer ${token}` } : {}),
      },
      body,
      cache: "no-store",
    });

  let upstream = await send(access);
  if (upstream.status === 401 && refresh && !refreshed) {
    refreshed = await refreshTokens(refresh);
    if (refreshed) upstream = await send(refreshed.access_token);
  }

  const text = upstream.status === 204 ? null : await upstream.text();
  const res = new NextResponse(text, {
    status: upstream.status,
    headers: { "content-type": upstream.headers.get("content-type") ?? "application/json" },
  });

  if (refreshed) applyTokens(res, refreshed);
  else if (upstream.status === 401 && refresh) clearTokens(res);

  if (upstream.ok && text && route === "auth/change-password") applyTokens(res, JSON.parse(text) as Tokens);
  if (upstream.ok && route === "auth/account" && req.method === "DELETE") clearTokens(res);
  return res;
}

export { handle as GET, handle as POST, handle as PUT, handle as PATCH, handle as DELETE };
