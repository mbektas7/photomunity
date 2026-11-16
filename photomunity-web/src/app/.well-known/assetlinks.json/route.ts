/**
 * Android App Links doğrulaması. ANDROID_CERT_SHA256: Play Console → Uygulama bütünlüğü → imzalama anahtarının
 * SHA-256 parmak izi (birden fazlaysa virgülle). Boşsa liste boş döner ve bağlantılar tarayıcıda açılır.
 */
const PACKAGE = process.env.ANDROID_PACKAGE || "app.photomunity.photomunity";
const FINGERPRINTS = (process.env.ANDROID_CERT_SHA256 || "").split(",").map((s) => s.trim()).filter(Boolean);

export function GET() {
  return Response.json(
    FINGERPRINTS.length
      ? [{ relation: ["delegate_permission/common.handle_all_urls"],
           target: { namespace: "android_app", package_name: PACKAGE, sha256_cert_fingerprints: FINGERPRINTS } }]
      : [],
  );
}
