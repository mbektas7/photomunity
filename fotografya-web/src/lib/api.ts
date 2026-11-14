export class ApiError extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
    public details: { code: string; message: string }[] = [],
  ) {
    super(message);
  }
}

type Init = { method?: string; body?: unknown; headers?: Record<string, string> };

function locale() {
  return typeof document !== "undefined" ? document.documentElement.lang || "tr" : "tr";
}

async function request<T>(url: string, init: Init = {}): Promise<T> {
  const res = await fetch(url, {
    method: init.method ?? "GET",
    headers: { "content-type": "application/json", "accept-language": locale(), ...init.headers },
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
    cache: "no-store",
  });
  if (res.status === 204) return undefined as T;
  const data = await res.json().catch(() => null);
  if (!res.ok) {
    const err = data?.error;
    // FastAPI doğrulama hataları {detail: [{msg}]} biçiminde gelir
    const validation = Array.isArray(data?.detail) ? String(data.detail[0]?.msg ?? "") : "";
    throw new ApiError(res.status, err?.code ?? (validation ? "validation" : "unknown"), err?.message ?? validation, err?.details ?? []);
  }
  return data as T;
}

/** Backend'e Next.js BFF üzerinden istek (oturum çerezleri sunucuda eklenir). */
export function api<T>(path: string, init?: Init) {
  return request<T>(`/api/proxy/${path.replace(/^\//, "")}`, init);
}

/** Oturum açan/kapatan uçlar: login, register, google, apple, logout */
export function authAction<T>(action: string, body: unknown = {}) {
  return request<T>(`/api/auth/${action}`, { method: "POST", body });
}

/** Presigned POST ile dosyayı doğrudan depolamaya yükler; ilerlemeyi 0-1 arası bildirir. */
export function uploadToStorage(url: string, fields: Record<string, string>, file: File, onProgress: (p: number) => void) {
  return new Promise<void>((resolve, reject) => {
    const form = new FormData();
    Object.entries(fields).forEach(([k, v]) => form.append(k, v));
    form.append("file", file);
    const xhr = new XMLHttpRequest();
    xhr.open("POST", url);
    xhr.upload.onprogress = (e) => e.lengthComputable && onProgress(e.loaded / e.total);
    xhr.onload = () => (xhr.status >= 200 && xhr.status < 300 ? resolve() : reject(new Error(`upload ${xhr.status}`)));
    xhr.onerror = () => reject(new Error("upload network"));
    xhr.send(form);
  });
}
