import { NextResponse } from "next/server";
import { passwordRequired, safeEqual, SESSION_COOKIE, SESSION_MAX_AGE, sessionToken } from "@/lib/session";

export const runtime = "nodejs";

export async function POST(req: Request) {
  if (!passwordRequired()) return NextResponse.json({ ok: true });
  const { password } = (await req.json().catch(() => ({}))) as { password?: string };
  if (typeof password !== "string" || !safeEqual(password, process.env.APP_PASSWORD!)) {
    // Slow down guessing.
    await new Promise((r) => setTimeout(r, 1000));
    return NextResponse.json({ error: "Wrong password." }, { status: 401 });
  }
  const res = NextResponse.json({ ok: true });
  res.cookies.set(SESSION_COOKIE, await sessionToken(), {
    httpOnly: true,
    sameSite: "lax",
    // The app is usually reached over plain http on a home network / Tailscale.
    secure: new URL(req.url).protocol === "https:",
    maxAge: SESSION_MAX_AGE,
    path: "/",
  });
  return res;
}
