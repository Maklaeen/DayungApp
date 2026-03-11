const express = require('express');
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

const turnstileLimiter = rateLimit({
  windowMs: 10 * 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many captcha attempts. Please try again later.' },
});

function getOptionalEnv(name) {
  const value = process.env[name];
  return typeof value === 'string' ? value.trim() : '';
}

function getTurnstileSiteKey() {
  return getOptionalEnv('TURNSTILE_SITE_KEY');
}

function getTurnstileSecretKey() {
  return getOptionalEnv('TURNSTILE_SECRET_KEY');
}

function normalizeTurnstileAction(raw) {
  const allowed = new Set(['login', 'forgot_password']);
  const action = typeof raw === 'string' ? raw.trim().toLowerCase() : 'login';
  return allowed.has(action) ? action : 'login';
}

function renderTurnstileHtml({ siteKey, action }) {
  const safeAction = normalizeTurnstileAction(action);

  if (!siteKey) {
    return `<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <style>
      body {
        margin: 0;
        font-family: Arial, sans-serif;
        background: #f8fafc;
        color: #0f172a;
        display: flex;
        align-items: center;
        justify-content: center;
        min-height: 100vh;
        padding: 24px;
        box-sizing: border-box;
      }
      .card {
        max-width: 420px;
        background: white;
        border-radius: 20px;
        padding: 24px;
        box-shadow: 0 20px 60px rgba(15, 23, 42, 0.12);
      }
      h1 { margin: 0 0 12px; font-size: 20px; }
      p { margin: 0; line-height: 1.5; color: #475569; }
    </style>
  </head>
  <body>
    <div class="card">
      <h1>Captcha not configured</h1>
      <p>TURNSTILE_SITE_KEY is missing on the backend server. Add it before using login or forgot password verification.</p>
    </div>
    <script>
      if (window.CaptchaBridge && window.CaptchaBridge.postMessage) {
        window.CaptchaBridge.postMessage(JSON.stringify({ type: 'config_error' }));
      }
    </script>
  </body>
</html>`;
  }

  return `<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <script src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit" async defer></script>
    <style>
      body {
        margin: 0;
        font-family: Arial, sans-serif;
        background: linear-gradient(180deg, #eff6ff 0%, #f8fafc 100%);
        color: #0f172a;
        display: flex;
        align-items: center;
        justify-content: center;
        min-height: 100vh;
        padding: 24px;
        box-sizing: border-box;
      }
      .card {
        width: 100%;
        max-width: 440px;
        background: white;
        border-radius: 24px;
        padding: 28px 24px;
        box-shadow: 0 22px 64px rgba(15, 23, 42, 0.16);
      }
      .badge {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        padding: 8px 12px;
        border-radius: 999px;
        background: #dbeafe;
        color: #1d4ed8;
        font-size: 12px;
        font-weight: 700;
        letter-spacing: 0.02em;
      }
      h1 {
        margin: 16px 0 10px;
        font-size: 24px;
        line-height: 1.2;
      }
      p {
        margin: 0 0 20px;
        line-height: 1.6;
        color: #475569;
      }
      #turnstile-container {
        min-height: 70px;
      }
      .hint {
        margin-top: 16px;
        font-size: 13px;
        color: #64748b;
      }
    </style>
  </head>
  <body>
    <div class="card">
      <div class="badge">Security Check</div>
      <h1>Verify before continuing</h1>
      <p>Complete the Cloudflare Turnstile check so we can continue with your ${safeAction === 'forgot_password' ? 'password reset' : 'sign in'} request.</p>
      <div id="turnstile-container"></div>
      <div class="hint">If the challenge expires or fails, it will refresh automatically.</div>
    </div>
    <script>
      function send(payload) {
        if (window.CaptchaBridge && window.CaptchaBridge.postMessage) {
          window.CaptchaBridge.postMessage(JSON.stringify(payload));
        }
      }

      function renderWidget() {
        if (!window.turnstile) {
          setTimeout(renderWidget, 150);
          return;
        }

        const container = document.getElementById('turnstile-container');
        container.innerHTML = '';

        window.turnstile.render(container, {
          sitekey: '${siteKey}',
          action: '${safeAction}',
          theme: 'light',
          retry: 'auto',
          callback: function(token) {
            send({ type: 'token', token: token, action: '${safeAction}' });
          },
          'error-callback': function(code) {
            send({ type: 'error', code: code || 'unknown_error' });
          },
          'expired-callback': function() {
            send({ type: 'expired' });
          }
        });
      }

      renderWidget();
    </script>
  </body>
</html>`;
}

function getRemoteIp(req) {
  const forwarded = req.headers['x-forwarded-for'];
  if (typeof forwarded === 'string' && forwarded.trim()) {
    return forwarded.split(',')[0].trim();
  }
  return req.ip || req.socket?.remoteAddress || undefined;
}

async function verifyTurnstileToken({ token, remoteIp }) {
  const secret = getTurnstileSecretKey();
  if (!secret) {
    throw new Error('TURNSTILE_SECRET_KEY is missing');
  }

  const form = new URLSearchParams({
    secret,
    response: token,
  });

  if (remoteIp) {
    form.set('remoteip', remoteIp);
  }

  const response = await fetch(
    'https://challenges.cloudflare.com/turnstile/v0/siteverify',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: form,
    }
  );

  if (!response.ok) {
    throw new Error(`Turnstile verification failed with status ${response.status}`);
  }

  return response.json();
}

app.get('/turnstile/challenge', (req, res) => {
  const action = normalizeTurnstileAction(req.query.action);
  res.type('html').send(
    renderTurnstileHtml({
      siteKey: getTurnstileSiteKey(),
      action,
    })
  );
});

app.post('/turnstile/verify', turnstileLimiter, async (req, res) => {
  try {
    const token = typeof req.body?.token === 'string' ? req.body.token.trim() : '';
    const action = normalizeTurnstileAction(req.body?.action);

    if (!token) {
      return res.status(400).json({ error: 'Missing turnstile token' });
    }

    if (!getTurnstileSiteKey() || !getTurnstileSecretKey()) {
      return res.status(503).json({ error: 'Turnstile is not configured on the server' });
    }

    const result = await verifyTurnstileToken({
      token,
      remoteIp: getRemoteIp(req),
    });

    if (!result.success) {
      return res.status(400).json({
        error: 'Captcha verification failed',
        codes: Array.isArray(result['error-codes']) ? result['error-codes'] : [],
      });
    }

    if (result.action && result.action !== action) {
      return res.status(400).json({ error: 'Captcha action mismatch' });
    }

    return res.json({ success: true });
  } catch (err) {
    console.error('Unhandled error in /turnstile/verify', err);
    return res.status(500).json({ error: 'Turnstile verification failed' });
  }
});

function getBearerToken(req) {
  const auth = req.headers.authorization || '';
  if (!auth.startsWith('Bearer ')) return null;
  return auth.slice(7).trim();
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