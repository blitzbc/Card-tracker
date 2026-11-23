"use client";

import { useEffect, useState } from "react";

export function StatusBanner() {
  const [status, setStatus] = useState<{ claude: boolean; ebay: boolean; backup?: { enabled: boolean; lastError: string | null } } | null>(null);
  useEffect(() => {
    fetch("/api/status").then((r) => r.json()).then(setStatus).catch(() => {});
  }, []);
  const backupError = status?.backup?.enabled ? status.backup.lastError : null;
  if (!status || (status.claude && status.ebay && !backupError)) return null;
  return (
    <div className="mb-4 rounded-xl bg-warn-bg px-4 py-3 text-sm text-warn-text">
      {!status.claude && <p><b>Card identification is off.</b> Set ANTHROPIC_API_KEY in .env.local.</p>}
      {!status.ebay && <p><b>Price lookups are off.</b> Set EBAY_CLIENT_ID and EBAY_CLIENT_SECRET in .env.local.</p>}
      {backupError && <p><b>OneDrive backup failed:</b> {backupError}</p>}
    </div>
  );
}
