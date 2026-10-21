import { createClient } from "npm:@supabase/supabase-js@2";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function normalizePhone(value: unknown) {
  const digits = String(value ?? "").replace(/\D/g, "");
  if (digits.length === 10) return "+91" + digits;
  if (digits.length === 12 && digits.startsWith("91")) return "+" + digits;
  return "";
}

export default {
  async fetch(req: Request) {
    if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

    let body: any;
    try {
      body = await req.json();
    } catch {
      return json({ error: "Invalid request" }, 400);
    }

    const role = String(body?.role || "").toLowerCase();
    const phone = normalizePhone(body?.phone);

    if (!["patient", "doctor"].includes(role)) {
      return json({ error: "Invalid reset type" }, 400);
    }

    if (!phone) {
      return json({ error: "Enter a valid 10-digit mobile number" }, 400);
    }

    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");

    if (!url || !serviceKey || !anonKey) {
      return json({ error: "Supabase function configuration is incomplete" }, 500);
    }

    const admin = createClient(url, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // Check the clinic role without revealing account existence to the browser.
    let exists = false;

    if (role === "patient") {
      const { data: patient } = await admin
        .from("patients")
        .select("id")
        .eq("phone", phone)
        .limit(1)
        .maybeSingle();
      exists = Boolean(patient);
    } else {
      const { data: doctor } = await admin
        .from("doctors")
        .select("id")
        .eq("phone", phone)
        .eq("active", true)
        .limit(1)
        .maybeSingle();
      exists = Boolean(doctor);
    }

    // Always return the same public response whether the account exists.
    if (!exists) {
      return json({
        ok: true,
        message: "If an account exists for this mobile number, an OTP has been sent.",
      });
    }

    // Use the public auth key to start the normal Supabase SMS OTP flow.
    const client = createClient(url, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { error } = await client.auth.signInWithOtp({
      phone,
      options: { shouldCreateUser: false },
    });

    if (error) {
      // Keep account enumeration out of the response.
      return json({
        ok: true,
        message: "If an account exists for this mobile number, an OTP has been sent.",
      });
    }

    return json({
      ok: true,
      message: "If an account exists for this mobile number, an OTP has been sent.",
    });
  },
};
