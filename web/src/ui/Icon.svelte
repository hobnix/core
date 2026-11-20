<script>
  // One icon, by name from ui/icons.js (a Phosphor name without `ph-`). Decorative by default (aria-hidden); give `label` when the icon is the only
  // thing that tells the user something, then it is an image with that text. Colour never carries a state alone: pair an icon with a word (#487).
  //   <Icon name="lock" />   <Icon name="warning" label="Needs attention" />
  import { isIcon } from './icons.js';
  let { name, label = '', spin = false, class: extra = '' } = $props();
  if (import.meta.env?.DEV && name && !isIcon(name)) console.warn(`Icon: "${name}" is not in ui/icons.js`);
</script>

<i class="ph ph-{name} {extra}" class:spin aria-hidden={label ? undefined : 'true'} role={label ? 'img' : undefined} aria-label={label || undefined}></i>
