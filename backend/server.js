const express = require('express');
const fs = require('fs/promises');
const path = require('path');
const { createClient } = require('@supabase/supabase-js');
const rateLimit = require('express-rate-limit');
const twilio = require('twilio');
require('dotenv').config();

const app = express();
app.use(express.json({ limit: '16kb' }));

app.get('/health', (_req, res) => {
  res.json({ ok: true });
});

function requireEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

const supabase = createClient(
  requireEnv('SUPABASE_URL'),
  requireEnv('SUPABASE_SERVICE_ROLE_KEY')
);

function getTwilioConfig() {
  const accountSid = getOptionalEnv('TWILIO_ACCOUNT_SID');
  const authToken = getOptionalEnv('TWILIO_AUTH_TOKEN');
  const from = getOptionalEnv('TWILIO_FROM');

  if (!accountSid || !authToken || !from) {
    return null;
  }

  return {
    client: twilio(accountSid, authToken),
    from,
  };
}

const smsAnnouncementLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many announcement attempts. Please try again later.' },
});

const auditIngestLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 120,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many audit events. Please try again later.' },
});

function getOptionalEnv(name) {
  const value = process.env[name];
  return typeof value === 'string' ? value.trim() : '';
}

function getBearerToken(req) {
  const auth = req.headers.authorization || '';
  if (!auth.startsWith('Bearer ')) return null;
  return auth.slice(7).trim();
}

function sanitizeText(value, { maxLength = 255 } = {}) {
  if (typeof value !== 'string') return '';
  return value.replace(/[<>]/g, '').replace(/\s+/g, ' ').trim().slice(0, maxLength);
}

function sanitizeEmail(value) {
  return sanitizeText(value, { maxLength: 120 }).toLowerCase();
}

function validateEmail(email) {
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email);
}

function validatePassword(password) {
  return typeof password === 'string' && password.length >= 8 && password.length <= 72;
}

const LONG_BAN_DURATION = '876000h';
const SYSTEM_STATE_FILE = path.join(__dirname, 'data', 'system-state.json');
const DEFAULT_SYSTEM_STATE = {
  maintenance_mode: false,
  maintenance_message:
    'Dayung is temporarily unavailable for maintenance. Please try again later.',
  allow_sms_broadcast: false,
  force_password_change_on_create: true,
  force_password_change_on_reset: true,
  updated_at: null,
  updated_by: null,
};
const UNIT_ROLE_COLUMNS = {
  president: 'president_id',
  secretary: 'secretary_id',
  treasurer: 'treasurer_id',
};

function sanitizeMultilineText(value, { maxLength = 800 } = {}) {
  if (typeof value !== 'string') return '';
  return value
    .replace(/[<>]/g, '')
    .replace(/\r/g, '')
    .trim()
    .slice(0, maxLength);
}

function encodeAuditValue(value) {
  return encodeURIComponent(String(value).trim().slice(0, 160));
}

function buildAuditAction(eventName, fields = {}) {
  const safeEventName = sanitizeText(eventName, { maxLength: 80 })
    .replace(/\s+/g, '_')
    .toUpperCase();

  const segments = [safeEventName || 'EVENT'];
  for (const [key, value] of Object.entries(fields)) {
    if (value === undefined || value === null || value === '') continue;
    segments.push(`${sanitizeText(key, { maxLength: 40 }).toLowerCase()}=${encodeAuditValue(value)}`);
  }
  return segments.join(' | ');
}

const PUBLIC_AUDIT_EVENTS = new Set([
  'LOGIN_ATTEMPT_STARTED',
  'LOGIN_ATTEMPT_FAILED',
  'ACCESS_VIOLATION',
  'SYSTEM_ERROR',
]);

const AUTHENTICATED_AUDIT_PREFIXES = [
  'LOGIN_',
  'SYSTEM_ERROR',
  'ACCESS_',
  'USER_ACTIVITY_',
  'PASSWORD_CHANGED_ON_FIRST_SIGN_IN',
  'ACCOUNT_',
  'UNIT_',
  'BROADCAST_',
  'SYSTEM_SETTINGS_',
];

function isAuditEventAllowed(eventName, isAuthenticated) {
  if (!eventName) return false;
  if (isAuthenticated) {
    return AUTHENTICATED_AUDIT_PREFIXES.some((prefix) => eventName.startsWith(prefix));
  }
  return PUBLIC_AUDIT_EVENTS.has(eventName);
}

async function resolveOptionalUserFromToken(req) {
  const token = getBearerToken(req);
  if (!token) return null;
  try {
    const { data, error } = await supabase.auth.getUser(token);
    if (error) return null;
    return data?.user ?? null;
  } catch (_error) {
    return null;
  }
}

function humanizeAuditEvent(eventName) {
  return eventName
    .toLowerCase()
    .split('_')
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');
}

function parseAuditAction(action) {
  const raw = typeof action === 'string' ? action.trim() : '';
  if (!raw) {
    return {
      raw_action: '',
      category: 'General',
      title: 'General activity',
      details: [],
      fields: {},
    };
  }

  const parts = raw.split('|').map((part) => part.trim()).filter(Boolean);
  const eventToken = parts[0] || raw;
  const structured = /^[A-Z0-9_]+$/.test(eventToken);
  const fields = {};
  const details = [];

  for (const part of parts.slice(1)) {
    const eqIndex = part.indexOf('=');
    if (eqIndex <= 0) {
      details.push(part);
      continue;
    }

    const key = part.slice(0, eqIndex).trim().toLowerCase();
    const value = decodeURIComponent(part.slice(eqIndex + 1).trim());
    fields[key] = value;
  }

  if (!structured) {
    return {
      raw_action: raw,
      category: 'General',
      title: raw,
      details,
      fields,
    };
  }

  return {
    raw_action: raw,
    event_name: eventToken,
    category: humanizeAuditEvent(eventToken),
    title: humanizeAuditEvent(eventToken),
    details,
    fields,
  };
}

