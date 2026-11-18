// Demo mode: a few made-up guides for the Docs page (the real ones are built by `hs docs build` on a server).
export const INDEX = {
  langs: {
    en: {
      start: 'start',
      groups: [
        { name: 'First steps', pages: [{ slug: 'start', title: 'Start here', file: 'start.md' }, { slug: 'shares', title: 'Create a share', file: 'shares.md' }] },
        { name: 'Looking after the server', pages: [{ slug: 'backup', title: 'Backups and restore', file: 'backup.md' }, { slug: 'disk-replace', title: 'Replace a failed disk', file: 'disk-replace.md' }] },
      ],
    },
  },
};
const PAGES = {
  start: '# Start here\n\nThis is a demo guide: the interface shows made-up data and changes nothing.\n\n## What you see\n\nThe tree on the left lists every page of the server. Open **Storage** to see pools and disks, **Instances** for containers and apps.\n\nNot tested on hardware yet.\n',
  shares: '# Create a share\n\nA share is a folder that Windows, macOS and Linux computers on your network can open.\n\n## Steps\n\n1. Open **Storage > Shares**.\n2. Press **New share** and give it a name.\n3. Check the plan and start it.\n\nNot tested on hardware yet.\n',
  backup: '# Backups and restore\n\nThe server backs up to a disk that is not part of a pool, and optionally to a second place.\n\n## Restore one file\n\nOpen **Protection > Backup**, press **Browse**, pick a restore point and copy the file back.\n\nNot tested on hardware yet.\n',
  'disk-replace': '# Replace a failed disk\n\nWhen a pool is degraded the **Incident** page names the disk and the next safe step.\n\n## Steps\n\n1. Plug in the new disk.\n2. Open **Storage > Incident** and press **Replace the disk**.\n3. Wait until the rebuild finishes.\n\nNot tested on hardware yet.\n',
};
export const page = (slug) => PAGES[slug] ?? null;
export function search(q) {
  const w = String(q || '').toLowerCase().trim();
  if (!w) return { hits: [] };
  const titles = Object.fromEntries(INDEX.langs.en.groups.flatMap((g) => g.pages.map((p) => [p.slug, p.title])));
  return { hits: Object.entries(PAGES).filter(([, t]) => t.toLowerCase().includes(w)).map(([slug]) => ({ lang: 'en', slug, title: titles[slug], heading: titles[slug], anchor: '' })) };
}
