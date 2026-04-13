"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useRouter } from "next/navigation";

import type { LoginInput, RegisterInput } from "@acme/validators";

import { authApi } from "~/lib/api";

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

export function useLogout() {
  const queryClient = useQueryClient();
  const router = useRouter();

  return () => {
    localStorage.removeItem("access_token");
    queryClient.clear();
    router.push("/login");
  };
}
