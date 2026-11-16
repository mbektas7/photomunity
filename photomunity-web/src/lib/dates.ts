/** <input type="datetime-local"> değerini ve ISO tarihini birbirine çevirir (kullanıcının yerel saatinde). */
export function toLocalInput(iso: string | null | undefined) {
  if (!iso) return "";
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function fromLocalInput(value: string) {
  return value ? new Date(value).toISOString() : "";
}

export function formatDateTime(iso: string, locale: string) {
  return new Intl.DateTimeFormat(locale, { dateStyle: "long", timeStyle: "short" }).format(new Date(iso));
}

/** "3 gün 4 saat" gibi kalan süre; geçtiyse null. */
export function remaining(iso: string, locale: string) {
  const ms = new Date(iso).getTime() - Date.now();
  if (ms <= 0) return null;
  const days = Math.floor(ms / 86_400_000);
  const hours = Math.floor((ms % 86_400_000) / 3_600_000);
  const minutes = Math.floor((ms % 3_600_000) / 60_000);
  const tr = locale === "tr";
  if (days > 0) return tr ? `${days} gün ${hours} saat` : `${days}d ${hours}h`;
  if (hours > 0) return tr ? `${hours} saat ${minutes} dk` : `${hours}h ${minutes}m`;
  return tr ? `${minutes} dakika` : `${minutes} min`;
}
