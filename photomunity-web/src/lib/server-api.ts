import "server-only";
import { API_URL } from "./session";

/** Sunucu tarafında herkese açık API okuması; hata durumunda null döner (sayfa bölümü gizlenir). */
export async function serverGet<T>(path: string, locale: string, revalidate = 300): Promise<T | null> {
  try {
    const r = await fetch(`${API_URL}/${path}`, { headers: { "accept-language": locale }, next: { revalidate } });
    return r.ok ? ((await r.json()) as T) : null;
  } catch {
    return null;
  }
}
