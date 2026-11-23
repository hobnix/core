// The info rows of the package health checks (`hs sys health info`): package, check id, title, message (- when empty).
// An info row is shown on the Health page as information; it is never a problem, never counted in the badge and never sent.
export function infoRows(rows) {
  return (rows ?? [])
    .filter((r) => r && r[0])
    .map((r) => ({
      key: `${r[0]}:${r[1] ?? ''}`,
      pkg: r[0],
      title: r[2] && r[2] !== '-' ? r[2] : r[0],
      text: r[3] && r[3] !== '-' ? r[3] : '',
    }));
}
