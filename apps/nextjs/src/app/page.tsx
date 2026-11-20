import { redirect } from "next/navigation";

/** Sends the root URL to the dashboard. */
export default function Home() {
  redirect("/dashboard");
}
