"use client";

import { useQuery } from "@tanstack/react-query";
import { authApi } from "~/lib/api";

/**
 * The signed-in user's session, fresh for five minutes and never retried.
 *
 * @returns The session query.
 */
export function useCurrentUser() {
  return useQuery({
    queryKey: ["session"],
    queryFn: () => authApi.getSession(),
    retry: false,
    staleTime: 5 * 60 * 1000,
  });
}
