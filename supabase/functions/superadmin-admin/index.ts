import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const longBanDuration = '876000h';
const settingsTable = 'system_settings';
const defaultSystemSettings = {
  id: 'global',
  maintenance_mode: false,
  maintenance_message:
    'Dayung is temporarily unavailable for maintenance. Please try again later.',
  allow_sms_broadcast: false,
  force_password_change_on_create: true,
  force_password_change_on_reset: true,
  updated_at: null,
  updated_by: null,
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  });
}

function sanitizeText(value: unknown, maxLength = 255) {
  if (typeof value !== 'string') return '';
  return value.replace(/[<>]/g, '').replace(/\s+/g, ' ').trim().slice(0, maxLength);
}

function sanitizeEmail(value: unknown) {
  return sanitizeText(value, 120).toLowerCase();
}

function sanitizeMultilineText(value: unknown, maxLength = 800) {
  if (typeof value !== 'string') return '';
  return value.replace(/[<>]/g, '').replace(/\r/g, '').trim().slice(0, maxLength);
}

function validateEmail(email: string) {
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email);
}

function validatePassword(password: unknown) {
  return typeof password === 'string' && password.length >= 8 && password.length <= 72;
}

function encodeAuditValue(value: unknown) {
  return encodeURIComponent(String(value ?? '').trim().slice(0, 160));
}

function buildAuditAction(eventName: string, fields: Record<string, unknown> = {}) {
  const safeEvent = sanitizeText(eventName, 80).replace(/\s+/g, '_').toUpperCase();
  const segments = [safeEvent || 'EVENT'];

  for (const [key, value] of Object.entries(fields)) {
    if (value === undefined || value === null || String(value).trim().length === 0) {
      continue;
    }
    segments.push(`${sanitizeText(key, 40).toLowerCase()}=${encodeAuditValue(value)}`);
  }

  return segments.join(' | ');
}

function humanizeAuditEvent(eventName: string) {
  return eventName
    .toLowerCase()
    .split('_')
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');
}

function auditCategoryForEvent(eventName: string) {
  if (eventName.startsWith('LOGIN_')) return 'Login Attempts';
  if (eventName.startsWith('SYSTEM_ERROR')) return 'System Errors';
  if (eventName.startsWith('ACCESS_')) return 'Access Violations';
  if (eventName.startsWith('USER_ACTIVITY_') || eventName === 'PASSWORD_CHANGED_ON_FIRST_SIGN_IN') {
    return 'User Activities';
  }
  return humanizeAuditEvent(eventName);
}

function auditTitleForEvent(eventName: string) {
  if (eventName.startsWith('USER_ACTIVITY_')) {
    return humanizeAuditEvent(eventName.replace('USER_ACTIVITY_', ''));
  }
  return humanizeAuditEvent(eventName);
}

function parseAuditAction(action: unknown) {
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
  const fields: Record<string, string> = {};
  const details: string[] = [];

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
    category: auditCategoryForEvent(eventToken),
    title: auditTitleForEvent(eventToken),
    details,
    fields,
  };
}

function isAuthUserDisabled(authUser: any) {
  if (!authUser?.banned_until) return false;
  const bannedUntil = Date.parse(authUser.banned_until);
  return !Number.isNaN(bannedUntil) && bannedUntil > Date.now();
}

async function getAllAuthUsers(adminClient: any) {
  const users: any[] = [];
  let page = 1;
  const perPage = 200;

  while (true) {
    const { data, error } = await adminClient.auth.admin.listUsers({ page, perPage });
    if (error) throw error;

    const batch = Array.isArray(data?.users) ? data.users : [];
    users.push(...batch);

    if (!data?.nextPage || batch.length < perPage) {
      break;
    }

    page = data.nextPage;
  }

  return users;
}

