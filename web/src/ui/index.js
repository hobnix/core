// The shared components of the redesign, one per job (web/design/HANDOFF.md "Shared components"). Props are documented at the top of each file.
// Phase-2 pages import from here (or from the file directly) and never hand-draw a dot, bar, banner, drawer or select.
export { default as StatusDot } from './StatusDot.svelte';
export { default as Icon } from './Icon.svelte';           // one icon by name from ui/icons.js
export { ICONS, isIcon } from './icons.js';
export { default as Chip } from './Chip.svelte';
export { default as StageBadge } from './StageBadge.svelte';
export { default as Banner } from './Banner.svelte';
export { default as EmptyState } from './EmptyState.svelte';
export { default as Skeleton } from './Skeleton.svelte';
export { default as Switch } from './Switch.svelte';          // also the checkbox: <Switch box>
export { default as Combobox } from './Combobox.svelte';
export { default as Drawer } from './Drawer.svelte';
export { default as Button } from './Button.svelte';          // every button that starts something: busy state, spinner, promise-aware
export { default as Kv } from './Kv.svelte';
export { default as Split } from './Split.svelte';
export { default as Wizard } from './Wizard.svelte';          // one question per screen: progress, back, question, children, primary button
export { default as ChoiceList } from './ChoiceList.svelte';    // radio rows: label, recommended chip, grey line
export { default as Field } from './Field.svelte';             // label, hint, error, required marker; gives its id and aria to the control inside
export { default as TextInput } from './TextInput.svelte';     // native input.input, reads the Field context
export { default as Select } from './Select.svelte';           // native select.input, options as data or <option> children
export { default as Textarea } from './Textarea.svelte';       // native textarea.input
export { default as Segmented } from './Segmented.svelte';     // 2-4 short choices as joined radio segments (ChoiceList is the explained one)
export { default as Checkbox } from './Checkbox.svelte';       // native checkbox with a clickable label (forms; Switch box is for table cells)
export { default as Slider } from './Slider.svelte';           // native range: accent-filled track, square thumb; oninput while dragging
export { default as Card } from './Card.svelte';             // the one card: title or header slot, actions, `dither` corner for the node card
export { default as Row } from './Row.svelte';               // flex row, gap from the spacing tokens
export { default as Stack } from './Stack.svelte';           // flex column, gap from the spacing tokens
export { default as Muted } from './Muted.svelte';           // the one secondary text style (not `mute`, not `muted`)
export { default as StateCard } from './StateCard.svelte';     // Group page card: status dot, one line, link
export { default as DangerZone } from './DangerZone.svelte';   // marked section of an Object page; each action opens a plan
export { default as Progress } from './Progress.svelte';       // one bar: value/total, unknown total moves, tone, text beside it
export { default as StepList } from './StepList.svelte';       // the steps of a job with a state word each; compact = the current step on one line
export { default as Timeline } from './Timeline.svelte';       // Feed body: entries newest first by day, filters above, severity word, object link, acknowledge
export { default as Stepper } from './Stepper.svelte';         // the steps of a flow with number or mark and a state word; sits under Wizard (steps prop)
// elsewhere, kept at their old paths so pages keep working:
//   shell/Table.svelte, shell/UsageBar.svelte, shell/Spark.svelte, shell/PlanDialog.svelte (opened with openPlan), forms/unlock/UnlockForm.svelte
// new in shell/: Halftone, PageHeader, PageState (loading, empty, error with stale data), PageFrame (locked, off, unreachable: the shell does it)
export { default as Tooltip } from './Tooltip.svelte';   // mounted once in App.svelte; a control asks for it: <button use:tip={'text'}>
export { tip } from './tooltip.svelte.js';
export { backdropClose } from './backdrop.js';           // read-only dialogs only: <div class="dialog-backdrop" use:backdropClose={close}>
export { default as ErrorNote } from './ErrorNote.svelte';       // coded error: code, what, why, one next step, guide link (#488)
export { default as Dialog } from './Dialog.svelte';       // modal base: backdrop, focus trap and return, Escape; CreateDialog and PlanDialog sit on it
export { default as Menu } from './Menu.svelte';           // the More menu and row actions; a disabled item says why
export { default as Toast } from './Toast.svelte';         // mounted once in the shell; fed by toast() from toast.svelte.js
export { toast, dismissToast } from './toast.svelte.js';
export { default as QuickLook } from './QuickLook.svelte'; // the Drawer as an overlay above a list
