import "server-only";
import { cookies } from "next/headers";
import type { NextResponse } from "next/server";

export const API_URL = process.env.API_URL ?? "http://localhost:8000/api/v1";

const ACCESS = "fg_at";
const REFRESH = "fg_rt";

export type Tokens = { access_token: string; refresh_token: string; expires_in: number };

export function applyTokens(res: NextResponse, t: Tokens) {
  const base = { httpOnly: true, secure: process.env.NODE_ENV === "production", sameSite: "lax" as const, path: "/" };
  res.cookies.set(ACCESS, t.access_token, { ...base, maxAge: Math.max(t.expires_in - 30, 30) });
  res.cookies.set(REFRESH, t.refresh_token, { ...base, maxAge: 60 * 60 * 24 * 30 });
}

export function clearTokens(res: NextResponse) {
  res.cookies.delete(ACCESS);
  res.cookies.delete(REFRESH);
}

export async function readTokens() {
  const jar = await cookies();
  return { access: jar.get(ACCESS)?.value, refresh: jar.get(REFRESH)?.value };
}

/*
 * Aynı refresh token'ı eş zamanlı istekler ayrı ayrı yenilerse backend bunu "yeniden kullanım"
 * sayıp tüm oturumları kapatır. Bu yüzden yenileme, token başına tek bir istekte birleştirilir.
 * Birden fazla Next.js örneği çalıştırılırsa bu birleştirme Redis'e taşınmalı.
 */
const inflight = new Map<string, Promise<Tokens | null>>();

export function refreshTokens(refreshToken: string): Promise<Tokens | null> {
  let pending = inflight.get(refreshToken);
  if (!pending) {
    pending = fetch(`${API_URL}/auth/refresh`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ refresh_token: refreshToken }),
      cache: "no-store",
    })
      .then((r) => (r.ok ? (r.json() as Promise<Tokens>) : null))
      .catch(() => null);
    inflight.set(refreshToken, pending);
    setTimeout(() => inflight.delete(refreshToken), 30_000);
  }
  return pending;
}