async function loadSystemSettings(adminClient: any) {
  try {
    const { data, error } = await adminClient
      .from(settingsTable)
      .select(
        'id, maintenance_mode, maintenance_message, allow_sms_broadcast, force_password_change_on_create, force_password_change_on_reset, updated_at, updated_by',
      )
      .eq('id', 'global')
      .maybeSingle();

    if (error) throw error;
    return { ...defaultSystemSettings, ...(data ?? {}) };
  } catch (_error) {
    return { ...defaultSystemSettings };
  }
}

async function insertAuditLog(
  adminClient: any,
  userId: string,
  eventName: string,
  fields: Record<string, unknown> = {},
) {
  try {
    await adminClient.from('audit_logs').insert({
      user_id: userId,
      action: buildAuditAction(eventName, fields),
      created_at: new Date().toISOString(),
    });
  } catch (_error) {}
}

async function getPublicUserById(adminClient: any, userId: string) {
  const { data, error } = await adminClient
    .from('users')
    .select('id, full_name, email, role, is_deceased')
    .eq('id', userId)
    .maybeSingle();

  if (error) throw error;
  return data;
}

async function ensureSuperAdminCanBeModified(
  adminClient: any,
  targetUserId: string,
  disableRequested: boolean,
) {
  const targetUser = await getPublicUserById(adminClient, targetUserId);
  if (!targetUser || targetUser.role !== 'superadmin' || !disableRequested) {
    return { ok: true, targetUser };
  }

  const { data, error } = await adminClient.from('users').select('id').eq('role', 'superadmin');
  if (error) throw error;

  const totalSuperAdmins = Array.isArray(data) ? data.length : 0;
  if (totalSuperAdmins <= 1) {
    return {
      ok: false,
      targetUser,
      error: 'You cannot disable the last superadmin account.',
    };
  }

  return { ok: true, targetUser };
}

