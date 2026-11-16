import { LEGAL_UPDATED, contactEmail, legalDoc, legalEntity, type LegalDoc } from "@/lib/legal";
import { Link } from "@/i18n/navigation";

/** Gizlilik politikası / kullanım koşulları: bg üzerinde surface kart, okunabilir satır uzunluğu. */
export function LegalPage({ doc, locale }: { doc: LegalDoc; locale: string }) {
  const d = legalDoc(doc, locale);
  const tr = locale === "tr";
  const date = new Date(LEGAL_UPDATED).toLocaleDateString(tr ? "tr-TR" : "en-GB", { day: "numeric", month: "long", year: "numeric" });
  const other = doc === "privacy" ? "/terms" : "/privacy";
  return (
    <div className="mx-auto max-w-[760px] px-4 pt-8 sm:px-6 sm:pt-12">
      <h1 className="text-[clamp(2rem,4.5vw,3rem)] font-bold leading-none tracking-[-0.04em]">{d.title}</h1>
      <p className="mt-3 text-ink-muted">{d.lead}</p>
      <p className="mt-2 text-sm text-ink-muted">{d.updated}: {date}</p>
      {(!legalEntity || !contactEmail) && (
        // Yayın öncesi uyarı: unvan ve iletişim adresi tanımlanmadan bu metin eksiktir.
        <p role="note" className="mt-6 rounded-box bg-danger/10 px-4 py-3 text-sm text-danger">
          {tr ? "Yayın öncesi: şirket unvanı ve iletişim adresi tanımlanmadı" : "Before launch: company name and contact address are not set"} (NEXT_PUBLIC_LEGAL_ENTITY, NEXT_PUBLIC_CONTACT_EMAIL)
        </p>
      )}
      <div className="mt-8 space-y-3">
        {d.sections.map((s) => (
          <section key={s.h} className="rounded-card bg-surface px-5 py-5 sm:px-6">
            <h2 className="text-[18px] font-bold leading-6">{s.h}</h2>
            {s.p.map((p, i) => (
              <p key={i} className="mt-2.5 leading-relaxed text-ink-muted">{p}</p>
            ))}
          </section>
        ))}
      </div>
      <p className="mt-6 text-sm">
        <Link href={other} className="font-semibold text-accent-text hover:underline">
          {legalDoc(doc === "privacy" ? "terms" : "privacy", locale).title}
        </Link>
      </p>
    </div>
  );
}
