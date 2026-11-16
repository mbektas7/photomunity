// Gizlilik politikası ve kullanım koşulları metinleri (TR/EN).
// TASLAK: yayından önce bir hukukçu tarafından gözden geçirilmeli (KVKK / GDPR, tüketici mevzuatı).
// Şirket unvanı ve iletişim adresi ortam değişkenlerinden gelir; uydurma bilgi yazılmaz.

export type LegalDoc = "privacy" | "terms";
type Section = { h: string; p: string[] };
type Doc = { title: string; lead: string; updated: string; sections: Section[] };

export const LEGAL_UPDATED = "2026-11-16";

export const legalEntity = process.env.NEXT_PUBLIC_LEGAL_ENTITY || "";
export const contactEmail = process.env.NEXT_PUBLIC_CONTACT_EMAIL || "";

const who = (tr: boolean) =>
  legalEntity
    ? tr ? `Photomunity hizmeti ${legalEntity} tarafından sunulur.` : `Photomunity is operated by ${legalEntity}.`
    : tr ? "Photomunity hizmetini sunan kuruluş." : "The organisation that operates Photomunity.";

const contact = (tr: boolean) =>
  contactEmail
    ? tr ? `Sorular ve talepler için: ${contactEmail}` : `Questions and requests: ${contactEmail}`
    : "";

