import { compose } from './compose.ts';

// `--volumes` is opt-in so local data survives a normal stop.
const removeData = process.argv.includes('--volumes');
await compose('down', ...(removeData ? ['--volumes'] : []));
console.log(removeData ? 'Stack stopped and data volumes removed.' : 'Stack stopped (data kept).');
