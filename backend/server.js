const express = require('express');
const { createClient } = require('@supabase/supabase-js');
const twilio = require('twilio');

const app = express();
app.use(express.json());

// Replace with your actual keys
const supabase = createClient('https://cbplyfoporianakushyz.supabase.co', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNicGx5Zm9wb3JpYW5ha3VzaHl6Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1MDczOTk5MCwiZXhwIjoyMDY2MzE1OTkwfQ.v550RFqVhZU-bR52eK9qQn9Gm24ipe0ys-ZfeYRG9Uw');
const twilioClient = twilio('AC0e05909f595d569da7ec796fd4b20d08', '681f2c9a65abe7bdb5b9f8ee383687be');
const TWILIO_FROM = '+13613012909';

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

app.listen(3000, () => console.log('Server running on port 3000'));