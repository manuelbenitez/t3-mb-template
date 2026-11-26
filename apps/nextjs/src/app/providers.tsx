"use client";

import { QueryClientProvider } from "@tanstack/react-query";
import { getQueryClient } from "~/lib/query-client";

/**
 * Client-side providers every page shares: the TanStack Query client.
 *
 * @param props - The tree to wrap, as `children`.
 * @returns The wrapped tree.
 */
export function Providers({ children }: { children: React.ReactNode }) {
  const queryClient = getQueryClient();

  return (
    <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  );
}