export function legalDoc(doc: LegalDoc, locale: string): Doc {
  const tr = locale === "tr";
  if (doc === "privacy") {
    return tr
      ? {
          title: "Gizlilik politikası",
          lead: "Hangi verileri neden işlediğimizi, kimlerle paylaştığımızı ve haklarını sade bir dille anlatıyoruz.",
          updated: "Son güncelleme",
          sections: [
            { h: "Veri sorumlusu", p: [who(true), contact(true)].filter(Boolean) },
            {
              h: "Topladığımız veriler",
              p: [
                "Hesap: ad, kullanıcı adı, e-posta adresi, şifrenin geri döndürülemez özeti; Apple veya Google ile girersen bu sağlayıcının verdiği kimlik ve ad.",
                "Profil ve içerik: yüklediğin fotoğraflar, başlık ve açıklamalar, eklediğin konum adı, ekipman bilgisi, yorumlar, beğeniler, takip ettiklerin, topluluk ve yarışma katılımların, mesajların.",
                "Çekim bilgisi (EXIF): makine, objektif, diyafram, enstantane, ISO gibi bilgiler fotoğrafın yanında gösterilir. Fotoğraftaki GPS konumu ayrı saklanır ve herkese açık kopyalara hiçbir zaman yazılmaz.",
                "Teknik veriler: IP adresi, cihaz ve tarayıcı bilgisi, bildirim için cihaz belirteci. IP adresi güvenlik, istek sınırlama ve yarışma oylarında hileyi önlemek için kullanılır.",
                "Ödeme: Pro aboneliğinde ödeme bilgilerini biz görmeyiz; ödeme Apple, Google veya Stripe üzerinden yapılır, bize yalnızca abonelik durumu iletilir.",
              ],
            },
            {
              h: "Verileri neden işliyoruz",
              p: [
                "Hizmeti sunmak (hesap, paylaşım, mesajlaşma, yarışmalar), sözleşmenin ifası kapsamında.",
                "Güvenliği sağlamak, kötüye kullanımı ve sahte oyları önlemek, şikâyetleri incelemek; meşru menfaat kapsamında.",
                "Hesabınla ilgili e-postalar ve izin verdiğin bildirimler göndermek.",
                "Reklam göstermek: kişiselleştirilmiş reklamlar yalnızca açık rızanla gösterilir; rıza vermezsen reklamlar kişiselleştirilmez. Pro üyeler reklam görmez.",
              ],
            },
            {
              h: "Kimlerle paylaşıyoruz",
              p: [
                "Hizmeti sunmak için çalıştığımız altyapı sağlayıcıları: barındırma ve veritabanı, fotoğraf depolama ve dağıtım (CDN), e-posta gönderimi, anlık bildirim (Firebase), ödeme (Apple, Google, Stripe, RevenueCat), reklam (Google AdSense / AdMob), bot doğrulama (Cloudflare Turnstile) ve etkinse otomatik içerik denetimi (AWS Rekognition).",
                "Bu sağlayıcılar verileri yalnızca bizim adımıza ve talimatımızla işler. Verilerin bir kısmı yurt dışındaki sunucularda işlenebilir.",
                "Verilerini satmıyoruz. Yasal bir zorunluluk olduğunda yetkili makamlarla paylaşabiliriz.",
              ],
            },
            {
              h: "Ne kadar saklıyoruz",
              p: [
                "Hesabın açık olduğu sürece. Hesabını Ayarlar'dan silebilirsin; silindiğinde hesabın, fotoğrafların ve dosyaları kalıcı olarak kaldırılır. Yasal saklama yükümlülüğü olan kayıtlar bu sürenin sonuna kadar tutulur.",
              ],
            },
            {
              h: "Çerezler",
              p: [
                "Oturumunu açık tutmak için zorunlu bir çerez kullanırız. Reklam ortakları, onay verirsen kendi çerezlerini kullanabilir.",
              ],
            },
            {
              h: "Hakların",
              p: [
                "Verilerine erişme, düzeltme, silme, işlemeye itiraz etme, verilerinin bir kopyasını alma ve rızanı geri çekme hakkın var. Türkiye'de KVKK'nın 11. maddesi, AB'de GDPR kapsamındaki haklar geçerlidir. Talebini yukarıdaki adrese iletebilirsin; ayrıca ilgili veri koruma otoritesine şikâyette bulunabilirsin.",
              ],
            },
            {
              h: "Çocuklar",
              p: ["Photomunity 13 yaşından küçükler için değildir. Bulunduğun ülkede daha yüksek bir yaş sınırı varsa o geçerlidir."],
            },
            { h: "Değişiklikler", p: ["Bu politikayı güncellediğimizde tarihini değiştirir, önemli değişiklikleri uygulama içinde duyururuz."] },
          ],
        }
      : {
          title: "Privacy policy",
          lead: "What data we process and why, who we share it with, and your rights, in plain language.",
          updated: "Last updated",
          sections: [
            { h: "Data controller", p: [who(false), contact(false)].filter(Boolean) },
            {
              h: "Data we collect",
              p: [
                "Account: name, username, email address, an irreversible hash of your password; if you sign in with Apple or Google, the identifier and name that provider shares.",
                "Profile and content: photos you upload, titles and descriptions, place names you add, equipment, comments, likes, who you follow, community and contest participation, and your messages.",
                "Shooting data (EXIF): camera, lens, aperture, shutter speed, ISO and similar are shown with your photo. GPS location in a photo is stored separately and never written to public copies.",
                "Technical data: IP address, device and browser information, and a device token for notifications. IP addresses are used for security, rate limiting and preventing contest vote fraud.",
                "Payments: for Pro we never see your payment details; payment is handled by Apple, Google or Stripe and we only receive the subscription status.",
              ],
            },
            {
              h: "Why we process data",
              p: [
                "To provide the service (account, sharing, messaging, contests), as necessary to perform our contract with you.",
                "To keep the service secure, prevent abuse and fake votes, and handle reports; based on legitimate interest.",
                "To send account emails and the notifications you allow.",
                "To show ads: personalised ads are shown only with your consent; without it ads are not personalised. Pro members see no ads.",
              ],
            },
            {
              h: "Who we share data with",
              p: [
                "Infrastructure providers that help us run the service: hosting and database, photo storage and delivery (CDN), email delivery, push notifications (Firebase), payments (Apple, Google, Stripe, RevenueCat), advertising (Google AdSense / AdMob), bot protection (Cloudflare Turnstile) and, when enabled, automated content moderation (AWS Rekognition).",
                "These providers process data only on our behalf and instructions. Some data may be processed on servers outside your country.",
                "We do not sell your data. We may share it with authorities where the law requires.",
              ],
            },
            {
              h: "How long we keep data",
              p: [
                "For as long as your account exists. You can delete your account in Settings; your account, photos and files are then permanently removed. Records we are legally required to keep are retained until that obligation ends.",
              ],
            },
            {
              h: "Cookies",
              p: ["We use one essential cookie to keep you signed in. Advertising partners may use their own cookies if you consent."],
            },
            {
              h: "Your rights",
              p: [
                "You have the right to access, correct and delete your data, to object to processing, to receive a copy of your data and to withdraw consent. Rights under the Turkish KVKK (Art. 11) and the EU GDPR apply. Send requests to the address above; you can also complain to your data protection authority.",
              ],
            },
            {
              h: "Children",
              p: ["Photomunity is not for children under 13. If your country sets a higher age, that age applies."],
            },
            { h: "Changes", p: ["When we update this policy we change the date above and announce significant changes in the app."] },
          ],
        };
  }
  return tr
    ? {
        title: "Kullanım koşulları",
        lead: "Photomunity'yi kullanırken geçerli kurallar. Hesap oluşturarak bu koşulları kabul etmiş olursun.",
        updated: "Son güncelleme",
        sections: [
          { h: "Hizmet", p: [who(true), "Photomunity fotoğrafçıların karelerini paylaştığı, topluluklar kurduğu ve yarışmalar düzenlediği bir platformdur.", contact(true)].filter(Boolean) },
          {
            h: "Hesabın",
            p: [
              "Hesap açmak için en az 13 yaşında olmalısın. Verdiğin bilgilerin doğru olmasından ve şifreni korumaktan sen sorumlusun.",
              "Hesabını istediğin zaman Ayarlar'dan silebilirsin.",
            ],
          },
          {
            h: "İçeriğin sana ait",
            p: [
              "Yüklediğin fotoğrafların hakları sende kalır. Photomunity'ye yalnızca bu fotoğrafları sitede ve uygulamada göstermek, uygun boyutlarda kopyalarını oluşturmak ve paylaşım bağlantılarında önizlemek için dünya çapında, ücretsiz ve münhasır olmayan bir izin verirsin. Fotoğrafı veya hesabını sildiğinde bu izin sona erer.",
              "Yalnızca hakkına sahip olduğun içerikleri yükle. Başkasının fotoğrafını kendi adınla paylaşamazsın; fotoğraftaki kişilerin haklarına saygı göstermelisin.",
            ],
          },
          {
            h: "Yasak olanlar",
            p: [
              "Yasa dışı, nefret söylemi içeren, taciz eden, müstehcen veya şiddeti öven içerik; spam; başkasının kimliğine bürünmek; sahte hesaplarla veya otomatik araçlarla oy toplamak; hizmetin güvenliğini aşmaya çalışmak.",
              "Kurallara uymayan içerikleri kaldırabilir, yarışma katılımlarını geçersiz sayabilir ve hesapları askıya alabiliriz. İçeriği uygunsuz bulursan şikâyet edebilirsin.",
            ],
          },
          {
            h: "Yarışmalar",
            p: [
              "Yarışmaları topluluk yöneticileri düzenler; kurallar, ödüller ve ödüllerin teslimi düzenleyen topluluğun sorumluluğundadır. Photomunity yalnızca altyapıyı sağlar.",
              "Halk oylamasında hileli oylar tespit edilirse sayılmayabilir.",
            ],
          },
          {
            h: "Pro abonelik",
            p: [
              "Pro aylık veya yıllık otomatik yenilenen bir aboneliktir. Dönem bitmeden en az 24 saat önce iptal etmezsen yenilenir. Uygulama içinden alınan abonelikler App Store veya Google Play hesabından, web'den alınanlar Pro sayfasından yönetilir ve iptal edilir. İadeler satın almanın yapıldığı mağazanın kurallarına tabidir.",
            ],
          },
          {
            h: "Sorumluluk",
            p: [
              "Hizmeti olduğu gibi sunarız ve kesintisiz çalışacağını garanti edemeyiz. Kullanıcıların paylaştığı içerikten o içeriği paylaşan kişi sorumludur. Yasanın izin verdiği ölçüde dolaylı zararlardan sorumlu değiliz.",
            ],
          },
          { h: "Değişiklikler", p: ["Koşulları güncellediğimizde tarihini değiştirir, önemli değişiklikleri önceden duyururuz."] },
          { h: "Uygulanacak hukuk", p: ["Bu koşullara Türkiye Cumhuriyeti hukuku uygulanır; tüketici olarak sahip olduğun zorunlu haklar saklıdır."] },
        ],
      }
    : {
        title: "Terms of use",
        lead: "The rules for using Photomunity. By creating an account you accept these terms.",
        updated: "Last updated",
        sections: [
          { h: "The service", p: [who(false), "Photomunity is a platform where photographers share their work, build communities and run contests.", contact(false)].filter(Boolean) },
          {
            h: "Your account",
            p: [
              "You must be at least 13 to create an account. You are responsible for the accuracy of your information and for keeping your password safe.",
              "You can delete your account at any time in Settings.",
            ],
          },
          {
            h: "Your content stays yours",
            p: [
              "You keep the rights to the photos you upload. You give Photomunity a worldwide, free, non-exclusive permission only to show them on the site and in the app, create copies at suitable sizes and preview them in shared links. The permission ends when you delete the photo or your account.",
              "Upload only content you have the rights to. You may not post someone else's photo as your own, and you must respect the rights of people in your photos.",
            ],
          },
          {
            h: "Not allowed",
            p: [
              "Illegal, hateful, harassing, sexually explicit or violence-glorifying content; spam; impersonation; collecting votes with fake accounts or automated tools; attempting to break the security of the service.",
              "We may remove content that breaks these rules, disqualify contest entries and suspend accounts. You can report content you find inappropriate.",
            ],
          },
          {
            h: "Contests",
            p: [
              "Contests are run by community admins; rules, prizes and prize delivery are the organising community's responsibility. Photomunity only provides the platform.",
              "Fraudulent public votes may be excluded from the count.",
            ],
          },
          {
            h: "Pro subscription",
            p: [
              "Pro is a monthly or yearly auto-renewing subscription. It renews unless cancelled at least 24 hours before the end of the period. Subscriptions bought in the app are managed and cancelled in your App Store or Google Play account; web subscriptions on the Pro page. Refunds follow the rules of the store where you purchased.",
            ],
          },
          {
            h: "Liability",
            p: [
              "We provide the service as is and cannot guarantee it will be uninterrupted. Users are responsible for the content they share. To the extent permitted by law we are not liable for indirect damages.",
            ],
          },
          { h: "Changes", p: ["When we update these terms we change the date above and announce significant changes in advance."] },
          { h: "Governing law", p: ["These terms are governed by the laws of the Republic of Türkiye; mandatory consumer rights you have are not affected."] },
        ],
      };
}
