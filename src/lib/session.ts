// Password protection. Set APP_PASSWORD to turn it on. The session cookie holds
// a hash derived from the password, so changing the password signs everyone out.
// Uses Web Crypto so it works in middleware (edge runtime) and in route handlers.

export const SESSION_COOKIE = "ct_session";
export const SESSION_MAX_AGE = 60 * 60 * 24 * 365; // one year

export function passwordRequired(): boolean {
  return Boolean(process.env.APP_PASSWORD);
}

export async function sessionToken(): Promise<string> {
  const data = new TextEncoder().encode(`card-tracker-session:${process.env.APP_PASSWORD ?? ""}`);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

/** Constant-time string comparison. */
export function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
