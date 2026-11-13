import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { generateOpenApi } from './openapi.ts';

const here = path.dirname(fileURLToPath(import.meta.url));
const target = path.resolve(here, '..', '..', '..', 'packages', 'api-contract', 'openapi.json');
mkdirSync(path.dirname(target), { recursive: true });
writeFileSync(target, await generateOpenApi());
console.log(`wrote ${target}`);
