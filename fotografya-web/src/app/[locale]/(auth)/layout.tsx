import { Wordmark } from "@/components/Shell";
import { Link } from "@/i18n/navigation";

export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-dvh flex-col">
      <header className="mx-auto flex h-16 w-full max-w-[1400px] items-center px-4 sm:px-6">
        <Link href="/" aria-label="Fotografya">
          <Wordmark />
        </Link>
      </header>
      <main className="flex flex-1 items-start justify-center px-4 pb-16 pt-6 sm:pt-14">
        <div className="w-full max-w-[420px]">{children}</div>
      </main>
    </div>
  );
}
