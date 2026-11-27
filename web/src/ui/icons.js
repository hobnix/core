// The one list of icon names (Phosphor, without the `ph-` prefix). `Icon`, `Button icon=` and the icon-only Button take a name from here;
// tests/web-icons.sh fails when a literal name used in web/src is missing, so the list is the inventory of what the interface draws.
// Add a name here when a page needs a new one. A name built at run time must still be one of these.
export const ICONS = [
  'archive', 'arrow-bend-down-right', 'arrow-circle-up', 'arrow-clockwise', 'arrow-counter-clockwise', 'arrow-left', 'arrow-line-down',
  'arrow-right', 'arrow-square-in', 'arrow-square-out', 'arrow-u-up-left', 'arrow-up', 'arrows-clockwise', 'arrows-left-right', 'arrows-out',
  'arrows-split', 'battery-charging', 'bell', 'bell-ringing', 'binoculars', 'book-open', 'broom', 'calendar-x', 'camera', 'caret-down', 'caret-left',
  'caret-right', 'certificate', 'check', 'check-circle', 'check-square', 'circle-notch', 'clock', 'clock-clockwise', 'clock-counter-clockwise',
  'cloud', 'cloud-arrow-up', 'cloud-check', 'cloud-slash', 'cloud-warning', 'compass', 'copy', 'corners-out', 'cpu', 'cube', 'cylinder', 'database',
  'desktop-tower', 'disc', 'dots-three', 'download-simple', 'envelope-simple', 'eraser', 'fan', 'file', 'file-dashed', 'file-text', 'first-aid-kit',
  'flask', 'floppy-disk', 'folder', 'folder-dashed', 'folder-lock', 'folder-open', 'folder-plus', 'folder-simple-plus', 'folders', 'game-controller',
  'gauge', 'gear-six', 'git-branch', 'globe-hemisphere-west', 'graphics-card', 'hammer', 'hand-arrow-down', 'hand-grabbing', 'hard-drive',
  'hard-drives', 'hash', 'heartbeat', 'hourglass-medium', 'hourglass-simple-low', 'house', 'house-line', 'info', 'key', 'keyboard', 'lightning',
  'link-break', 'list', 'list-bullets', 'list-checks', 'list-magnifying-glass', 'lock', 'lock-key', 'lock-key-open', 'lock-open', 'lock-simple',
  'magic-wand', 'magnifying-glass', 'memory', 'monitor', 'network', 'package', 'password', 'pause', 'pause-circle', 'pencil-simple', 'play', 'plug',
  'plugs', 'plugs-connected', 'plus', 'power', 'prohibit', 'pulse', 'push-pin', 'puzzle-piece', 'question', 'ruler', 'scroll', 'seal-check', 'share-network',
  'shield', 'shield-check', 'shipping-container', 'sign-in', 'sign-out', 'sliders', 'sliders-horizontal', 'sparkle', 'squares-four', 'stack',
  'stack-plus', 'stethoscope', 'stop', 'storefront', 'swap', 'tag', 'terminal-window', 'thermometer', 'trash', 'trash-simple', 'tray',
  'tray-arrow-down', 'usb', 'user', 'user-plus', 'users-four', 'users-three', 'vault', 'video-camera', 'warning', 'warning-circle',
  'warning-octagon', 'wifi-slash', 'wrench', 'x',
  'chart-line', 'film-strip', 'identification-badge', 'images', 'wind',
];
const known = new Set(ICONS);
export const isIcon = (n) => known.has(n);
