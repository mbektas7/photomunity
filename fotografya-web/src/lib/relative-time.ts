const UNITS: [Intl.RelativeTimeFormatUnit, number][] = [
  ["year", 31536000], ["month", 2592000], ["week", 604800], ["day", 86400], ["hour", 3600], ["minute", 60],
];

export function relativeTime(iso: string, locale: string) {
  const diff = (new Date(iso).getTime() - Date.now()) / 1000;
  const fmt = new Intl.RelativeTimeFormat(locale, { numeric: "auto" });
  for (const [unit, sec] of UNITS) {
    if (Math.abs(diff) >= sec) return fmt.format(Math.round(diff / sec), unit);
  }
  return fmt.format(0, "minute");
}
