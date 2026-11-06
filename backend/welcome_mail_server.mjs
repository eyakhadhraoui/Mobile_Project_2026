import { createServer } from 'node:http';
import { randomInt } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import nodemailer from 'nodemailer';

import { createAnnoncesApi } from './annonces_api.mjs';
import { loadSecret } from './auth.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
try {
  const envText = await readFile(path.join(here, '.env'), 'utf8');
  for (const line of envText.split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (match && !process.env[match[1]]) process.env[match[1]] = match[2].replace(/^['"]|['"]$/g, '');
  }
} catch (error) { if (error.code !== 'ENOENT') throw error; }

const port = Number(process.env.PORT || 3000);
const smtpUser = process.env.GMAIL_SMTP_USER || '';
const smtpAppPassword = (process.env.GMAIL_SMTP_APP_PASSWORD || '').replace(/[\s]+/g, '');
const senderName = process.env.GMAIL_SMTP_SENDER_NAME || 'StudentHub';
const openAiApiKey = process.env.OPENAI_API_KEY || '';
const aiRequestCounts = new Map();
const mailTransport = smtpUser && smtpAppPassword ? nodemailer.createTransport({
  host: 'smtp.gmail.com', port: 465, secure: true,
  auth: { user: smtpUser, pass: smtpAppPassword }, connectionTimeout: 12000,
  greetingTimeout: 12000, socketTimeout: 12000,
}) : null;
const sendCounts = new Map();
const verificationCodes = new Map();
const hour = 60 * 60 * 1000;
const complaintDataDir = process.env.DATA_DIR ? path.resolve(process.env.DATA_DIR) : path.join(here, 'data');
const complaintDataFile = path.join(complaintDataDir, 'complaints.json');
let sharedComplaints = [];
let complaintWriteQueue = Promise.resolve();
try {
  sharedComplaints = JSON.parse(await readFile(complaintDataFile, 'utf8'));
  if (!Array.isArray(sharedComplaints)) sharedComplaints = [];
} catch (error) { if (error.code !== 'ENOENT') throw error; }
const adminEmails = new Set((process.env.ADMIN_EMAILS || '').split(',').map((email) => email.trim().toLowerCase()).filter(Boolean));
const api = await createAnnoncesApi({ dataDir: complaintDataDir, secret: await loadSecret(complaintDataDir), adminEmails });

function respond(res, status, body) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  res.end(JSON.stringify(body));
}
function persistComplaints() {
  complaintWriteQueue = complaintWriteQueue
    .catch(() => {})
    .then(async () => {
      await mkdir(complaintDataDir, { recursive: true });
      await writeFile(complaintDataFile, JSON.stringify(sharedComplaints, null, 2), 'utf8');
    });
  return complaintWriteQueue;
}
function escapeHtml(value) {
  return value.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}
async function readJson(req) {
  const chunks = []; let size = 0;
  for await (const chunk of req) { size += chunk.length; if (size > 100 * 1024) throw new Error('large'); chunks.push(chunk); }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

const server = createServer(async (req, res) => {
  if (req.method === 'GET' && req.url === '/health') return respond(res, 200, { ok: true });
  if (await api.handle(req, res)) return;
  if (req.method === 'POST' && req.url === '/chat') {
    if (!openAiApiKey) return respond(res, 503, { error: 'assistant_not_configured' });
    let data;
    try { data = await readJson(req); } catch { return respond(res, 400, { error: 'invalid_request' }); }
    if (!Array.isArray(data.messages) || data.messages.length < 1 || data.messages.length > 12) {
      return respond(res, 400, { error: 'invalid_messages' });
    }
    const messages = [];
    for (const item of data.messages) {
      if (!item || !['user', 'assistant'].includes(item.role) || typeof item.content !== 'string'
          || item.content.trim().length < 1 || item.content.length > 2000) {
        return respond(res, 400, { error: 'invalid_messages' });
      }
      messages.push({ role: item.role, content: item.content.trim() });
    }
    const last = messages.at(-1);
    if (last.role !== 'user') return respond(res, 400, { error: 'last_message_must_be_user' });
    const ip = req.socket.remoteAddress || 'unknown';
    const recent = (aiRequestCounts.get(ip) || []).filter((time) => Date.now() - time < hour);
    if (recent.length >= 30) return respond(res, 429, { error: 'rate_limited' });
    try {
      const response = await fetch('https://api.openai.com/v1/responses', {
        method: 'POST',
        headers: { authorization: `Bearer ${openAiApiKey}`, 'content-type': 'application/json' },
        body: JSON.stringify({
          model: process.env.OPENAI_MODEL || 'gpt-5.4-mini',
          store: false,
          instructions: 'Tu es l’assistant IA de StudentHub. Réponds en français, clairement et brièvement. Aide les étudiants pour les annonces, événements, réclamations, logement et l’utilisation de l’application. N’invente pas de statut ni d’information sur un compte. Si une information manque, demande-la ou indique comment contacter la résidence.',
          input: messages,
          max_output_tokens: 500,
        }),
        signal: AbortSignal.timeout(45000),
      });
      if (!response.ok) {
        console.error(`OpenAI API returned HTTP ${response.status}`);
        return respond(res, 502, { error: 'assistant_provider_error' });
      }
      const result = await response.json();
      const reply = (result.output || []).flatMap((item) => item.content || [])
        .filter((item) => item.type === 'output_text').map((item) => item.text).join('\n').trim();
      if (!reply) return respond(res, 502, { error: 'empty_assistant_reply' });
      recent.push(Date.now()); aiRequestCounts.set(ip, recent);
      return respond(res, 200, { reply });
    } catch (error) {
      console.error(`Assistant request failed: ${error instanceof Error ? error.message : 'unknown error'}`);
      return respond(res, 502, { error: 'assistant_unavailable' });
    }
  }
  if (req.method === 'GET' && req.url === '/complaints') return respond(res, 200, sharedComplaints);
  // Message d'échange d'une réclamation (réponse du propriétaire ou message de l'étudiant).
  const responseRoute = req.method === 'POST' && req.url.match(/^\/complaints\/([^/]{1,100})\/responses$/);
  if (responseRoute) {
    const complaint = sharedComplaints.find((item) => item.id === decodeURIComponent(responseRoute[1]));
    if (!complaint || complaint.deleted) return respond(res, 404, { error: 'complaint_not_found' });
    let message;
    try { message = await readJson(req); } catch { return respond(res, 400, { error: 'invalid_request' }); }
    const langues = ['fr', 'en', 'ar', 'ru', 'es', 'de', 'tr'];
    if (!message || typeof message.id !== 'string' || message.id.length < 1 || message.id.length > 100
        || typeof message.authorId !== 'string' || message.authorId.length > 100
        || !['proprietaire', 'etudiant'].includes(message.authorRole)
        || typeof message.text !== 'string' || message.text.trim().length < 1 || message.text.length > 4000
        || typeof message.createdAt !== 'string' || Number.isNaN(Date.parse(message.createdAt))) {
      return respond(res, 400, { error: 'invalid_response' });
    }
    const safe = {
      id: message.id, authorId: message.authorId, authorRole: message.authorRole, text: message.text.trim(),
      langue: langues.includes(message.langue) ? message.langue : 'fr', createdAt: message.createdAt,
      updatedAt: typeof message.updatedAt === 'string' ? message.updatedAt : null, deleted: message.deleted === true,
    };
    complaint.responses = complaint.responses || [];
    const existing = complaint.responses.findIndex((item) => item.id === safe.id);
    if (existing >= 0 && complaint.responses[existing].authorId !== safe.authorId) return respond(res, 403, { error: 'not_author' });
    if (existing < 0) complaint.responses.push(safe); else complaint.responses[existing] = safe;
    complaint.responses = complaint.responses.slice(-300);
    await persistComplaints();
    return respond(res, existing < 0 ? 201 : 200, { saved: true });
  }
  if (req.method === 'POST' && req.url === '/complaints') {
    let complaint;
    try { complaint = await readJson(req); } catch { return respond(res, 400, { error: 'invalid_request' }); }
    const required = ['id', 'userId', 'locationId', 'subject', 'category', 'description', 'status', 'createdAt'];
    if (!complaint || required.some((key) => typeof complaint[key] !== 'string' || complaint[key].trim().length === 0)
        || complaint.id.length > 100 || complaint.userId.length > 100
        || complaint.locationId.length > 240 || complaint.subject.length > 240 || complaint.description.length > 8000
        || (complaint.history != null && !Array.isArray(complaint.history))) {
      return respond(res, 400, { error: 'invalid_complaint' });
    }
    const index = sharedComplaints.findIndex((item) => item.id === complaint.id);
    const safeComplaint = {
      id: complaint.id, userId: complaint.userId, locationId: complaint.locationId,
      subject: complaint.subject, category: complaint.category, description: complaint.description,
      status: complaint.status, priority: complaint.priority || 'moyenne', createdAt: complaint.createdAt,
      history: (complaint.history || []).slice(-100), deleted: complaint.deleted === true,
      // Les échanges sont envoyés séparément (/complaints/:id/responses) : on les conserve.
      responses: index < 0 ? [] : (sharedComplaints[index].responses || []),
    };
    if (index < 0) sharedComplaints.push(safeComplaint);
    else sharedComplaints[index] = safeComplaint;
    await persistComplaints();
    return respond(res, index < 0 ? 201 : 200, { saved: true });
  }
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
    return respond(res, 200, { verified: true, verificationToken: api.emailToken(email) });
  }

  if (!mailTransport) return respond(res, 503, { error: 'mail_service_not_configured' });
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
    code = String(randomInt(100000, 1000000));
    verificationCodes.set(email.toLowerCase(), { code, expiresAt: Date.now() + 10 * 60 * 1000, attempts: (prior?.attempts || 0) + 1 });
  }
  try {
    await mailTransport.sendMail({
      from: `"${senderName}" <${smtpUser}>`, to: email,
      subject: isVerification ? 'Vérifiez votre adresse e-mail StudentHub' : 'Bienvenue chez StudentHub',
      text: isVerification ? `Bonjour ${name}, votre code de vérification StudentHub est ${code}. Il expire dans 10 minutes.` : `Bonjour ${name}, bienvenue chez StudentHub !`,
      html: isVerification
        ? `<html><body><h2>Vérifiez votre adresse e-mail</h2><p>Bonjour ${escapeHtml(name)}, votre code StudentHub est :</p><p style="font-size:28px;font-weight:bold;letter-spacing:6px">${code}</p><p>Ce code expire dans 10 minutes.</p></body></html>`
        : `<html><body><h2>Bienvenue chez StudentHub, ${escapeHtml(name)} !</h2><p>Votre compte a bien été créé.</p></body></html>`,
    });  } catch (error) {
    console.error(`Gmail SMTP send failed: ${error instanceof Error ? error.message : 'unknown network error'}`);
    return respond(res, 502, { error: 'mail_provider_unavailable' });
  }
  recent.push(Date.now()); sendCounts.set(ip, recent);
  return respond(res, 202, { sent: true });
});
server.listen(port, '0.0.0.0', () => {
  console.log(`StudentHub account mail service (Gmail SMTP) listening on port ${port}.`);
  console.log(api.moderation
    ? `Modération des annonces active (${adminEmails.size} administrateur(s) dans ADMIN_EMAILS).`
    : 'ADMIN_EMAILS vide : les annonces sont publiées sans modération.');
});
