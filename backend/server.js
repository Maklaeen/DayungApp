const express = require('express');
const { createClient } = require('@supabase/supabase-js');
const twilio = require('twilio');

const app = express();
app.use(express.json());

// Use environment variables for secrets
const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);
const twilioClient = twilio(
  process.env.TWILIO_ACCOUNT_SID,
  process.env.TWILIO_AUTH_TOKEN
);
const TWILIO_FROM = process.env.TWILIO_FROM;

app.post('/send-announcement-sms', async (req, res) => {
  const { dayung_unit_id, title, body } = req.body;


  // 1. Get officials
  const { data: unit, error: unitError } = await supabase
    .from('dayung_units')
    .select('president_id, secretary_id, treasurer_id, collector_id')
    .eq('id', dayung_unit_id)
    .maybeSingle();

  if (unitError || !unit) return res.status(500).json({ error: 'Unit not found' });

  const officialIds = [
    unit.president_id,
    unit.secretary_id,
    unit.treasurer_id,
    unit.collector_id,
  ].filter(Boolean);

  // 2. Get members
  const { data: members, error: membersError } = await supabase
    .from('applications')
    .select('user_id')
    .eq('dayung_unit_id', dayung_unit_id)
    .eq('status', 'approved');

  if (membersError) return res.status(500).json({ error: membersError.message });

  const memberIds = members.map(m => m.user_id);
  const allUserIds = Array.from(new Set([...officialIds, ...memberIds]));

   console.log('All user IDs:', allUserIds);

  // 3. Get mobile numbers
  const { data: users, error: usersError } = await supabase
    .from('users')
    .select('mobile_number')
    .in('id', allUserIds);

      console.log('Users with mobile numbers:', users);

  if (usersError) return res.status(500).json({ error: usersError.message });

  // 4. Send SMS
  const message = `[Dayung] ${title}\n${body}`;
  let sent = 0;
  for (const user of users) {
    if (user.mobile_number) {
      try {
        await twilioClient.messages.create({
          body: message,
          from: TWILIO_FROM,
          to: user.mobile_number,
        });
        sent++;
      } catch (err) {
        // Optionally log or handle failed sends
      }
    }
  }

  res.json({ success: true, sent });
});


const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));