import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const publicAuditEvents = new Set([
  'LOGIN_ATTEMPT_STARTED',
  'LOGIN_ATTEMPT_FAILED',
  'ACCESS_VIOLATION',
  'SYSTEM_ERROR',
]);

const authenticatedAuditPrefixes = [
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

function isAuditEventAllowed(eventName: string, isAuthenticated: boolean) {
  if (!eventName) return false;
  if (isAuthenticated) {
    return authenticatedAuditPrefixes.some((prefix) => eventName.startsWith(prefix));
  }
  return publicAuditEvents.has(eventName);
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
      global: { headers: authorization ? { Authorization: authorization } : {} },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    let actorUserId: string | null = null;
    if (authorization.startsWith('Bearer ')) {
      const {
        data: { user },
        error,
      } = await anonClient.auth.getUser();
      if (!error && user) {
        actorUserId = user.id;
      }
    }

    const body = await req.json().catch(() => ({}));
    const eventName = sanitizeText(body.event_name, 80).replace(/\s+/g, '_').toUpperCase();
    const fields = body.fields && typeof body.fields === 'object'
      ? body.fields as Record<string, unknown>
      : {};

    if (!isAuditEventAllowed(eventName, !!actorUserId)) {
      return json(403, { error: 'Audit event is not allowed.' });
    }

    const { error } = await adminClient.from('audit_logs').insert({
      user_id: actorUserId,
      action: buildAuditAction(eventName, fields),
      created_at: new Date().toISOString(),
    });

    if (error) {
      return json(500, { error: 'Failed to ingest audit event.' });
    }

    return json(200, { success: true });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Internal server error';
    return json(500, { error: message || 'Internal server error' });
  }
});