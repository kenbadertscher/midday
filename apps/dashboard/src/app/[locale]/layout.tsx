import "@/styles/globals.css";
import { cn } from "@midday/ui/cn";
import "@midday/ui/globals.css";
import { Toaster } from "@midday/ui/toaster";
import type { Metadata } from "next";
import { Hedvig_Letters_Sans, Hedvig_Letters_Serif } from "next/font/google";
import { NuqsAdapter } from "nuqs/adapters/next/app";
import type { ReactElement } from "react";
import { DesktopHeader } from "@/components/desktop-header";
import { isDesktopApp } from "@/utils/desktop";
import { Providers } from "./providers";

export const metadata: Metadata = {
  metadataBase: new URL(process.env.NEXT_PUBLIC_URL || "http://localhost:3001"),
  title: "Midday | Run your business smarter",
  description:
    "Automate financial tasks, stay organized, and make informed decisions effortlessly.",
  twitter: {
    title: "Midday | Run your business smarter",
    description:
      "Automate financial tasks, stay organized, and make informed decisions effortlessly.",
    images: [
      {
        url: `${process.env.NEXT_PUBLIC_CDN_URL || ""}/opengraph-image-v1.jpg`,
        width: 800,
        height: 600,
      },
      {
        url: `${process.env.NEXT_PUBLIC_CDN_URL || ""}/opengraph-image-v1.jpg`,
        width: 1800,
        height: 1600,
      },
    ],
  },
  openGraph: {
    title: "Midday | Run your business smarter",
    description:
      "Automate financial tasks, stay organized, and make informed decisions effortlessly.",
    url: process.env.NEXT_PUBLIC_URL || "http://localhost:3001",
    siteName: "Midday",
    images: [
      {
        url: `${process.env.NEXT_PUBLIC_CDN_URL || ""}/opengraph-image-v1.jpg`,
        width: 800,
        height: 600,
      },
      {
        url: `${process.env.NEXT_PUBLIC_CDN_URL || ""}/opengraph-image-v1.jpg`,
        width: 1800,
        height: 1600,
      },
    ],
    locale: "en_US",
    type: "website",
  },
};

const hedvigSans = Hedvig_Letters_Sans({
  weight: "400",
  subsets: ["latin"],
  display: "swap",
  variable: "--font-hedvig-sans",
});

const hedvigSerif = Hedvig_Letters_Serif({
  weight: "400",
  subsets: ["latin"],
  display: "swap",
  variable: "--font-hedvig-serif",
});

export const viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
  themeColor: [
    { media: "(prefers-color-scheme: light)" },
    { media: "(prefers-color-scheme: dark)" },
  ],
};

export default async function Layout({
  children,
  params,
}: {
  children: ReactElement;
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const isDesktop = await isDesktopApp();

  return (
    <html
      lang={locale}
      suppressHydrationWarning
      className={cn(isDesktop && "desktop")}
    >
      <body
        className={cn(
          `${hedvigSans.variable} ${hedvigSerif.variable} font-sans`,
          "whitespace-pre-line overscroll-none antialiased",
        )}
      >
        <DesktopHeader />

        <NuqsAdapter>
          <Providers locale={locale}>
            {children}
            <Toaster />
          </Providers>
        </NuqsAdapter>
      </body>
    </html>
  );
}
