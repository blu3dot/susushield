import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "SusuShield — Privacy-Preserving Savings Circles",
  description:
    "Private savings circles with commit-reveal contributions and ZK identity verification. Synthesis Hackathon 2026.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className="min-h-screen bg-gray-950 text-white">
        <nav className="border-b border-gray-800 px-6 py-4">
          <div className="max-w-4xl mx-auto flex items-center justify-between">
            <div className="flex items-center gap-3">
              <span className="text-2xl">🛡️</span>
              <h1 className="text-xl font-bold text-shield-500">SusuShield</h1>
            </div>
            <span className="text-xs text-gray-500">Base Mainnet</span>
          </div>
        </nav>
        <main className="max-w-4xl mx-auto px-6 py-8">{children}</main>
      </body>
    </html>
  );
}
