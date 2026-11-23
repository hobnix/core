// The block registry (#473, docs/PLAN-package-pages.md): the blocks a package page may use, each with its schema and the component that draws it.
// The data is block-registry.json, which scripts/lib/pkg_blocks.py reads as well, so `hs pkg validate` and the renderer agree. `api-level` goes up when
// a block is removed or a key changes meaning (adding a block or an optional key does not).
import registry from './block-registry.json';

export const BLOCK_API_LEVEL = registry['api-level'];
export const BLOCKS = registry.blocks;
export const blockNames = () => Object.keys(BLOCKS);
export const isKnownBlock = (type) => Object.prototype.hasOwnProperty.call(BLOCKS, type);
