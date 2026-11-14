import { Header, MobileTabBar } from "@/components/Shell";
import { RealtimeBridge } from "@/lib/realtime";

export default function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      <Header />
      <RealtimeBridge />
      <main className="pb-28 md:pb-16 [&:has([data-fullbleed])]:pb-0">{children}</main>
      <MobileTabBar />
    </>
  );
}
