"use client";

import { useRouter } from "next/navigation";
import type { LoginInput, RegisterInput } from "@acme/validators";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { authApi } from "~/lib/api";

/**
 * Signs in; a success stores the token, refreshes the session and opens the dashboard.
 *
 * @returns The login mutation.
 */
export function useLogin() {
  const queryClient = useQueryClient();
  const router = useRouter();

  return useMutation({
    mutationFn: (data: LoginInput) => authApi.login(data),
    onSuccess: (data) => {
      localStorage.setItem("access_token", data.access_token);
      void queryClient.invalidateQueries({ queryKey: ["session"] });
      router.push("/dashboard");
    },
  });
}

/**
 * Creates an account; a success stores the token, refreshes the session and opens the dashboard.
 *
 * @returns The register mutation.
 */
export function useRegister() {
  const queryClient = useQueryClient();
  const router = useRouter();

  return useMutation({
    mutationFn: (data: RegisterInput) => authApi.register(data),
    onSuccess: (data) => {
      localStorage.setItem("access_token", data.access_token);
      void queryClient.invalidateQueries({ queryKey: ["session"] });
      router.push("/dashboard");
    },
  });
}

/**
 * Signs out: drops the token and every cached query, then opens the login page.
 *
 * @returns A function that signs out.
 */
export function useLogout() {
  const queryClient = useQueryClient();
  const router = useRouter();

  return () => {
    localStorage.removeItem("access_token");
    queryClient.clear();
    router.push("/login");
  };
}
