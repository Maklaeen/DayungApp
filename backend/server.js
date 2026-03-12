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

function getOptionalEnv(name) {
  const value = process.env[name];
  return typeof value === 'string' ? value.trim() : '';
}

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