function monthKey(value: unknown) {
  const parsed = Date.parse(String(value ?? ''));
  if (Number.isNaN(parsed)) return null;
  const date = new Date(parsed);
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}`;
}

function buildMonthSeries(
  monthsBack: number,
  values: Array<{ date: unknown; value?: unknown }>,
  amount = false,
) {
  const now = new Date();
  const buckets: Array<{ month: string; value: number }> = [];
  const bucketMap = new Map<string, { month: string; value: number }>();

  for (let offset = monthsBack - 1; offset >= 0; offset -= 1) {
    const date = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - offset, 1));
    const key = `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}`;
    const item = { month: key, value: 0 };
    buckets.push(item);
    bucketMap.set(key, item);
  }

  for (const entry of values) {
    const key = monthKey(entry.date);
    if (!key || !bucketMap.has(key)) continue;
    bucketMap.get(key)!.value += amount ? Number(entry.value) || 0 : 1;
  }

  return buckets.map((bucket) => ({
    month: bucket.month,
    value: amount ? Number(bucket.value.toFixed(2)) : bucket.value,
  }));
}

async function buildReportsModel(adminClient: any) {
  const [authUsers, publicUsersRes, applicationsRes, unitsRes, collectorsRes, paymentsRes, notificationsRes, auditLogsRes] =
    await Promise.all([
      getAllAuthUsers(adminClient),
      adminClient.from('users').select('id, role, is_deceased, created_at'),
      adminClient.from('applications').select('user_id, dayung_unit_id, status, approved_at'),
      adminClient.from('dayung_units').select('id, name, president_id, secretary_id, treasurer_id'),
      adminClient.from('dayung_collectors').select('user_id, dayung_unit_id'),
      adminClient.from('payments').select('amount, status, paid_at'),
      adminClient.from('notifications').select('created_at'),
      adminClient.from('audit_logs').select('created_at'),
    ]);

  if (publicUsersRes.error) throw publicUsersRes.error;
  if (applicationsRes.error) throw applicationsRes.error;
  if (unitsRes.error) throw unitsRes.error;
  if (collectorsRes.error) throw collectorsRes.error;
  if (paymentsRes.error) throw paymentsRes.error;
  if (notificationsRes.error) throw notificationsRes.error;
  if (auditLogsRes.error) throw auditLogsRes.error;

  const publicUsers = Array.isArray(publicUsersRes.data) ? publicUsersRes.data : [];
  const applications = Array.isArray(applicationsRes.data) ? applicationsRes.data : [];
  const units = Array.isArray(unitsRes.data) ? unitsRes.data : [];
  const collectors = Array.isArray(collectorsRes.data) ? collectorsRes.data : [];
  const payments = Array.isArray(paymentsRes.data) ? paymentsRes.data : [];
  const notifications = Array.isArray(notificationsRes.data) ? notificationsRes.data : [];
  const auditLogs = Array.isArray(auditLogsRes.data) ? auditLogsRes.data : [];

  const disabledIds = new Set(authUsers.filter((user: any) => isAuthUserDisabled(user)).map((user: any) => user.id));
  const approvedApplications = applications.filter((row: any) => row.status === 'approved');
  const approvedMemberIds = new Set(
    approvedApplications.map((row: any) => row.user_id).filter(Boolean),
  );
  const officerIds = new Set<string>();
  const unitMemberCounts = new Map<string, number>();
  const unitNames = new Map<string, string>();

  for (const unit of units) {
    if (unit.id != null) {
      unitNames.set(String(unit.id), unit.name || `Unit ${unit.id}`);
    }
    for (const value of [unit.president_id, unit.secretary_id, unit.treasurer_id]) {
      if (value) officerIds.add(String(value));
    }
  }

  for (const collector of collectors) {
    if (collector.user_id) officerIds.add(String(collector.user_id));
  }

  for (const appRow of approvedApplications) {
    if (!appRow.dayung_unit_id) continue;
    const key = String(appRow.dayung_unit_id);
    unitMemberCounts.set(key, (unitMemberCounts.get(key) || 0) + 1);
  }

  const paidRows = payments.filter((row: any) => String(row.status ?? '').toLowerCase() === 'paid');
  const thirtyDaysAgo = Date.now() - 30 * 24 * 60 * 60 * 1000;

  return {
    generated_at: new Date().toISOString(),
    summary: {
      total_users: publicUsers.length,
      active_users: publicUsers.filter((user: any) => !disabledIds.has(user.id) && user.is_deceased !== true).length,
      disabled_users: publicUsers.filter((user: any) => disabledIds.has(user.id)).length,
      deceased_users: publicUsers.filter((user: any) => user.is_deceased === true).length,
      superadmins: publicUsers.filter((user: any) => user.role === 'superadmin').length,
      officers: officerIds.size,
      approved_members: approvedMemberIds.size,
      pending_applications: applications.filter((row: any) => row.status === 'pending').length,
      dayung_units: units.length,
      paid_transactions: paidRows.length,
      paid_total: Number(
        paidRows.reduce((sum: number, row: any) => sum + (Number(row.amount) || 0), 0).toFixed(2),
      ),
      notifications_last_30_days: notifications.filter(
        (row: any) => Date.parse(String(row.created_at ?? '')) >= thirtyDaysAgo,
      ).length,
      audit_logs_last_30_days: auditLogs.filter(
        (row: any) => Date.parse(String(row.created_at ?? '')) >= thirtyDaysAgo,
      ).length,
    },
    monthly_users: buildMonthSeries(
      6,
      authUsers.map((user: any) => ({ date: user.created_at })),
    ),
    monthly_approvals: buildMonthSeries(
      6,
      approvedApplications.map((row: any) => ({ date: row.approved_at })),
    ),
    monthly_revenue: buildMonthSeries(
      6,
      paidRows.map((row: any) => ({ date: row.paid_at, value: row.amount })),
      true,
    ),
    role_breakdown: {
      superadmins: publicUsers.filter((user: any) => user.role === 'superadmin').length,
      officers: officerIds.size,
      members: approvedMemberIds.size,
      disabled: publicUsers.filter((user: any) => disabledIds.has(user.id)).length,
    },
    top_units: [...unitMemberCounts.entries()]
      .sort((left, right) => right[1] - left[1])
      .slice(0, 5)
      .map(([unitId, count]) => ({
        dayung_unit_id: unitId,
        name: unitNames.get(unitId) || `Unit ${unitId}`,
        members: count,
      })),
  };
}

async function loadUnitParticipantIds(adminClient: any, dayungUnitId: string) {
  const participantIds = new Set<string>();
  const [unitRes, collectorsRes, appsRes] = await Promise.all([
    adminClient
      .from('dayung_units')
      .select('president_id, secretary_id, treasurer_id')
      .eq('id', dayungUnitId)
      .maybeSingle(),
    adminClient.from('dayung_collectors').select('user_id').eq('dayung_unit_id', dayungUnitId),
    adminClient
      .from('applications')
      .select('user_id')
      .eq('dayung_unit_id', dayungUnitId)
      .eq('status', 'approved'),
  ]);

  if (unitRes.error) throw unitRes.error;
  if (collectorsRes.error) throw collectorsRes.error;
  if (appsRes.error) throw appsRes.error;

  const unit = unitRes.data;
  if (unit) {
    for (const value of [unit.president_id, unit.secretary_id, unit.treasurer_id]) {
      if (value) participantIds.add(String(value));
    }
  }

  for (const collector of collectorsRes.data ?? []) {
    if (collector.user_id) participantIds.add(String(collector.user_id));
  }

  for (const app of appsRes.data ?? []) {
    if (app.user_id) participantIds.add(String(app.user_id));
  }

  return participantIds;
}

async function resolveBroadcastRecipients(
  adminClient: any,
  audience: string,
  dayungUnitId: string | null,
) {
  const [authUsers, publicUsersRes, approvedAppsRes, unitsRes, collectorsRes] = await Promise.all([
    getAllAuthUsers(adminClient),
    adminClient.from('users').select('id, full_name, email, role, mobile_number, is_deceased'),
    adminClient.from('applications').select('user_id, dayung_unit_id, status').eq('status', 'approved'),
    adminClient.from('dayung_units').select('id, president_id, secretary_id, treasurer_id'),
    adminClient.from('dayung_collectors').select('user_id, dayung_unit_id'),
  ]);

  if (publicUsersRes.error) throw publicUsersRes.error;
  if (approvedAppsRes.error) throw approvedAppsRes.error;
  if (unitsRes.error) throw unitsRes.error;
  if (collectorsRes.error) throw collectorsRes.error;

  const publicUsers = Array.isArray(publicUsersRes.data) ? publicUsersRes.data : [];
  const approvedApps = Array.isArray(approvedAppsRes.data) ? approvedAppsRes.data : [];
  const units = Array.isArray(unitsRes.data) ? unitsRes.data : [];
  const collectors = Array.isArray(collectorsRes.data) ? collectorsRes.data : [];
  const disabledIds = new Set(authUsers.filter((user: any) => isAuthUserDisabled(user)).map((user: any) => user.id));
  const publicUserById = new Map(publicUsers.map((user: any) => [String(user.id), user]));
  const officerIds = new Set<string>();

  for (const unit of units) {
    for (const value of [unit.president_id, unit.secretary_id, unit.treasurer_id]) {
      if (value) officerIds.add(String(value));
    }
  }
  for (const collector of collectors) {
    if (collector.user_id) officerIds.add(String(collector.user_id));
  }

  let recipientIds = new Set<string>();
  let audienceLabel = audience;

  if (audience === 'all_active') {
    if (dayungUnitId) {
      recipientIds = await loadUnitParticipantIds(adminClient, dayungUnitId);
      audienceLabel = `Active users in unit ${dayungUnitId}`;
    } else {
      recipientIds = new Set(publicUsers.map((user: any) => String(user.id)));
      audienceLabel = 'All active users';
    }
  } else if (audience === 'members') {
    const filtered = approvedApps.filter(
      (row: any) => !dayungUnitId || String(row.dayung_unit_id) === dayungUnitId,
    );
    recipientIds = new Set(filtered.map((row: any) => String(row.user_id)).filter(Boolean));
    audienceLabel = dayungUnitId
      ? `Approved members in unit ${dayungUnitId}`
      : 'All approved members';
  } else if (audience === 'officers') {
    if (dayungUnitId) {
      const unitParticipants = await loadUnitParticipantIds(adminClient, dayungUnitId);
      recipientIds = new Set([...unitParticipants].filter((id) => officerIds.has(id)));
      audienceLabel = `Officers in unit ${dayungUnitId}`;
    } else {
      recipientIds = officerIds;
      audienceLabel = 'All officers';
    }
  } else if (audience === 'superadmins') {
    recipientIds = new Set(
      publicUsers.filter((user: any) => user.role === 'superadmin').map((user: any) => String(user.id)),
    );
    audienceLabel = 'All superadmins';
  } else if (audience === 'inactive') {
    recipientIds = new Set([...disabledIds].map((id) => String(id)));
    if (dayungUnitId) {
      const unitParticipants = await loadUnitParticipantIds(adminClient, dayungUnitId);
      recipientIds = new Set([...recipientIds].filter((id) => unitParticipants.has(id)));
      audienceLabel = `Inactive users in unit ${dayungUnitId}`;
    } else {
      audienceLabel = 'All inactive users';
    }
  } else {
    throw new Error('Unsupported audience.');
  }

  const recipients = [...recipientIds]
    .map((id) => publicUserById.get(id))
    .filter(Boolean)
    .filter((user: any) => user.is_deceased !== true)
    .filter((user: any) => (audience === 'inactive' ? true : !disabledIds.has(user.id)));

  return { recipients, audienceLabel };
}

async function requireSuperAdmin(req: Request, adminClient: any, anonClient: any) {
  const {
    data: { user },
    error: authError,
  } = await anonClient.auth.getUser();

  if (authError || !user) {
    return { error: json(401, { error: 'Invalid token' }) };
  }

  const { data: userRow, error } = await adminClient
    .from('users')
    .select('id, role, email, full_name')
    .eq('id', user.id)
    .maybeSingle();

  if (error) {
    return { error: json(500, { error: 'Failed to load requesting user' }) };
  }

  if (!userRow || userRow.role !== 'superadmin') {
    return { error: json(403, { error: 'Forbidden' }) };
  }

  return { user, userRow };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return json(405, { error: 'Method not allowed' });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      return json(500, { error: 'Supabase environment variables are not configured.' });
    }

    const authorization = req.headers.get('Authorization') ?? '';
    const anonClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const authCheck = await requireSuperAdmin(req, adminClient, anonClient);
    if (authCheck.error) {
      return authCheck.error;
    }

    const requester = authCheck.user!;
    const body = await req.json().catch(() => ({}));
    const action = sanitizeText(body.action, 60).toLowerCase();

    switch (action) {
      case 'list_users': {
        const authUsers = await getAllAuthUsers(adminClient);
        const { data, error } = await adminClient
          .from('users')
          .select('id, full_name, email, role, is_deceased')
          .order('full_name', { ascending: true });

        if (error) {
          return json(500, { error: 'Failed to fetch users' });
        }

        const authById = new Map(authUsers.map((user: any) => [user.id, user]));
        const users = (data ?? []).map((user: any) => {
          const authUser = authById.get(user.id);
          return {
            ...user,
            is_disabled: isAuthUserDisabled(authUser),
            banned_until: authUser?.banned_until ?? null,
            email_confirmed_at: authUser?.email_confirmed_at ?? null,
          };
        });

        return json(200, { users });
      }

      case 'create_user': {
        let createdAuthUserId: string | null = null;

        try {
          const fullName = sanitizeText(body.full_name, 120);
          const email = sanitizeEmail(body.email);
          const password = body.password;
          const requestedRole = sanitizeText(body.role || 'member', 40).toLowerCase();
          const systemState = await loadSystemSettings(adminClient);

          if (fullName.length < 2) {
            return json(400, { error: 'Full name is too short' });
          }
          if (!validateEmail(email)) {
            return json(400, { error: 'Enter a valid email address' });
          }
          if (!validatePassword(password)) {
            return json(400, { error: 'Password must be 8 to 72 characters long' });
          }
          if (!['member', 'superadmin'].includes(requestedRole)) {
            return json(400, {
              error:
                'Only member and superadmin accounts can be created here. Officer roles must be assigned from unit-role management.',
            });
          }

          const { data: existingUser, error: existingUserError } = await adminClient
            .from('users')
            .select('id')
            .eq('email', email)
            .maybeSingle();

          if (existingUserError) {
            return json(500, { error: 'Failed to validate user email' });
          }
          if (existingUser) {
            return json(409, { error: 'An account with that email already exists' });
          }

          const { data: createdAuth, error: createAuthError } = await adminClient.auth.admin.createUser({
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
            return json(400, {
              error: createAuthError?.message || 'Failed to create auth user',
            });
          }

          createdAuthUserId = createdAuth.user.id;
          const { error: insertUserError } = await adminClient.from('users').insert({
            id: createdAuth.user.id,
            full_name: fullName,
            email,
            role: requestedRole,
            is_deceased: false,
          });

          if (insertUserError) {
            await adminClient.auth.admin.deleteUser(createdAuth.user.id);
            return json(500, { error: 'Failed to create public user row' });
          }

          await insertAuditLog(adminClient, requester.id, 'ACCOUNT_CREATED', {
            target: email,
            role: requestedRole,
            force_password_change: systemState.force_password_change_on_create === true,
          });

          return json(201, {
            user: {
              id: createdAuth.user.id,
              full_name: fullName,
              email,
              role: requestedRole,
              is_deceased: false,
            },
            requires_password_change: systemState.force_password_change_on_create === true,
          });
        } catch (_error) {
          if (createdAuthUserId) {
            try {
              await adminClient.auth.admin.deleteUser(createdAuthUserId);
            } catch (_rollbackError) {}
          }
          return json(500, { error: 'Internal server error' });
        }
      }

      case 'reset_user_password': {
        const userId = sanitizeText(body.user_id, 80);
        const password = body.password;

        if (!userId) {
          return json(400, { error: 'Missing user_id' });
        }
        if (!validatePassword(password)) {
          return json(400, { error: 'Password must be 8 to 72 characters long' });
        }

        const targetUser = await getPublicUserById(adminClient, userId);
        if (!targetUser) {
          return json(404, { error: 'User not found' });
        }

        const systemState = await loadSystemSettings(adminClient);
        const { data: authLookup, error: authLookupError } = await adminClient.auth.admin.getUserById(userId);
        if (authLookupError) {
          return json(500, { error: 'Failed to load auth user' });
        }

        const currentMetadata = {
          ...(authLookup?.user?.user_metadata || {}),
        };

        const { error } = await adminClient.auth.admin.updateUserById(userId, {
          password,
          user_metadata: {
            ...currentMetadata,
            force_password_change: systemState.force_password_change_on_reset === true,
          },
        });

        if (error) {
          return json(400, { error: error.message || 'Failed to reset password' });
        }

        await insertAuditLog(adminClient, requester.id, 'ACCOUNT_PASSWORD_RESET', {
          target: targetUser.email || userId,
          force_password_change: systemState.force_password_change_on_reset === true,
        });

        return json(200, {
          success: true,
          requires_password_change: systemState.force_password_change_on_reset === true,
        });
      }

      case 'set_user_disabled': {
        const userId = sanitizeText(body.user_id, 80);
        const disabled = body.disabled === true;

        if (!userId) {
          return json(400, { error: 'Missing user_id' });
        }
        if (userId === requester.id && disabled) {
          return json(400, { error: 'You cannot disable your own active session.' });
        }

        const check = await ensureSuperAdminCanBeModified(adminClient, userId, disabled);
        if (!check.ok) {
          return json(400, { error: check.error });
        }
        if (!check.targetUser) {
          return json(404, { error: 'User not found' });
        }

        const { error } = await adminClient.auth.admin.updateUserById(userId, {
          ban_duration: disabled ? longBanDuration : 'none',
        });

        if (error) {
          return json(400, { error: error.message || 'Failed to update account status' });
        }

        await insertAuditLog(
          adminClient,
          requester.id,
          disabled ? 'ACCOUNT_DISABLED' : 'ACCOUNT_REACTIVATED',
          { target: check.targetUser.email || userId },
        );

        return json(200, { success: true, disabled });
      }

      case 'get_reports': {
        return json(200, await buildReportsModel(adminClient));
      }

      case 'get_audit_logs': {
        const search = sanitizeText(body.q || '', 120).toLowerCase();
        const categoryFilter = sanitizeText(body.category || '', 80).toLowerCase();
        const requestedLimit = Number(body.limit);
        const limit = Math.min(Math.max(Number.isFinite(requestedLimit) ? requestedLimit : 120, 20), 250);

        const { data, error } = await adminClient
          .from('audit_logs')
          .select('id, action, created_at, user:user_id(full_name, email)')
          .order('created_at', { ascending: false })
          .limit(limit);

        if (error) {
          return json(500, { error: 'Failed to load audit logs' });
        }

        const logs = (Array.isArray(data) ? data : [])
          .map((log: any) => {
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
          .filter((log: any) => {
            const haystack = `${log.actor_name} ${log.actor_email || ''} ${log.category} ${log.title} ${log.raw_action}`.toLowerCase();
            if (search && !haystack.includes(search)) return false;
            if (categoryFilter && String(log.category).toLowerCase() !== categoryFilter) return false;
            return true;
          });

        const categories = [...new Set(logs.map((log: any) => log.category))];
        return json(200, { logs, categories });
      }

      case 'get_system_snapshot': {
        const [report, settings] = await Promise.all([
          buildReportsModel(adminClient),
          loadSystemSettings(adminClient),
        ]);
        return json(200, {
          generated_at: new Date().toISOString(),
          settings,
          report,
        });
      }

      case 'send_broadcast': {
        const title = sanitizeText(body.title, 120);
        const message = sanitizeMultilineText(body.body, 800);
        const audience = sanitizeText(body.audience || 'all_active', 40).toLowerCase();
        const dayungUnitId = body.dayung_unit_id == null ? null : String(body.dayung_unit_id).trim();
        const sendSms = body.send_sms === true;

        if (title.length < 3 || message.length < 6) {
          return json(400, { error: 'Title or message is too short.' });
        }
        if (sendSms) {
          return json(400, {
            error:
              'SMS sending is intentionally disabled here. Use in-app broadcast only until SMS is implemented server-side.',
          });
        }

        const resolved = await resolveBroadcastRecipients(adminClient, audience, dayungUnitId);
        const recipients = Array.isArray(resolved.recipients) ? resolved.recipients : [];

        if (recipients.length > 0) {
          const rows = recipients.map((recipient: any) => ({
            recipient_id: recipient.id,
            type: 'announcement',
            title,
            body: message,
            dayung_unit_id: dayungUnitId ? Number(dayungUnitId) : null,
          }));

          const { error } = await adminClient.from('notifications').insert(rows);
          if (error) {
            return json(500, { error: 'Failed to send in-app broadcast.' });
          }
        }

        await insertAuditLog(adminClient, requester.id, 'BROADCAST_SENT', {
          title,
          audience,
          unit: dayungUnitId || 'all',
          delivered: recipients.length,
          sms_sent: 0,
        });

        return json(200, {
          success: true,
          delivered: recipients.length,
          sms_sent: 0,
          audience_label: resolved.audienceLabel,
        });
      }

      default:
        return json(400, { error: 'Unsupported action.' });
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Internal server error';
    return json(500, { error: message || 'Internal server error' });
  }
});