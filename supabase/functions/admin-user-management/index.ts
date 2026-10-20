import { withSupabase } from "npm:@supabase/server@1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function validPassword(value: unknown) {
  return typeof value === "string" && value.length >= 8;
}

export default {
  fetch: withSupabase({ auth: "user" }, async (req, ctx) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

    const callerId = ctx.userClaims?.sub;
    if (!callerId) return json({ error: "Authentication required" }, 401);

    const { data: profile, error: profileError } = await ctx.supabase
      .from("profiles")
      .select("role,full_name")
      .eq("id", callerId)
      .single();

    if (profileError || profile?.role !== "admin") {
      return json({ error: "Admin access required" }, 403);
    }

    let body: any;
    try {
      body = await req.json();
    } catch {
      return json({ error: "Invalid JSON request" }, 400);
    }

    const action = body?.action;

    if (action === "listUsers") {
      const result = await ctx.supabaseAdmin.auth.admin.listUsers({ page: 1, perPage: 1000 });
      if (result.error) return json({ error: result.error.message }, 400);

      const { data: profiles, error: profilesError } = await ctx.supabaseAdmin
        .from("profiles")
        .select("id,role,full_name,phone");

      if (profilesError) return json({ error: profilesError.message }, 400);

      const profileMap = new Map((profiles || []).map((p: any) => [p.id, p]));

      const users = (result.data.users || []).map((u: any) => {
        const p = profileMap.get(u.id);
        return {
          id: u.id,
          email: u.email || "",
          phone: u.phone || "",
          role: p?.role || u.user_metadata?.role || "unassigned",
          full_name: p?.full_name || u.user_metadata?.full_name || "",
          created_at: u.created_at,
          last_sign_in_at: u.last_sign_in_at || null,
          confirmed: Boolean(u.email_confirmed_at || u.phone_confirmed_at),
          active: !(u.banned_until && new Date(u.banned_until).getTime() > Date.now()),
        };
      });

      return json({ users });
    }

    if (action === "updatePassword") {
      const userId = String(body?.userId || "");
      const password = body?.password;

      if (!userId) return json({ error: "User ID is required" }, 400);
      if (!validPassword(password)) {
        return json({ error: "Password must be at least 8 characters" }, 400);
      }

      const result = await ctx.supabaseAdmin.auth.admin.updateUserById(
        userId,
        { password }
      );

      if (result.error) return json({ error: result.error.message }, 400);
      return json({ ok: true, message: "Password updated successfully" });
    }

    if (action === "createUser") {
      const role = String(body?.role || "").toLowerCase();
      const password = body?.password;
      const fullName = String(body?.fullName || "").trim();

      if (!validPassword(password)) {
        return json({ error: "Password must be at least 8 characters" }, 400);
      }
      if (!["patient", "doctor", "admin"].includes(role)) {
        return json({ error: "Invalid role" }, 400);
      }
      if (!fullName) return json({ error: "Full name is required" }, 400);

      const attrs: any = {
        password,
        email_confirm: role === "admin",
        phone_confirm: role !== "admin",
        user_metadata: { full_name: fullName, role },
      };

      if (role === "admin") {
        const email = String(body?.email || "").trim().toLowerCase();
        if (!email) return json({ error: "Admin email is required" }, 400);
        attrs.email = email;
      } else {
        const phone = String(body?.phone || "").trim();
        if (!phone) return json({ error: "Mobile number is required" }, 400);
        attrs.phone = phone;
      }

      const created = await ctx.supabaseAdmin.auth.admin.createUser(attrs);
      if (created.error) return json({ error: created.error.message }, 400);

      const user = created.data.user;
      if (!user) return json({ error: "User was not created" }, 400);

      const { error: profileInsertError } = await ctx.supabaseAdmin
        .from("profiles")
        .insert({
          id: user.id,
          role,
          full_name: fullName,
          phone: role === "admin" ? null : String(body?.phone || "").trim(),
        });

      if (profileInsertError) {
        await ctx.supabaseAdmin.auth.admin.deleteUser(user.id);
        return json({ error: profileInsertError.message }, 400);
      }

      if (role === "doctor") {
        const doctorCode = String(body?.doctorCode || "").toLowerCase();
        if (!["reshma", "op"].includes(doctorCode)) {
          await ctx.supabaseAdmin.auth.admin.deleteUser(user.id);
          await ctx.supabaseAdmin.from("profiles").delete().eq("id", user.id);
          return json({ error: "Doctor code must be reshma or op" }, 400);
        }

        const { data: doctor, error: doctorReadError } = await ctx.supabaseAdmin
          .from("doctors")
          .select("id,user_id")
          .eq("doctor_code", doctorCode)
          .single();

        if (doctorReadError) {
          await ctx.supabaseAdmin.auth.admin.deleteUser(user.id);
          await ctx.supabaseAdmin.from("profiles").delete().eq("id", user.id);
          return json({ error: doctorReadError.message }, 400);
        }

        if (doctor.user_id && doctor.user_id !== user.id) {
          await ctx.supabaseAdmin.auth.admin.deleteUser(user.id);
          await ctx.supabaseAdmin.from("profiles").delete().eq("id", user.id);
          return json({ error: "That doctor account is already linked to another Auth user." }, 400);
        }

        const { error: doctorError } = await ctx.supabaseAdmin
          .from("doctors")
          .update({
            user_id: user.id,
            phone: String(body?.phone || "").trim(),
            active: true,
          })
          .eq("doctor_code", doctorCode);

        if (doctorError) {
          await ctx.supabaseAdmin.auth.admin.deleteUser(user.id);
          await ctx.supabaseAdmin.from("profiles").delete().eq("id", user.id);
          return json({ error: doctorError.message }, 400);
        }
      }

      if (role === "patient") {
        const phone = String(body?.phone || "").trim();
        const { data: existingPatient } = await ctx.supabaseAdmin
          .from("patients")
          .select("id,user_id")
          .eq("phone", phone)
          .maybeSingle();

        if (existingPatient?.user_id && existingPatient.user_id !== user.id) {
          await ctx.supabaseAdmin.auth.admin.deleteUser(user.id);
          await ctx.supabaseAdmin.from("profiles").delete().eq("id", user.id);
          return json({ error: "A patient already uses this mobile number." }, 400);
        }

        const patientWrite = existingPatient?.id
          ? await ctx.supabaseAdmin.from("patients").update({
              user_id: user.id,
              full_name: fullName,
              phone,
              updated_at: new Date().toISOString(),
            }).eq("id", existingPatient.id)
          : await ctx.supabaseAdmin.from("patients").insert({
              user_id: user.id,
              full_name: fullName,
              phone,
            });

        if (patientWrite.error) {
          await ctx.supabaseAdmin.auth.admin.deleteUser(user.id);
          await ctx.supabaseAdmin.from("profiles").delete().eq("id", user.id);
          return json({ error: patientWrite.error.message }, 400);
        }
      }

      return json({ ok: true, user: { id: user.id, role, full_name: fullName } });
    }



    if (action === "listDoctors") {
      const { data, error } = await ctx.supabaseAdmin
        .from("doctors")
        .select("id,doctor_code,full_name,qualification,phone,user_id,active")
        .order("doctor_code");

      if (error) return json({ error: error.message }, 400);

      return json({
        doctors: (data || []).map((d: any) => ({
          id: d.id,
          doctor_code: d.doctor_code,
          full_name: d.full_name,
          qualification: d.qualification,
          phone: d.phone || "",
          user_id: d.user_id || null,
          active: d.active,
        })),
      });
    }

    if (action === "updatePatient") {
      const patientId = String(body?.patientId || "");
      const fullName = String(body?.fullName || "").trim();
      const phone = String(body?.phone || "").trim();

      if (!patientId || !fullName) {
        return json({ error: "Patient ID and full name are required" }, 400);
      }
      if (phone.replace(/\D/g, "").length < 10) {
        return json({ error: "Valid 10-digit mobile number is required" }, 400);
      }

      const { data: patient, error: patientReadError } = await ctx.supabaseAdmin
        .from("patients")
        .select("id,user_id")
        .eq("id", patientId)
        .single();

      if (patientReadError) return json({ error: patientReadError.message }, 400);

      const { error: patientUpdateError } = await ctx.supabaseAdmin
        .from("patients")
        .update({
          full_name: fullName,
          phone,
          updated_at: new Date().toISOString(),
        })
        .eq("id", patientId);

      if (patientUpdateError) return json({ error: patientUpdateError.message }, 400);

      if (patient.user_id) {
        const authUpdate = await ctx.supabaseAdmin.auth.admin.updateUserById(
          patient.user_id,
          { phone, user_metadata: { full_name: fullName, role: "patient" } }
        );
        if (authUpdate.error) return json({ error: authUpdate.error.message }, 400);
      }

      if (patient.user_id) {
        await ctx.supabaseAdmin
          .from("profiles")
          .upsert({
            id: patient.user_id,
            role: "patient",
            full_name: fullName,
            phone,
          });
      }

      return json({ ok: true, message: "Patient details updated" });
    }

    if (action === "updateDoctor") {
      const doctorId = String(body?.doctorId || "");
      const phone = String(body?.phone || "").trim();
      const active = body?.active !== false;

      if (!doctorId) return json({ error: "Doctor ID is required" }, 400);
      if (phone.replace(/\D/g, "").length < 10) {
        return json({ error: "Valid 10-digit mobile number is required" }, 400);
      }

      const { data: doctor, error: doctorReadError } = await ctx.supabaseAdmin
        .from("doctors")
        .select("id,user_id")
        .eq("id", doctorId)
        .single();

      if (doctorReadError) return json({ error: doctorReadError.message }, 400);

      const { error: doctorUpdateError } = await ctx.supabaseAdmin
        .from("doctors")
        .update({
          phone,
          active,
        })
        .eq("id", doctorId);

      if (doctorUpdateError) return json({ error: doctorUpdateError.message }, 400);

      if (doctor.user_id) {
        const authUpdate = await ctx.supabaseAdmin.auth.admin.updateUserById(
          doctor.user_id,
          { phone }
        );
        if (authUpdate.error) return json({ error: authUpdate.error.message }, 400);
      }

      return json({ ok: true, message: "Doctor account updated" });
    }

    if (action === "setUserActive") {
      const userId = String(body?.userId || "");
      const active = Boolean(body?.active);

      if (!userId) return json({ error: "User ID is required" }, 400);
      if (userId === callerId && !active) {
        return json({ error: "You cannot disable your own admin account here." }, 400);
      }

      const result = await ctx.supabaseAdmin.auth.admin.updateUserById(
        userId,
        { ban_duration: active ? "none" : "876000h" }
      );

      if (result.error) return json({ error: result.error.message }, 400);
      return json({ ok: true, message: active ? "User enabled" : "User disabled" });
    }

    return json({ error: "Unsupported action" }, 400);
  }),
};
