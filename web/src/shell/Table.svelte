<script>
  import { tip } from '../ui/tooltip.svelte.js';
  // The shared table. Columns are declared, the rows are data; a click on a header sorts by it (ascending, descending, back to the order the
  // data came in). The header sticks to the top while the page scrolls (see `.table thead th` in nocturne.css). A cell is drawn by the `cell`
  // snippet when the page gives one, else it shows the value.
  //
  //   <Table id="shares" {columns} rows={items} key="name" onrow={(r) => open(r)} selected={sel?.name} empty="No shares.">
  //     {#snippet cell(row, col)} ... {/snippet}
  //   </Table>
  //
  // column: { key, label, sort?: 'text' | 'num' | (a, b) => number | false, value?: (row) => any, align?: 'right', width?: '120px', cls?: 'name', optional?: true, wide?: true }
  //   `optional: true` = hidden on a phone (up to 860 px), so the table keeps its important columns readable.
  //   `wide: true` = shown only while the TABLE is wider than 1400 px (its own width, so the open tree counts): a long table keeps its main columns and the row
  //   buttons without sideways scrolling.
  //   `sort` defaults to 'text' ('num' for numbers: sizes, counts, dates as epoch); false = not sortable. `value` is what is compared (and shown by default).
  //   A row's empty value (null, '', '-', NaN) always sorts last, whichever way the table is sorted.
  // Optional, for a list that needs more than a click (the file manager): `onrow(row, event)` also gets the click event (modifier keys); `view` ($bindable) is
  // the rows as shown (sorted); `first(row)` keeps those rows on top in either direction; `tabrows={false}` leaves the rows out of the Tab order (the page
  // does its own keyboard); `headcell(col)` draws the header cell of a column with `head: true` (the select-all box); `draggable(row)` makes a row draggable (the page handles the drag events, rows carry data-k = the key).
  // `kids(row)` -> the rows under a row (one level; [] = none, also when the page keeps them closed): real rows with the same columns and cell snippet, indented.
  // A sort orders the top rows and the rows under each one separately (sort.js treeRows). `key` must be unique over both. `rowClass(row)` 'dimmed' greys a row.
  // `id` keeps the chosen sort for the browser session. `sort` = { key, dir: 'asc' | 'desc' } is the sort a table starts with.
  import { untrack } from 'svelte';
  import { sortRows, treeRows, nextOrder, valueOf } from './sort.js';
  import { tr } from '../i18n.js';

  let { columns, rows = [], key = null, id = '', sort = null, onrow = null, selected = null, empty = 'Nothing to show.', loading = false, cell = null, rowClass = null, compact = false, view = $bindable([]), headcell = null, first = null, tabrows = true, draggable = null, kids = null } = $props();

  const store = (v) => { try { v === undefined ? sessionStorage.removeItem('tbl:' + id) : sessionStorage.setItem('tbl:' + id, JSON.stringify(v)); } catch { /* private mode: no memory */ } };
  const stored = () => { try { return id ? JSON.parse(sessionStorage.getItem('tbl:' + id) ?? 'null') : null; } catch { return null; } };

  let order = $state(untrack(() => stored() ?? sort));   // { key, dir } or null = the order of the data

  const sorted = $derived(sortRows(rows, columns, order, first));
  $effect(() => { view = sorted; });
  const drawn = $derived(treeRows(rows, columns, order, first, kids));

  function toggle(col) {
    order = nextOrder(order, col);
    store(order ?? undefined);
  }
  // a clickable row is reachable with Tab and opens with Enter or Space (a key pressed on a button inside the row is that button's own)
  function rowkey(e, row) {
    if (!tabrows) return;
    if (e.target !== e.currentTarget || (e.key !== 'Enter' && e.key !== ' ')) return;
    e.preventDefault();
    onrow(row);
  }
  const aria = (col) => (order?.key === col.key ? (order.dir === 'asc' ? 'ascending' : 'descending') : 'none');
</script>

<div class="tablescroll" class:sized={columns.some((c) => c.wide)}>
<table class="table" class:compact>
  <thead>
    <tr>
      {#each columns as col (col.key)}
        <th class:opt={col.optional} class:wide={col.wide} style:text-align={col.align} style:width={col.width} aria-sort={col.sort === false ? undefined : aria(col)}>
          {#if col.head && headcell}
            {@render headcell(col)}
          {:else if col.sort === false || !col.label}
            {tr(col.label) ?? ''}
          {:else}
            <button class="sortbtn" class:on={order?.key === col.key} onclick={() => toggle(col)} use:tip={`${tr('Sort by')} ${tr(col.label)}`}>
              {tr(col.label)}<i class="ph ph-{order?.key === col.key ? (order.dir === 'asc' ? 'caret-up' : 'caret-down') : 'caret-up-down'}"></i>
            </button>
          {/if}
        </th>
      {/each}
    </tr>
  </thead>
  <tbody>
    {#each drawn as { row, depth }, i (key ? row[key] : i)}
      <tr class={rowClass ? rowClass(row) : ''} class:child={depth > 0} class:clickable={!!onrow} class:selected={key && selected !== null && row[key] === selected} aria-current={key && selected !== null && row[key] === selected ? 'true' : undefined}
          data-k={key ? row[key] : i} draggable={draggable ? draggable(row) : undefined}
          tabindex={onrow && tabrows ? 0 : undefined} onclick={onrow ? (e) => onrow(row, e) : null} onkeydown={onrow && tabrows ? (e) => rowkey(e, row) : null}>
        {#each columns as col (col.key)}
          <td style:text-align={col.align} class:opt={col.optional} class:wide={col.wide} class={col.cls ?? ''}>
            {#if cell}{@render cell(row, col)}{:else}{valueOf(col, row) ?? ''}{/if}
          </td>
        {/each}
      </tr>
    {:else}
      <tr class="none"><td colspan={columns.length}>{loading ? 'Loading…' : empty}</td></tr>
    {/each}
  </tbody>
</table>
</div>

<style>
  .sortbtn { all: unset; cursor: pointer; display: inline-flex; align-items: center; gap: 4px; text-transform: inherit; letter-spacing: inherit; font: inherit; color: inherit; }
  .sortbtn i { font-size: 11px; opacity: 0; transition: opacity 0.1s; }
  .sortbtn:hover i, .sortbtn.on i { opacity: 0.8; }
  .sortbtn.on { color: var(--fg); }
  .sortbtn:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
  tr.clickable { cursor: pointer; }
  /* the selected row: a tint and the accent marker on its left edge */
  tr.selected td { background: color-mix(in oklch, var(--accent) 12%, transparent); }
  tr.selected td:first-child { box-shadow: inset 2px 0 0 var(--accent); }
  tr.none td { color: var(--fg-3); font-size: 12.5px; padding: 12px; }
  tr.child td { background: var(--panel-2); }
  tr.child td:first-child { padding-left: 32px; }
  tr.dimmed td { opacity: 0.55; }
  .compact td { padding-block: 4px; }
  td { vertical-align: middle; }
  @media (max-width: 860px) { .opt { display: none; } }
  .sized { container-type: inline-size; }
  @container (max-width: 1400px) { .wide { display: none; } }
</style>
