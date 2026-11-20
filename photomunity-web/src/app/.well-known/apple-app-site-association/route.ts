/**
 * iOS Universal Links: https://photomunity.com/… bağlantılarını uygulama açar.
 * APPLE_TEAM_ID App Store Connect'teki ekip kimliğidir (mobil projede DEVELOPMENT_TEAM).
 */
const TEAM_ID = process.env.APPLE_TEAM_ID || "3C8FGT67DB";
const BUNDLE_ID = process.env.IOS_BUNDLE_ID || "app.photomunity.photomunity";

// Uygulamada karşılığı olan yollar; diğerleri tarayıcıda açılır.
const PATHS = ["/verify-email", "/reset-password", "/invite/*", "/p/*", "/u/*", "/c/*", "/contests/*",
  "/tr/p/*", "/en/p/*", "/tr/u/*", "/en/u/*", "/tr/c/*", "/en/c/*", "/tr/contests/*", "/en/contests/*"];

export function GET() {
  return Response.json({
    applinks: { details: [{ appIDs: [`${TEAM_ID}.${BUNDLE_ID}`], components: PATHS.map((p) => ({ "/": p })) }] },
  });
}
