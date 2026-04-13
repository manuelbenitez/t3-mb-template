"use client";

import { useLogout } from "~/hooks/use-auth";
import { useCurrentUser } from "~/hooks/use-current-user";

export default function DashboardPage() {
  const { data, isLoading } = useCurrentUser();
  const logout = useLogout();

  if (isLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <p className="text-sm text-gray-500">Loading…</p>
      </div>
    );
  }

  return (
    <div className="min-h-screen p-8">
      <div className="mx-auto max-w-2xl space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold">Dashboard</h1>
            <p className="text-sm text-gray-500">
              Welcome back{data?.user.name ? `, ${data.user.name}` : ""}
            </p>
          </div>
          <button
            onClick={logout}
            className="rounded-md border px-4 py-2 text-sm hover:bg-gray-50"
          >
            Sign out
          </button>
        </div>

        <div className="space-y-2 rounded-lg border p-6">
          <h2 className="font-semibold">Your profile</h2>
          {data?.user ? (
            <dl className="space-y-1 text-sm">
              <div className="flex gap-2">
                <dt className="text-gray-500">Name</dt>
                <dd>{data.user.name}</dd>
              </div>
              <div className="flex gap-2">
                <dt className="text-gray-500">Email</dt>
                <dd>{data.user.email}</dd>
              </div>
              <div className="flex gap-2">
                <dt className="text-gray-500">Roles</dt>
                <dd>
                  {data.user.roles.length > 0
                    ? data.user.roles.join(", ")
                    : "—"}
                </dd>
              </div>
            </dl>
          ) : (
            <p className="text-sm text-gray-500">
              Not authenticated.{" "}
              <a href="/login" className="underline">
                Sign in
              </a>
            </p>
          )}
        </div>

        <div className="rounded-lg border border-dashed p-6 text-center text-sm text-gray-400">
          Your app content goes here
        </div>
      </div>
    </div>
  );
}
