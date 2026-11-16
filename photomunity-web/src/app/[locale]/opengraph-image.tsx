import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { ImageResponse } from "next/og";

// Görsel oluşturucu değişken yazı tipini desteklemez; statik kalın kesim (Türkçe karakterler latin-ext'te)
const fontDir = join(process.cwd(), "node_modules/@fontsource/schibsted-grotesk/files");
const font = (subset: string, weight: number) => readFile(join(fontDir, `schibsted-grotesk-${subset}-${weight}-normal.woff`));

export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
export const alt = "Photomunity";

/** Paylaşım görseli: uygulamanın kimliği (galeri grisi, kırpılmamış baskılar, siyah vizör şeridi). */
export default async function OgImage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  const tr = locale === "tr";
  const [latin700, ext700, latin600, ext600] = await Promise.all([font("latin", 700), font("latin-ext", 700), font("latin", 600), font("latin-ext", 600)]);
  const prints = [
    { w: 300, h: 200, bg: "linear-gradient(180deg,#0a0c1e,#2a2a55)" },
    { w: 140, h: 200, bg: "linear-gradient(180deg,#c6cccd,#2c3633)" },
    { w: 260, h: 200, bg: "linear-gradient(180deg,#3a4a80,#f4a870)" },
    { w: 200, h: 200, bg: "linear-gradient(180deg,#5a7aa8,#e4ecf4)" },
  ];
  return new ImageResponse(
    (
      <div style={{ width: "100%", height: "100%", display: "flex", flexDirection: "column", background: "#e6e6e3", padding: "56px 64px", color: "#1a1b1e", fontFamily: "SG, SG Ext" }}>
        <div style={{ fontSize: 34, fontWeight: 700, letterSpacing: -1 }}>Photomunity</div>
        <div style={{ fontSize: 76, fontWeight: 700, letterSpacing: -3, lineHeight: 1, marginTop: 28, maxWidth: 900 }}>
          {tr ? "Fotoğrafçıların buluştuğu yer." : "Where photographers meet."}
        </div>
        <div style={{ display: "flex", gap: 8, marginTop: "auto" }}>
          {prints.map((p, i) => <div key={i} style={{ width: p.w, height: p.h, background: p.bg, border: "8px solid #fbfbf9" }} />)}
        </div>
        <div style={{ display: "flex", gap: 40, background: "#000", color: "#f2f2ee", padding: "14px 24px", marginTop: 16, fontSize: 26, fontWeight: 600 }}>
          <span>1/250</span><span>f/8</span><span>ISO 100</span><span>35mm</span>
        </div>
      </div>
    ),
    {
      ...size,
      fonts: [
        // Aynı adlı ikinci dosyaya geçilmediği için alt kümeler ayrı adla, yedek zinciri olarak verilir
        { name: "SG", data: latin700, weight: 700 },
        { name: "SG", data: latin600, weight: 600 },
        { name: "SG Ext", data: ext700, weight: 700 },
        { name: "SG Ext", data: ext600, weight: 600 },
      ],
    },
  );
}
