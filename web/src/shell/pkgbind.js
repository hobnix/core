// A package update is bound to the plan that was shown: Start sends its release (--tag) and the word for what it showed (--seen, which covers
// the new permissions); the server refuses with plan.changed when either differs (scripts/pkg-change.sh). The job key stays that of the plan args.
export const boundArgs = (area, args, p) =>
  area === 'pkg' && args[0] === 'update' && p?.tag && p?.seen ? [...args, '--tag', p.tag, '--seen', p.seen] : [...args];
