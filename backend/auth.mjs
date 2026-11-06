import { createHmac, randomBytes, scrypt as scryptCallback, timingSafeEqual } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { promisify } from 'node:util';

const scrypt = promisify(scryptCallback);

/** Secret de signature : AUTH_SECRET dans .env, sinon généré une fois et conservé dans data/. */
export async function loadSecret(dataDir) {
  if (process.env.AUTH_SECRET && process.env.AUTH_SECRET.length >= 32) return process.env.AUTH_SECRET;
  const file = path.join(dataDir, 'auth_secret.txt');
  try {
    const saved = (await readFile(file, 'utf8')).trim();
    if (saved.length >= 32) return saved;
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  const secret = randomBytes(48).toString('base64url');
  await mkdir(dataDir, { recursive: true });
  await writeFile(file, secret, 'utf8');
  return secret;
}

export function signToken(payload, secret) {
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const signature = createHmac('sha256', secret).update(body).digest('base64url');
  return `${body}.${signature}`;
}

/** Retourne le contenu du jeton s'il est authentique, du bon type et non expiré, sinon null. */
export function verifyToken(token, secret, type) {
  if (typeof token !== 'string' || token.length > 4096) return null;
  const [body, signature, extra] = token.split('.');
  if (!body || !signature || extra !== undefined) return null;
  const expected = createHmac('sha256', secret).update(body).digest();
  let given;
  try { given = Buffer.from(signature, 'base64url'); } catch { return null; }
  if (given.length !== expected.length || !timingSafeEqual(given, expected)) return null;
  let payload;
  try { payload = JSON.parse(Buffer.from(body, 'base64url').toString('utf8')); } catch { return null; }
  if (!payload || payload.typ !== type || typeof payload.exp !== 'number' || payload.exp < Date.now()) return null;
  return payload;
}

export async function hashPassword(password) {
  const salt = randomBytes(16);
  const key = await scrypt(password, salt, 64);
  return `scrypt:${salt.toString('base64')}:${key.toString('base64')}`;
}

export async function checkPassword(password, stored) {
  const [scheme, saltText, keyText] = String(stored || '').split(':');
  if (scheme !== 'scrypt' || !saltText || !keyText) return false;
  const expected = Buffer.from(keyText, 'base64');
  const actual = await scrypt(password, Buffer.from(saltText, 'base64'), expected.length);
  return timingSafeEqual(actual, expected);
}
