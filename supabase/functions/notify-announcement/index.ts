// @ts-nocheck
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  try {
    const body = await req.json();
    const notifications = Array.isArray(body?.notifications) ? body.notifications : [];

    if (!notifications.length) {
      return new Response(JSON.stringify({ ok: true, sent: 0 }), { status: 200 });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const serverKey = Deno.env.get("BOhXzlck1keSV4-vubk8sYdghQUB1DQBXwP52-7VBjfHBt1kYSyVTcJ6X-xHClbTlGo-vwZlOOy2nNu5GOobJ5M");
    if (!serverKey) {
      console.warn("FIREBASE_SERVER_KEY not configured; skipping push delivery");
      return new Response(
        JSON.stringify({
          ok: true,
          sent: 0,
          skipped: notifications.length,
          warning: "FIREBASE_SERVER_KEY missing",
        }),
        { status: 200 }
      );
    }

    let sent = 0;

    for (const notification of notifications) {
      const recipientId = notification.recipient_id;
      if (!recipientId) continue;

      const { data: profile, error } = await supabase
        .from("profiles")
        .select("fcm_token")
        .eq("id", recipientId)
        .maybeSingle();

      if (error || !profile?.fcm_token) continue;

      const response = await fetch("https://fcm.googleapis.com/fcm/send", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `key=${serverKey}`,
        },
        body: JSON.stringify({
          to: profile.fcm_token,
          notification: {
            title: notification.title || "New announcement",
            body: notification.body || "You have a new update",
          },
          data: {
            type: notification.type || "announcement",
            announcement_id: String(notification.announcement_id ?? ""),
            recipient_id: recipientId,
          },
        }),
      });

      const result = await response.json();
      if (response.ok && (result.success === 1 || result.message_id)) {
        sent += 1;
      }
    }

    return new Response(JSON.stringify({ ok: true, sent }), { status: 200 });
  } catch (error) {
    return new Response(
      JSON.stringify({ ok: false, error: String(error) }),
      { status: 500 }
    );
  }
});
