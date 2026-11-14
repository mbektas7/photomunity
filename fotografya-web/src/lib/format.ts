export function countryName(code: string | null, locale: string) {
  if (!code) return null;
  try {
    return new Intl.DisplayNames([locale], { type: "region" }).of(code.toUpperCase()) ?? code;
  } catch {
    return code;
  }
}

export function formatDate(iso: string | null, locale: string) {
  if (!iso) return null;
  return new Intl.DateTimeFormat(locale, { dateStyle: "long" }).format(new Date(iso));
}

export function initials(name: string) {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((p) => p[0]!.toLocaleUpperCase())
    .join("");
}

export function cameraName(make: string | null, model: string | null) {
  if (!model) return make;
  if (make && !model.toLowerCase().startsWith(make.toLowerCase().split(" ")[0]!)) return `${make} ${model}`;
  return model;
}
