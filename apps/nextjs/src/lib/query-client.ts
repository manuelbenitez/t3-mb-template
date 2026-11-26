import { QueryClient } from "@tanstack/react-query";

/**
 * Creates a query client: data stays fresh for a minute, a failed query retries once.
 *
 * @returns A new client.
 */
export function makeQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: {
        staleTime: 60 * 1000,
        retry: 1,
      },
    },
  });
}

/** The browser's one client, created on first use. */
let browserQueryClient: QueryClient | undefined = undefined;

/**
 * Returns a new client per server request and one shared client per browser tab.
 *
 * @returns The client for this context.
 */
export function getQueryClient() {
  if (typeof window === "undefined") {
    return makeQueryClient();
  }
  if (!browserQueryClient) {
    browserQueryClient = makeQueryClient();
  }
  return browserQueryClient;
}
