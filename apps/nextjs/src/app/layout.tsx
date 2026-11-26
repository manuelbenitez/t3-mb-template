import type { Metadata } from "next";
import { Providers } from "./providers";
import "./globals.css";

/** Default title and description for every page. */
export const metadata: Metadata = {
  title: "My App",
  description: "Built with t3-mb-template",
};

/**
 * The HTML shell; wraps every page in the app providers.
 *
 * @param props - The page to render, as `children`.
 * @returns The document.
 */
export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
