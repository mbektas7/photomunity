"use client";

import clsx from "clsx";
import { forwardRef } from "react";
import { buttonClass } from "@/lib/button-class";

export { buttonClass };

type ButtonProps = React.ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "primary" | "secondary" | "ghost" | "danger";
  busy?: boolean;
};


export function Button({ variant = "primary", busy, className, children, disabled, ...rest }: ButtonProps) {
  return (
    <button className={buttonClass(variant, className)} disabled={disabled || busy} aria-busy={busy} {...rest}>
      {children}
    </button>
  );
}

type FieldProps = React.InputHTMLAttributes<HTMLInputElement> & { label: string; hint?: string; error?: string };

export const TextField = forwardRef<HTMLInputElement, FieldProps>(function TextField(
  { label, hint, error, id, className, ...rest },
  ref,
) {
  const fieldId = id ?? rest.name;
  return (
    <div className={clsx("flex flex-col gap-1.5", className)}>
      <label htmlFor={fieldId} className="text-sm font-medium">
        {label}
      </label>
      <input
        ref={ref}
        id={fieldId}
        aria-invalid={!!error}
        aria-describedby={hint || error ? `${fieldId}-hint` : undefined}
        className="h-11 rounded-[10px] border border-line bg-mat px-3.5 text-[15px] outline-none transition-colors placeholder:text-muted/70 focus:border-ink aria-[invalid=true]:border-danger"
        {...rest}
      />
      {(error || hint) && (
        <p id={`${fieldId}-hint`} className={clsx("text-sm", error ? "text-danger" : "text-muted")}>
          {error ?? hint}
        </p>
      )}
    </div>
  );
});

type AreaProps = React.TextareaHTMLAttributes<HTMLTextAreaElement> & { label: string; hint?: string };

export function TextArea({ label, hint, id, ...rest }: AreaProps) {
  const fieldId = id ?? rest.name;
  return (
    <div className="flex flex-col gap-1.5">
      <label htmlFor={fieldId} className="text-sm font-medium">
        {label}
      </label>
      <textarea
        id={fieldId}
        rows={4}
        className="rounded-[10px] border border-line bg-mat px-3.5 py-3 text-[15px] leading-relaxed outline-none focus:border-ink"
        {...rest}
      />
      {hint && <p className="text-sm text-muted">{hint}</p>}
    </div>
  );
}

export function Notice({ tone = "info", children }: { tone?: "info" | "error" | "success"; children: React.ReactNode }) {
  return (
    <div
      role={tone === "error" ? "alert" : "status"}
      className={clsx(
        "rounded-[10px] border px-4 py-3 text-[15px]",
        tone === "error" && "border-danger/40 text-danger",
        tone === "success" && "border-accent/40 text-ink",
        tone === "info" && "border-line text-muted",
      )}
    >
      {children}
    </div>
  );
}

export function Toggle({ checked, onChange, label, hint }: { checked: boolean; onChange: (v: boolean) => void; label: string; hint?: string }) {
  return (
    <label className="flex cursor-pointer items-start justify-between gap-6">
      <span>
        <span className="block text-[15px] font-medium">{label}</span>
        {hint && <span className="mt-0.5 block text-sm text-muted">{hint}</span>}
      </span>
      <span className="relative mt-0.5 inline-flex shrink-0">
        <input type="checkbox" className="peer sr-only" checked={checked} onChange={(e) => onChange(e.target.checked)} />
        <span className="h-7 w-12 rounded-full bg-line transition-colors peer-checked:bg-accent peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-accent" />
        <span className="absolute left-1 top-1 h-5 w-5 rounded-full bg-mat transition-transform peer-checked:translate-x-5" />
      </span>
    </label>
  );
}
