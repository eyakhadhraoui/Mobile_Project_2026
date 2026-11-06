import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import path from 'node:path';

/**
 * Stockage JSON minimal : une collection = un fichier `<nom>.json` dans `dir`.
 * Les écritures sont sérialisées et passent par un fichier temporaire pour
 * éviter un fichier tronqué en cas d'arrêt pendant l'écriture.
 */
export function createStore(dir) {
  const data = new Map();
  let queue = Promise.resolve();

  async function load(name, fallback) {
    try {
      const value = JSON.parse(await readFile(path.join(dir, `${name}.json`), 'utf8'));
      data.set(name, value ?? fallback);
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      data.set(name, fallback);
    }
    return data.get(name);
  }

  function save(name) {
    const json = JSON.stringify(data.get(name), null, 2);
    queue = queue.catch(() => {}).then(async () => {
      await mkdir(dir, { recursive: true });
      const file = path.join(dir, `${name}.json`);
      const tmp = `${file}.tmp`;
      await writeFile(tmp, json, 'utf8');
      try {
        await rename(tmp, file);
      } catch {
        // Windows peut refuser le renommage si un autre programme lit le fichier.
        await writeFile(file, json, 'utf8');
      }
    });
    return queue;
  }

  return { load, save };
}
