import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
try {
  const envText = await readFile(path.join(here, '.env'), 'utf8');
  for (const line of envText.split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (match && !process.env[match[1]]) process.env[match[1]] = match[2].replace(/^['"]|['"]$/g, '');
  }
} catch (error) { if (error.code !== 'ENOENT') throw error; }

const port = Number(process.env.PORT || 3000);
const apiKey = process.env.BREVO_API_KEY || '';
const senderEmail = process.env.BREVO_SENDER_EMAIL || '';
const senderName = process.env.BREVO_SENDER_NAME || 'StudentHub';
const sendCounts = new Map();
const verificationCodes = new Map();
const hour = 60 * 60 * 1000;

function respond(res, status, body) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  res.end(JSON.stringify(body));
}
function escapeHtml(value) {
  return value.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}
async function readJson(req) {
  const chunks = []; let size = 0;
  for await (const chunk of req) { size += chunk.length; if (size > 4096) throw new Error('large'); chunks.push(chunk); }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

const server = createServer(async (req, res) => {
  if (req.method === 'GET' && req.url === '/health') return respond(res, 200, { ok: true });
  if (req.method !== 'POST' || !['/verification-email', '/verify-email', '/welcome-email'].includes(req.url)) return respond(res, 404, { error: 'not_found' });
  let data;
  try { data = await readJson(req); } catch { return respond(res, 400, { error: 'invalid_request' }); }
  const email = typeof data.email === 'string' ? data.email.trim() : '';
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return respond(res, 400, { error: 'invalid_email' });

  if (req.url === '/verify-email') {
    const saved = verificationCodes.get(email.toLowerCase());
    if (!saved || saved.expiresAt < Date.now()) return respond(res, 400, { error: 'invalid_or_expired_code' });
    if (saved.code !== String(data.code || '').trim()) {
      saved.failures = (saved.failures || 0) + 1;
      if (saved.failures >= 5) verificationCodes.delete(email.toLowerCase());
      return respond(res, 400, { error: 'invalid_or_expired_code' });
    }
    verificationCodes.delete(email.toLowerCase());
    return respond(res, 200, { verified: true });
  }

  if (!apiKey || !senderEmail) return respond(res, 503, { error: 'mail_service_not_configured' });
  const ip = req.socket.remoteAddress || 'unknown';
  const recent = (sendCounts.get(ip) || []).filter((time) => Date.now() - time < hour);
  if (recent.length >= 10) return respond(res, 429, { error: 'rate_limited' });
  const name = typeof data.firstName === 'string' ? data.firstName.trim() : '';
  if (name.length < 1 || name.length > 80) return respond(res, 400, { error: 'invalid_name' });
  const isVerification = req.url === '/verification-email';
  let code = '';
  if (isVerification) {
    const prior = verificationCodes.get(email.toLowerCase());
    if (prior?.attempts >= 5 && prior.expiresAt > Date.now()) return respond(res, 429, { error: 'too_many_codes' });
    code = String(Math.floor(100000 + Math.random() * 900000));
    verificationCodes.set(email.toLowerCase(), { code, expiresAt: Date.now() + 10 * 60 * 1000, attempts: (prior?.attempts || 0) + 1 });
  }
  try {
    const mail = await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST', headers: { accept: 'application/json', 'api-key': apiKey, 'content-type': 'application/json' },
      body: JSON.stringify({
        sender: { name: senderName, email: senderEmail }, to: [{ email, name }],
        subject: isVerification ? 'Vérifiez votre adresse e-mail StudentHub' : 'Bienvenue chez StudentHub',
        textContent: isVerification ? `Bonjour ${name}, votre code de vérification StudentHub est ${code}. Il expire dans 10 minutes.` : `Bonjour ${name}, bienvenue chez StudentHub !`,
        htmlContent: isVerification
          ? `<html><body><h2>Vérifiez votre adresse e-mail</h2><p>Bonjour ${escapeHtml(name)}, votre code StudentHub est :</p><p style="font-size:28px;font-weight:bold;letter-spacing:6px">${code}</p><p>Ce code expire dans 10 minutes.</p></body></html>`
          : `<html><body><h2>Bienvenue chez StudentHub, ${escapeHtml(name)} !</h2><p>Votre compte a bien été créé.</p></body></html>`,
      }), signal: AbortSignal.timeout(12000),
    });
    if (!mail.ok) { console.error(`Brevo rejected mail (HTTP ${mail.status}).`); return respond(res, 502, { error: 'mail_provider_rejected_request' }); }
  } catch { return respond(res, 502, { error: 'mail_provider_unavailable' }); }
  recent.push(Date.now()); sendCounts.set(ip, recent);
  return respond(res, 202, { sent: true });
});
server.listen(port, '0.0.0.0', () => console.log(`StudentHub account mail service listening on port ${port}.`));
