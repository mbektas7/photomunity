import { api, uploadToStorage } from "./api";

/** Presigned yükleme + tamamla akışı (profil ve topluluk görselleri için ortak). */
export async function uploadImage<T>(base: string, kind: string, file: File): Promise<T> {
  const contentType = file.type || "image/heic";
  const slot = await api<{ upload_url: string; fields: Record<string, string> }>(`${base}/images/upload-url`, {
    method: "POST",
    body: { kind, content_type: contentType, size_bytes: file.size },
  });
  await uploadToStorage(slot.upload_url, slot.fields, file, () => undefined);
  return api<T>(`${base}/images/complete`, { method: "POST", body: { kind, key: slot.fields.key } });
}
