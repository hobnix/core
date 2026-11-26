// What a row of `sys ct list` is and does. Plain JS (ct.js pulls in the router, which plain node cannot load).
export const isVm = (c) => /virtual|VM/i.test(c.type);
export const isRunning = (c) => /running/i.test(c.state);
