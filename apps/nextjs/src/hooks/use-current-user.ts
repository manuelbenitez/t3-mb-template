"use client";

import { useQuery } from "@tanstack/react-query";

import { authApi } from "~/lib/api";

export function useCurrentUser() {
  return useQuery({
    queryKey: ["session"],
    queryFn: () => authApi.getSession(),
    retry: false,
    staleTime: 5 * 60 * 1000, // 5 minutes
  });
}