async function readSystemState() {
  try {
    const raw = await fs.readFile(SYSTEM_STATE_FILE, 'utf8');
    const parsed = JSON.parse(raw);
    return {
      ...DEFAULT_SYSTEM_STATE,
      ...(parsed && typeof parsed === 'object' ? parsed : {}),
    };
  } catch (error) {
    if (error && error.code !== 'ENOENT') {
      console.error('Failed to read system state', error);
    }
    return { ...DEFAULT_SYSTEM_STATE };
  }
}

async function writeSystemState(nextState) {
  await fs.mkdir(path.dirname(SYSTEM_STATE_FILE), { recursive: true });
  await fs.writeFile(SYSTEM_STATE_FILE, JSON.stringify(nextState, null, 2));
}

function getMonthKey(value) {
  const parsed = Date.parse(value || '');
  if (Number.isNaN(parsed)) return null;
  const date = new Date(parsed);
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}`;
}

function buildMonthSeries(monthsBack, values, { amount = false } = {}) {
  const now = new Date();
  const buckets = [];
  const bucketMap = new Map();

  for (let offset = monthsBack - 1; offset >= 0; offset -= 1) {
    const date = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - offset, 1));
    const key = `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}`;
    const item = { month: key, value: 0 };
    buckets.push(item);
    bucketMap.set(key, item);
  }

  for (const entry of values) {
    const key = getMonthKey(entry.date);
    if (!key || !bucketMap.has(key)) continue;
    bucketMap.get(key).value += amount ? Number(entry.value) || 0 : 1;
  }

  return buckets.map((bucket) => ({
    month: bucket.month,
    value: amount ? Number(bucket.value.toFixed(2)) : bucket.value,
  }));
}

function chunkArray(items, size) {
  const chunks = [];
  for (let index = 0; index < items.length; index += size) {
    chunks.push(items.slice(index, index + size));
  }
  return chunks;
}

async function loadUnitParticipantIds(dayungUnitId) {
  const participantIds = new Set();

  const [{ data: unit, error: unitError }, { data: collectors, error: collectorsError }, { data: apps, error: appsError }] =
    await Promise.all([
      supabase
        .from('dayung_units')
        .select('president_id, secretary_id, treasurer_id')
        .eq('id', dayungUnitId)
        .maybeSingle(),
      supabase
        .from('dayung_collectors')
        .select('user_id')
        .eq('dayung_unit_id', dayungUnitId),
      supabase
        .from('applications')
        .select('user_id')
        .eq('dayung_unit_id', dayungUnitId)
        .eq('status', 'approved'),
    ]);

  if (unitError) throw unitError;
  if (collectorsError) throw collectorsError;
  if (appsError) throw appsError;

  if (unit) {
    [unit.president_id, unit.secretary_id, unit.treasurer_id].filter(Boolean).forEach((id) => participantIds.add(id));
  }

  for (const collector of collectors || []) {
    if (collector.user_id) participantIds.add(collector.user_id);
  }

  for (const appRow of apps || []) {
    if (appRow.user_id) participantIds.add(appRow.user_id);
  }

  return participantIds;
}

async function buildReportsModel() {
  const [authUsers, publicUsersResponse, applicationsResponse, unitsResponse, collectorsResponse, paymentsResponse, notificationsResponse, auditLogsResponse] =
    await Promise.all([
      getAllAuthUsers(),
      supabase.from('users').select('id, role, is_deceased'),
      supabase.from('applications').select('user_id, dayung_unit_id, status, approved_at'),
      supabase.from('dayung_units').select('id, name, president_id, secretary_id, treasurer_id'),
      supabase.from('dayung_collectors').select('user_id, dayung_unit_id'),
      supabase.from('payments').select('amount, status, paid_at'),
      supabase.from('notifications').select('created_at'),
      supabase.from('audit_logs').select('created_at'),
    ]);

  if (publicUsersResponse.error) throw publicUsersResponse.error;
  if (applicationsResponse.error) throw applicationsResponse.error;
  if (unitsResponse.error) throw unitsResponse.error;
  if (collectorsResponse.error) throw collectorsResponse.error;
  if (paymentsResponse.error) throw paymentsResponse.error;
  if (notificationsResponse.error) throw notificationsResponse.error;
  if (auditLogsResponse.error) throw auditLogsResponse.error;

  const publicUsers = Array.isArray(publicUsersResponse.data) ? publicUsersResponse.data : [];
  const applications = Array.isArray(applicationsResponse.data) ? applicationsResponse.data : [];
  const units = Array.isArray(unitsResponse.data) ? unitsResponse.data : [];
  const collectors = Array.isArray(collectorsResponse.data) ? collectorsResponse.data : [];
  const payments = Array.isArray(paymentsResponse.data) ? paymentsResponse.data : [];
  const notifications = Array.isArray(notificationsResponse.data) ? notificationsResponse.data : [];
  const auditLogs = Array.isArray(auditLogsResponse.data) ? auditLogsResponse.data : [];

  const disabledIds = new Set(authUsers.filter(isAuthUserDisabled).map((user) => user.id));
  const approvedApplications = applications.filter((row) => row.status === 'approved');
  const approvedMemberIds = new Set(approvedApplications.map((row) => row.user_id).filter(Boolean));
  const officerIds = new Set();
  const unitMemberCounts = new Map();
  const unitNameById = new Map(units.map((unit) => [unit.id, unit.name || `Unit ${unit.id}`]));

  for (const unit of units) {
    [unit.president_id, unit.secretary_id, unit.treasurer_id].filter(Boolean).forEach((id) => officerIds.add(id));
  }

  for (const collector of collectors) {
    if (collector.user_id) {
      officerIds.add(collector.user_id);
    }
  }

  for (const appRow of approvedApplications) {
    if (!appRow.dayung_unit_id) continue;
    unitMemberCounts.set(appRow.dayung_unit_id, (unitMemberCounts.get(appRow.dayung_unit_id) || 0) + 1);
  }

  const paidRows = payments.filter((row) => String(row.status).toLowerCase() === 'paid');
  const now = Date.now();
  const thirtyDaysAgo = now - 30 * 24 * 60 * 60 * 1000;

  return {
    generated_at: new Date().toISOString(),
    summary: {
      total_users: publicUsers.length,
      active_users: publicUsers.filter((user) => !disabledIds.has(user.id) && user.is_deceased !== true).length,
      disabled_users: publicUsers.filter((user) => disabledIds.has(user.id)).length,
      deceased_users: publicUsers.filter((user) => user.is_deceased === true).length,
      superadmins: publicUsers.filter((user) => user.role === 'superadmin').length,
      officers: officerIds.size,
      approved_members: approvedMemberIds.size,
      pending_applications: applications.filter((row) => row.status === 'pending').length,
      dayung_units: units.length,
      paid_transactions: paidRows.length,
      paid_total: Number(
        paidRows.reduce((sum, row) => sum + (Number(row.amount) || 0), 0).toFixed(2)
      ),
      notifications_last_30_days: notifications.filter((row) => Date.parse(row.created_at || '') >= thirtyDaysAgo).length,
      audit_logs_last_30_days: auditLogs.filter((row) => Date.parse(row.created_at || '') >= thirtyDaysAgo).length,
    },
    monthly_users: buildMonthSeries(
      6,
      authUsers.map((user) => ({ date: user.created_at })),
    ),
    monthly_approvals: buildMonthSeries(
      6,
      approvedApplications.map((row) => ({ date: row.approved_at })),
    ),
    monthly_revenue: buildMonthSeries(
      6,
      paidRows.map((row) => ({ date: row.paid_at, value: row.amount })),
      { amount: true },
    ),
    role_breakdown: {
      superadmins: publicUsers.filter((user) => user.role === 'superadmin').length,
      officers: officerIds.size,
      members: approvedMemberIds.size,
      disabled: publicUsers.filter((user) => disabledIds.has(user.id)).length,
    },
    top_units: [...unitMemberCounts.entries()]
      .sort((left, right) => right[1] - left[1])
      .slice(0, 5)
      .map(([unitId, count]) => ({
        dayung_unit_id: unitId,
        name: unitNameById.get(unitId) || `Unit ${unitId}`,
        members: count,
      })),
  };
}

async function resolveBroadcastRecipients({ audience, dayungUnitId }) {
  const [authUsers, publicUsersResponse, approvedAppsResponse, unitsResponse, collectorsResponse] = await Promise.all([
    getAllAuthUsers(),
    supabase.from('users').select('id, full_name, email, role, mobile_number, is_deceased'),
    supabase.from('applications').select('user_id, dayung_unit_id, status').eq('status', 'approved'),
    supabase.from('dayung_units').select('id, president_id, secretary_id, treasurer_id'),
    supabase.from('dayung_collectors').select('user_id, dayung_unit_id'),
  ]);

  if (publicUsersResponse.error) throw publicUsersResponse.error;
  if (approvedAppsResponse.error) throw approvedAppsResponse.error;
  if (unitsResponse.error) throw unitsResponse.error;
  if (collectorsResponse.error) throw collectorsResponse.error;

  const publicUsers = Array.isArray(publicUsersResponse.data) ? publicUsersResponse.data : [];
  const approvedApps = Array.isArray(approvedAppsResponse.data) ? approvedAppsResponse.data : [];
  const units = Array.isArray(unitsResponse.data) ? unitsResponse.data : [];
  const collectors = Array.isArray(collectorsResponse.data) ? collectorsResponse.data : [];
  const disabledIds = new Set(authUsers.filter(isAuthUserDisabled).map((user) => user.id));
  const publicUserById = new Map(publicUsers.map((user) => [user.id, user]));
  const officerIds = new Set();

  for (const unit of units) {
    [unit.president_id, unit.secretary_id, unit.treasurer_id].filter(Boolean).forEach((id) => officerIds.add(id));
  }
  for (const collector of collectors) {
    if (collector.user_id) officerIds.add(collector.user_id);
  }

  let recipientIds = new Set();
  let audienceLabel = audience;

  if (audience === 'all_active') {
    if (dayungUnitId) {
      recipientIds = await loadUnitParticipantIds(dayungUnitId);
      audienceLabel = `Active users in unit ${dayungUnitId}`;
    } else {
      recipientIds = new Set(publicUsers.map((user) => user.id));
      audienceLabel = 'All active users';
    }
  } else if (audience === 'members') {
    const filtered = approvedApps.filter((row) => !dayungUnitId || row.dayung_unit_id === dayungUnitId);
    recipientIds = new Set(filtered.map((row) => row.user_id).filter(Boolean));
    audienceLabel = dayungUnitId ? `Approved members in unit ${dayungUnitId}` : 'All approved members';
  } else if (audience === 'officers') {
    if (dayungUnitId) {
      const unitParticipants = await loadUnitParticipantIds(dayungUnitId);
      recipientIds = new Set([...unitParticipants].filter((id) => officerIds.has(id)));
      audienceLabel = `Officers in unit ${dayungUnitId}`;
    } else {
      recipientIds = officerIds;
      audienceLabel = 'All officers';
    }
  } else if (audience === 'superadmins') {
    recipientIds = new Set(publicUsers.filter((user) => user.role === 'superadmin').map((user) => user.id));
    audienceLabel = 'All superadmins';
  } else if (audience === 'inactive') {
    recipientIds = new Set([...disabledIds]);
    if (dayungUnitId) {
      const unitParticipants = await loadUnitParticipantIds(dayungUnitId);
      recipientIds = new Set([...recipientIds].filter((id) => unitParticipants.has(id)));
      audienceLabel = `Inactive users in unit ${dayungUnitId}`;
    } else {
      audienceLabel = 'All inactive users';
    }
  } else {
    throw new Error('Unsupported audience');
  }

  const recipients = [...recipientIds]
    .map((id) => publicUserById.get(id))
    .filter(Boolean)
    .filter((user) => user.is_deceased !== true)
    .filter((user) => (audience === 'inactive' ? true : !disabledIds.has(user.id)));

  return { recipients, audienceLabel };
}

async function insertAuditLog(userId, actionOrEvent, fields = null) {
  const action = fields && typeof fields === 'object'
    ? buildAuditAction(actionOrEvent, fields)
    : actionOrEvent;

  try {
    await supabase.from('audit_logs').insert({
      user_id: userId,
      action,
      created_at: new Date().toISOString(),
    });
  } catch (error) {
    console.error('Failed to insert audit log', error);
  }
}

app.post('/audit/ingest', auditIngestLimiter, async (req, res) => {
  try {
    const eventName = sanitizeText(req.body?.event_name, { maxLength: 80 })
      .replace(/\s+/g, '_')
      .toUpperCase();
    const fields = req.body?.fields && typeof req.body.fields === 'object'
      ? req.body.fields
      : {};
    const user = await resolveOptionalUserFromToken(req);

    if (!isAuditEventAllowed(eventName, !!user)) {
      return res.status(403).json({ error: 'Audit event is not allowed.' });
    }

    await insertAuditLog(user?.id ?? null, eventName, fields);
    return res.json({ success: true });
  } catch (error) {
    console.error('Failed to ingest audit event', error);
    return res.status(500).json({ error: 'Failed to ingest audit event' });
  }
});

async function getAllAuthUsers() {
  const users = [];
  let page = 1;
  const perPage = 200;

  while (true) {
    const { data, error } = await supabase.auth.admin.listUsers({
      page,
      perPage,
    });

    if (error) {
      throw error;
    }

    const batch = data?.users || [];
    users.push(...batch);

    if (!data?.nextPage || batch.length < perPage) {
      break;
    }

    page = data.nextPage;
  }

  return users;
}

function isAuthUserDisabled(authUser) {
  if (!authUser?.banned_until) return false;
  const bannedUntil = Date.parse(authUser.banned_until);
  return !Number.isNaN(bannedUntil) && bannedUntil > Date.now();
}

async function getPublicUserById(userId) {
  const { data, error } = await supabase
    .from('users')
    .select('id, full_name, email, role, is_deceased, created_at')
    .eq('id', userId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  return data;
}

async function ensureSuperAdminCanBeModified(targetUserId, disableRequested) {
  const targetUser = await getPublicUserById(targetUserId);
  if (!targetUser || targetUser.role !== 'superadmin' || !disableRequested) {
    return { ok: true, targetUser };
  }

  const { data: superAdmins, error } = await supabase
    .from('users')
    .select('id')
    .eq('role', 'superadmin');

  if (error) {
    throw error;
  }

  const totalSuperAdmins = Array.isArray(superAdmins) ? superAdmins.length : 0;
  if (totalSuperAdmins <= 1) {
    return {
      ok: false,
      targetUser,
      error: 'You cannot disable the last superadmin account.',
    };
  }

  return { ok: true, targetUser };
}

async function requireAuthenticatedUser(req, res, next) {
  try {
    const token = getBearerToken(req);
    if (!token) {
      return res.status(401).json({ error: 'Missing bearer token' });
    }

    const {
      data: { user },
      error,
    } = await supabase.auth.getUser(token);

    if (error || !user) {
      return res.status(401).json({ error: 'Invalid token' });
    }

    req.user = user;
    next();
  } catch (_) {
    return res.status(401).json({ error: 'Authentication failed' });
  }
}

async function requireSuperAdmin(req, res, next) {
  try {
    const { data: userRow, error } = await supabase
      .from('users')
      .select('id, role, email, full_name')
      .eq('id', req.user.id)
      .maybeSingle();

    if (error) {
      console.error('Failed to load requesting user', error);
      return res.status(500).json({ error: 'Failed to load requesting user' });
    }

    if (!userRow || userRow.role !== 'superadmin') {
      return res.status(403).json({ error: 'Forbidden' });
    }

    req.requestingUserRow = userRow;
    next();
  } catch (err) {
    console.error('Superadmin authorization failed', err);
    return res.status(403).json({ error: 'Authorization failed' });
  }
}

async function requirePresidentOfUnit(req, res, next) {
  try {
    const dayungUnitId = Number(req.body.dayung_unit_id);
    if (!Number.isInteger(dayungUnitId) || dayungUnitId <= 0) {
      return res.status(400).json({ error: 'Invalid dayung_unit_id' });
    }

    const { data: unit, error } = await supabase
      .from('dayung_units')
      .select('id, president_id')
      .eq('id', dayungUnitId)
      .maybeSingle();

    if (error || !unit) {
      return res.status(404).json({ error: 'Unit not found' });
    }

    if (unit.president_id !== req.user.id) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    req.dayungUnitId = dayungUnitId;
    next();
  } catch (_) {
    return res.status(403).json({ error: 'Authorization failed' });
  }
}

app.get('/system/runtime', async (_req, res) => {
  try {
    const state = await readSystemState();
    return res.json({
      maintenance_mode: state.maintenance_mode === true,
      maintenance_message: state.maintenance_message,
    });
  } catch (error) {
    console.error('Failed to load runtime system state', error);
    return res.status(500).json({ error: 'Failed to load system state' });
  }
});

app.post(
  '/superadmin/create-user',
  requireAuthenticatedUser,
  requireSuperAdmin,
  async (req, res) => {
    let createdAuthUserId = null;

    try {
      const fullName = sanitizeText(req.body.full_name, { maxLength: 120 });
      const email = sanitizeEmail(req.body.email);
      const password = req.body.password;
      const requestedRole = sanitizeText(req.body.role || 'member', {
        maxLength: 40,
      }).toLowerCase();
      const systemState = await readSystemState();

      if (fullName.length < 2) {
        return res.status(400).json({ error: 'Full name is too short' });
      }

      if (!validateEmail(email)) {
        return res.status(400).json({ error: 'Enter a valid email address' });
      }

      if (!validatePassword(password)) {
        return res.status(400).json({ error: 'Password must be 8 to 72 characters long' });
      }

      if (!['member', 'superadmin'].includes(requestedRole)) {
        return res.status(400).json({
          error:
            'Only member and superadmin accounts can be created here. Officer roles must be assigned from unit-role management.',
        });
      }

      const { data: existingUser, error: existingUserError } = await supabase
        .from('users')
        .select('id')
        .eq('email', email)
        .maybeSingle();

      if (existingUserError) {
        console.error('Failed to check existing user email', existingUserError);
        return res.status(500).json({ error: 'Failed to validate user email' });
      }

      if (existingUser) {
        return res.status(409).json({ error: 'An account with that email already exists' });
      }

      const { data: createdAuth, error: createAuthError } = await supabase.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: {
          role: requestedRole,
          full_name: fullName,
          force_password_change: systemState.force_password_change_on_create === true,
        },
      });

      if (createAuthError || !createdAuth?.user) {
        console.error('Failed to create auth user', createAuthError);
        return res.status(400).json({
          error: createAuthError?.message || 'Failed to create auth user',
        });
      }

      createdAuthUserId = createdAuth.user.id;

      const { error: insertUserError } = await supabase.from('users').insert({
        id: createdAuth.user.id,
        full_name: fullName,
        email,
        role: requestedRole,
        is_deceased: false,
      });

      if (insertUserError) {
        console.error('Failed to create public user row', insertUserError);
        await supabase.auth.admin.deleteUser(createdAuth.user.id);
        return res.status(500).json({ error: 'Failed to create public user row' });
      }

      await insertAuditLog(req.user.id, 'ACCOUNT_CREATED', {
        target: email,
        role: requestedRole,
        force_password_change: systemState.force_password_change_on_create === true,
      });

      return res.status(201).json({
        user: {
          id: createdAuth.user.id,
          full_name: fullName,
          email,
          role: requestedRole,
          is_deceased: false,
        },
        requires_password_change: systemState.force_password_change_on_create === true,
      });
    } catch (err) {
      console.error('Unhandled error in /superadmin/create-user', err);

      if (createdAuthUserId) {
        try {
          await supabase.auth.admin.deleteUser(createdAuthUserId);
        } catch (rollbackErr) {
          console.error('Failed to roll back auth user after error', rollbackErr);
        }
      }

      return res.status(500).json({ error: 'Internal server error' });
    }
  }
);

app.get(
  '/superadmin/users',
  requireAuthenticatedUser,
  requireSuperAdmin,
  async (req, res) => {
    try {
      const authUsers = await getAllAuthUsers();
      const { data: publicUsers, error: publicUsersError } = await supabase
        .from('users')
        .select('id, full_name, email, role, is_deceased, created_at')
        .order('full_name', { ascending: true });

      if (publicUsersError) {
        throw publicUsersError;
      }

      const usersRows = Array.isArray(publicUsers) ? publicUsers : [];
      const authById = new Map(authUsers.map((user) => [user.id, user]));

      const users = usersRows.map((user) => {
        const authUser = authById.get(user.id);
        return {
          ...user,
          is_disabled: isAuthUserDisabled(authUser),
          banned_until: authUser?.banned_until || null,
          email_confirmed_at: authUser?.email_confirmed_at || null,
        };
      });

      return res.json({ users });
    } catch (error) {
      console.error('Failed to fetch superadmin users', error);
      return res.status(500).json({ error: 'Failed to fetch users' });
    }
  }
);

app.post(
  '/superadmin/reset-user-password',
  requireAuthenticatedUser,
  requireSuperAdmin,
  async (req, res) => {
    try {
      const userId = sanitizeText(req.body.user_id, { maxLength: 80 });
      const password = req.body.password;

      if (!userId) {
        return res.status(400).json({ error: 'Missing user_id' });
      }

      if (!validatePassword(password)) {
        return res.status(400).json({ error: 'Password must be 8 to 72 characters long' });
      }

      const targetUser = await getPublicUserById(userId);
      if (!targetUser) {
        return res.status(404).json({ error: 'User not found' });
      }

      const systemState = await readSystemState();
      const { data: authLookup, error: authLookupError } = await supabase.auth.admin.getUserById(userId);
      if (authLookupError) {
        console.error('Failed to load auth user for password reset', authLookupError);
        return res.status(500).json({ error: 'Failed to load auth user' });
      }

      const currentMetadata = {
        ...(authLookup?.user?.user_metadata || {}),
      };

      const { error } = await supabase.auth.admin.updateUserById(userId, {
        password,
        user_metadata: {
          ...currentMetadata,
          force_password_change: systemState.force_password_change_on_reset === true,
        },
      });

      if (error) {
        console.error('Failed to reset password', error);
        return res.status(400).json({ error: error.message || 'Failed to reset password' });
      }

      await insertAuditLog(req.user.id, 'ACCOUNT_PASSWORD_RESET', {
        target: targetUser.email || userId,
        force_password_change: systemState.force_password_change_on_reset === true,
      });
      return res.json({
        success: true,
        requires_password_change: systemState.force_password_change_on_reset === true,
      });
    } catch (error) {
      console.error('Failed to reset user password', error);
      return res.status(500).json({ error: 'Failed to reset password' });
    }
  }
);

app.post(
  '/superadmin/set-user-disabled',
  requireAuthenticatedUser,
  requireSuperAdmin,
  async (req, res) => {
    try {
      const userId = sanitizeText(req.body.user_id, { maxLength: 80 });
      const disabled = req.body.disabled === true;

      if (!userId) {
        return res.status(400).json({ error: 'Missing user_id' });
      }

      if (userId === req.user.id && disabled) {
        return res.status(400).json({ error: 'You cannot disable your own active session.' });
      }

      const check = await ensureSuperAdminCanBeModified(userId, disabled);
      if (!check.ok) {
        return res.status(400).json({ error: check.error });
      }

      if (!check.targetUser) {
        return res.status(404).json({ error: 'User not found' });
      }

      const { error } = await supabase.auth.admin.updateUserById(userId, {
        ban_duration: disabled ? LONG_BAN_DURATION : 'none',
      });

      if (error) {
        console.error('Failed to update disabled status', error);
        return res.status(400).json({ error: error.message || 'Failed to update account status' });
      }

      await insertAuditLog(req.user.id, disabled ? 'ACCOUNT_DISABLED' : 'ACCOUNT_REACTIVATED', {
        target: check.targetUser.email || userId,
      });

      return res.json({ success: true, disabled });
    } catch (error) {
      console.error('Failed to update user disabled status', error);
      return res.status(500).json({ error: 'Failed to update account status' });
    }
  }
);

app.post(
  '/superadmin/confirm-application',
  requireAuthenticatedUser,
  requireSuperAdmin,
  async (req, res) => {
    try {
      const userId = sanitizeText(req.body.user_id, { maxLength: 80 });
      const appliedAt = sanitizeText(req.body.applied_at, { maxLength: 120 });
      const approvedAt = sanitizeText(req.body.approved_at, { maxLength: 120 });

      if (!userId) {
        return res.status(400).json({ error: 'Missing user_id' });
      }
      if (!appliedAt || !approvedAt) {
        return res.status(400).json({ error: 'Missing timestamps' });
      }

      const targetUser = await getPublicUserById(userId);
      if (!targetUser) {
        return res.status(404).json({ error: 'User not found' });
      }

      const { error } = await supabase.from('applications').insert({
        user_id: userId,
        status: 'approved',
        applied_at: appliedAt,
        approved_at: approvedAt,
      });

      if (error) {
        console.error('Failed to create application', error);
        return res.status(400).json({ error: error.message || 'Failed to create application record' });
      }

      await insertAuditLog(req.user.id, 'APPLICATION_CONFIRMED', {
        target: targetUser.email || userId,
      });

      return res.json({ success: true });
    } catch (error) {
      console.error('Failed to confirm application', error);
      return res.status(500).json({ error: 'Failed to confirm application' });
    }
  }
);

app.post(
  '/superadmin/assign-unit-role',
  requireAuthenticatedUser,
  requireSuperAdmin,
  async (req, res) => {
    try {
      const dayungUnitId = Number(req.body.dayung_unit_id);
      const userId = sanitizeText(req.body.user_id, { maxLength: 80 });
      const role = sanitizeText(req.body.role, { maxLength: 40 }).toLowerCase();

      if (!Number.isInteger(dayungUnitId) || dayungUnitId <= 0) {
        return res.status(400).json({ error: 'Invalid dayung_unit_id' });
      }

      if (!userId) {
        return res.status(400).json({ error: 'Missing user_id' });
      }

      if (!['president', 'secretary', 'treasurer', 'collector'].includes(role)) {
        return res.status(400).json({ error: 'Invalid role assignment' });
      }

      const [{ data: unit, error: unitError }, targetUser] = await Promise.all([
        supabase
          .from('dayung_units')
          .select('id, name, president_id, secretary_id, treasurer_id')
          .eq('id', dayungUnitId)
          .maybeSingle(),
        getPublicUserById(userId),
      ]);

      if (unitError) {
        throw unitError;
      }

      if (!unit) {
        return res.status(404).json({ error: 'Dayung unit not found' });
      }

      if (!targetUser) {
        return res.status(404).json({ error: 'User not found' });
      }

      if (role === 'collector') {
        await supabase
          .from('dayung_collectors')
          .delete()
          .eq('dayung_unit_id', dayungUnitId)
          .eq('user_id', userId);

        const { data: latestCollector, error: collectorIdError } = await supabase
          .from('dayung_collectors')
          .select('collectors_id')
          .order('collectors_id', { ascending: false })
          .limit(1)
          .maybeSingle();

        if (collectorIdError) {
          throw collectorIdError;
        }

        const latestCollectorId = Number(latestCollector?.collectors_id || 0);

        const { error } = await supabase.from('dayung_collectors').insert({
          collectors_id: Number.isInteger(latestCollectorId) ? latestCollectorId + 1 : 1,
          dayung_unit_id: dayungUnitId,
          user_id: userId,
          added_by: req.user.id,
          created_at: new Date().toISOString(),
        });

        if (error) {
          console.error('Failed to assign collector', error);
          return res.status(400).json({ error: error.message || 'Failed to assign collector' });
        }
      } else {
        const column = UNIT_ROLE_COLUMNS[role];
        const { data: updatedUnit, error } = await supabase
          .from('dayung_units')
          .update({ [column]: userId })
          .eq('id', dayungUnitId)
          .select('id, name, president_id, secretary_id, treasurer_id')
          .maybeSingle();

        if (error) {
          console.error('Failed to assign unit role', error);
          return res.status(400).json({ error: error.message || 'Failed to assign role' });
        }
        if (!updatedUnit) {
          return res.status(404).json({ error: 'Dayung unit not found or was not updated' });
        }
      }

      await insertAuditLog(req.user.id, 'UNIT_ROLE_ASSIGNED', {
        role,
        unit: unit.name || `unit ${dayungUnitId}`,
        target: targetUser.email || userId,
      });

      return res.json({ success: true });
    } catch (error) {
      console.error('Failed to assign unit role', error);
      return res.status(500).json({ error: 'Failed to assign role' });
    }
  }
);

app.post(
  '/superadmin/remove-unit-role',
  requireAuthenticatedUser,
  requireSuperAdmin,
  async (req, res) => {
    try {
      const dayungUnitId = Number(req.body.dayung_unit_id);
      const userId = sanitizeText(req.body.user_id || '', { maxLength: 80 });
      const role = sanitizeText(req.body.role, { maxLength: 40 }).toLowerCase();

      if (!Number.isInteger(dayungUnitId) || dayungUnitId <= 0) {
        return res.status(400).json({ error: 'Invalid dayung_unit_id' });
      }

      if (!['president', 'secretary', 'treasurer', 'collector'].includes(role)) {
        return res.status(400).json({ error: 'Invalid role assignment' });
      }

      const { data: unit, error: unitError } = await supabase
        .from('dayung_units')
        .select('id, name, president_id, secretary_id, treasurer_id')
        .eq('id', dayungUnitId)
        .maybeSingle();

      if (unitError) {
        throw unitError;
      }

      if (!unit) {
        return res.status(404).json({ error: 'Dayung unit not found' });
      }

      if (role === 'collector') {
        if (!userId) {
          return res.status(400).json({ error: 'Collector removal requires user_id' });
        }

        const { error } = await supabase
          .from('dayung_collectors')
          .delete()
          .eq('dayung_unit_id', dayungUnitId)
          .eq('user_id', userId);

        if (error) {
          console.error('Failed to remove collector', error);
          return res.status(400).json({ error: error.message || 'Failed to remove collector' });
        }
      } else {
        const column = UNIT_ROLE_COLUMNS[role];
        const { data: updatedUnit, error } = await supabase
          .from('dayung_units')
          .update({ [column]: null })
          .eq('id', dayungUnitId)
          .select('id, name, president_id, secretary_id, treasurer_id')
          .maybeSingle();

        if (error) {
          console.error('Failed to remove unit role', error);
          return res.status(400).json({ error: error.message || 'Failed to remove role' });
        }
        if (!updatedUnit) {
          return res.status(404).json({ error: 'Dayung unit not found or was not updated' });
        }
      }

      await insertAuditLog(req.user.id, 'UNIT_ROLE_REMOVED', {
        role,
        unit: unit.name || `unit ${dayungUnitId}`,
        target: userId || 'unassigned',
      });

      return res.json({ success: true });
    } catch (error) {
      console.error('Failed to remove unit role', error);
      return res.status(500).json({ error: 'Failed to remove role' });
    }
  }
);

app.get(
  '/superadmin/settings',
  requireAuthenticatedUser,
  requireSuperAdmin,
  async (_req, res) => {
    try {
      const settings = await readSystemState();
      return res.json({
        settings,
        twilio_configured: !!getTwilioConfig(),
      });
    } catch (error) {
      console.error('Failed to load settings', error);
      return res.status(500).json({ error: 'Failed to load settings' });
    }
  }
);

app.post(
  '/superadmin/settings',
  requireAuthenticatedUser,
  requireSuperAdmin,
  async (req, res) => {
    try {
      const currentState = await readSystemState();
      const nextState = {
        ...currentState,
        maintenance_mode: req.body.maintenance_mode === true,
        maintenance_message:
          sanitizeMultilineText(req.body.maintenance_message || currentState.maintenance_message, {
            maxLength: 240,
          }) || DEFAULT_SYSTEM_STATE.maintenance_message,
        allow_sms_broadcast: req.body.allow_sms_broadcast === true,
        force_password_change_on_create: req.body.force_password_change_on_create !== false,
        force_password_change_on_reset: req.body.force_password_change_on_reset !== false,
        updated_at: new Date().toISOString(),
        updated_by: req.requestingUserRow?.email || req.user.id,
      };

      await writeSystemState(nextState);
      await insertAuditLog(req.user.id, 'SYSTEM_SETTINGS_UPDATED', {
        maintenance_mode: nextState.maintenance_mode,
        allow_sms_broadcast: nextState.allow_sms_broadcast,
        force_create: nextState.force_password_change_on_create,
        force_reset: nextState.force_password_change_on_reset,
      });

      return res.json({
        success: true,
        settings: nextState,
        twilio_configured: !!getTwilioConfig(),
      });
    } catch (error) {
      console.error('Failed to update settings', error);
      return res.status(500).json({ error: 'Failed to update settings' });
    }
  }
);

app.get(
  '/superadmin/reports',
  requireAuthenticatedUser,
  requireSuperAdmin,
  async (_req, res) => {
    try {
      const report = await buildReportsModel();
      return res.json(report);
    } catch (error) {
      console.error('Failed to build reports', error);
      return res.status(500).json({ error: 'Failed to build reports' });
    }
  }
);

app.get(
  '/superadmin/system-snapshot',
  requireAuthenticatedUser,
  requireSuperAdmin,
  async (_req, res) => {
    try {
      const [report, settings] = await Promise.all([buildReportsModel(), readSystemState()]);
      return res.json({
        generated_at: new Date().toISOString(),
        settings,
        report,
      });
    } catch (error) {
      console.error('Failed to generate system snapshot', error);
      return res.status(500).json({ error: 'Failed to generate snapshot' });
    }
  }
);

app.get(
  '/superadmin/audit-logs',
  requireAuthenticatedUser,
  requireSuperAdmin,
  async (req, res) => {
    try {
      const search = sanitizeText(req.query.q || '', { maxLength: 120 }).toLowerCase();
      const categoryFilter = sanitizeText(req.query.category || '', { maxLength: 80 }).toLowerCase();
      const limit = Math.min(Math.max(Number(req.query.limit) || 120, 20), 250);

      const { data, error } = await supabase
        .from('audit_logs')
        .select('id, action, created_at, user:user_id(full_name, email)')
        .order('created_at', { ascending: false })
        .limit(limit);

      if (error) throw error;

      const logs = (Array.isArray(data) ? data : [])
        .map((log) => {
          const parsed = parseAuditAction(log.action);
          return {
            id: log.id,
            created_at: log.created_at,
            actor_name: log.user?.full_name || 'Unknown user',
            actor_email: log.user?.email || null,
            category: parsed.category,
            title: parsed.title,
            fields: parsed.fields,
            details: parsed.details,
            raw_action: parsed.raw_action,
          };
        })
        .filter((log) => {
          const haystack = `${log.actor_name} ${log.actor_email || ''} ${log.category} ${log.title} ${log.raw_action}`.toLowerCase();
          if (search && !haystack.includes(search)) return false;
          if (categoryFilter && log.category.toLowerCase() !== categoryFilter) return false;
          return true;
        });

      const categories = [...new Set(logs.map((log) => log.category))];
      return res.json({ logs, categories });
    } catch (error) {
      console.error('Failed to load audit logs', error);
      return res.status(500).json({ error: 'Failed to load audit logs' });
    }
  }
);

app.post(
  '/superadmin/send-broadcast',
  smsAnnouncementLimiter,
  requireAuthenticatedUser,
  requireSuperAdmin,
  async (req, res) => {
    try {
      const title = sanitizeText(req.body.title, { maxLength: 120 });
      const body = sanitizeMultilineText(req.body.body, { maxLength: 800 });
      const audience = sanitizeText(req.body.audience || 'all_active', { maxLength: 40 }).toLowerCase();
      const dayungUnitId = req.body.dayung_unit_id ? Number(req.body.dayung_unit_id) : null;
      const sendSms = req.body.send_sms === true;
      const settings = await readSystemState();

      if (title.length < 3 || body.length < 6) {
        return res.status(400).json({ error: 'Title or message is too short' });
      }

      if (dayungUnitId !== null && (!Number.isInteger(dayungUnitId) || dayungUnitId <= 0)) {
        return res.status(400).json({ error: 'Invalid dayung_unit_id' });
      }

      if (!['all_active', 'members', 'officers', 'superadmins', 'inactive'].includes(audience)) {
        return res.status(400).json({ error: 'Invalid audience' });
      }

      if (sendSms && settings.allow_sms_broadcast !== true) {
        return res.status(400).json({ error: 'SMS broadcast is disabled in system settings' });
      }

      const { recipients, audienceLabel } = await resolveBroadcastRecipients({
        audience,
        dayungUnitId,
      });

      if (recipients.length === 0) {
        return res.json({ success: true, delivered: 0, sms_sent: 0, audience_label: audienceLabel });
      }

      const notificationRows = recipients.map((recipient) => ({
        recipient_id: recipient.id,
        type: 'announcement',
        title,
        body,
        dayung_unit_id: dayungUnitId,
      }));

      for (const chunk of chunkArray(notificationRows, 500)) {
        const { error } = await supabase.from('notifications').insert(chunk);
        if (error) {
          console.error('Failed to insert broadcast notifications', error);
          return res.status(500).json({ error: 'Failed to save broadcast notifications' });
        }
      }

      let smsSent = 0;
      if (sendSms) {
        const twilioConfig = getTwilioConfig();
        if (!twilioConfig) {
          return res.status(503).json({ error: 'SMS service is not configured on the server' });
        }

        const smsMessage = `[Dayung] ${title}\n${body}`;
        for (const recipient of recipients) {
          if (!recipient.mobile_number) continue;
          try {
            await twilioConfig.client.messages.create({
              body: smsMessage,
              from: twilioConfig.from,
              to: recipient.mobile_number,
            });
            smsSent += 1;
          } catch (smsError) {
            console.error('SMS send failed for one broadcast recipient', smsError);
          }
        }
      }

      await insertAuditLog(req.user.id, 'BROADCAST_SENT', {
        title,
        audience,
        unit: dayungUnitId || 'all',
        delivered: recipients.length,
        sms_sent: smsSent,
      });

      return res.json({
        success: true,
        delivered: recipients.length,
        sms_sent: smsSent,
        audience_label: audienceLabel,
      });
    } catch (error) {
      console.error('Failed to send superadmin broadcast', error);
      return res.status(500).json({ error: 'Failed to send broadcast' });
    }
  }
);

app.post(
  '/send-announcement-sms',
  smsAnnouncementLimiter,
  requireAuthenticatedUser,
  requirePresidentOfUnit,
  async (req, res) => {
    try {
      const twilioConfig = getTwilioConfig();
      if (!twilioConfig) {
        return res.status(503).json({
          error: 'SMS service is not configured on the server',
        });
      }

      const { title, body } = req.body;
      const dayung_unit_id = req.dayungUnitId;

      if (
        typeof title !== 'string' ||
        typeof body !== 'string' ||
        title.trim().length < 3 ||
        body.trim().length < 3
      ) {
        return res.status(400).json({ error: 'Invalid title or body' });
      }

      const { data: unit, error: unitError } = await supabase
        .from('dayung_units')
        .select('president_id, secretary_id, treasurer_id, collector_id')
        .eq('id', dayung_unit_id)
        .maybeSingle();

      if (unitError) {
        console.error('Failed to load unit', unitError);
        return res.status(500).json({ error: 'Failed to load unit' });
      }

      if (!unit) {
        return res.status(404).json({ error: 'Unit not found' });
      }

      const officialIds = [
        unit.president_id,
        unit.secretary_id,
        unit.treasurer_id,
        unit.collector_id,
      ].filter(Boolean);

      const { data: members, error: membersError } = await supabase
        .from('applications')
        .select('user_id')
        .eq('dayung_unit_id', dayung_unit_id)
        .eq('status', 'approved');

      if (membersError) {
        console.error('Failed to load members', membersError);
        return res.status(500).json({ error: 'Failed to load members' });
      }

      const memberIds = members.map((m) => m.user_id);
      const allUserIds = Array.from(new Set([...officialIds, ...memberIds]));

      if (allUserIds.length === 0) {
        return res.json({ success: true, sent: 0 });
      }

      const { data: users, error: usersError } = await supabase
        .from('users')
        .select('mobile_number')
        .in('id', allUserIds);

      if (usersError) {
        console.error('Failed to load recipients', usersError);
        return res.status(500).json({ error: 'Failed to load recipients' });
      }

      const message = `[Dayung] ${title.trim()}\n${body.trim()}`;
      let sent = 0;

      for (const user of users) {
        if (!user.mobile_number) continue;

        try {
          await twilioConfig.client.messages.create({
            body: message,
            from: twilioConfig.from,
            to: user.mobile_number,
          });
          sent++;
        } catch (err) {
          console.error('SMS send failed for one recipient', err);
        }
      }

      return res.json({ success: true, sent });
    } catch (err) {
      console.error('Unhandled error in /send-announcement-sms', err);
      return res.status(500).json({ error: 'Internal server error' });
    }
  }
);

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));