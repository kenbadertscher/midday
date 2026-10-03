import { createBrowserClient } from "@supabase/ssr";
import type { Database } from "../types";
import { AUTH_COOKIE_NAME } from "./cookie-name";

export const createClient = () => {
  return createBrowserClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookieOptions: { name: AUTH_COOKIE_NAME },
    },
  );
};
