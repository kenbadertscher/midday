import type { Config } from "drizzle-kit";

export default {
  schema: "./src/schema.ts",
  out: "./migrations",
  dialect: "postgresql",
  // Must match the runtime clients (client.ts / worker-client.ts / job-client.ts),
  // which all set casing: "snake_case". Without it, any column that omits an
  // explicit name is CREATED camelCase but QUERIED snake_case.
  casing: "snake_case",
  dbCredentials: {
    url: process.env.DATABASE_SESSION_POOLER!,
  },
} satisfies Config;
