// Supabase configuration for Aaradhya's Homoeopathy.
// The publishable key is intended for browser use. RLS is required for data protection.
// Never put the database password or Supabase secret/service-role key here.

const SUPABASE_URL = "https://frjxsybhycfyzvywwmlt.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_gVote-0exfIDEFFEMOZVWQ_bB2ORMEq";

let supabaseClient = null;

function loadSupabaseJs() {
  if (window.supabase && window.supabase.createClient) return Promise.resolve();
  if (window.__supabaseScriptPromise) return window.__supabaseScriptPromise;

  window.__supabaseScriptPromise = new Promise((resolve, reject) => {
    const s = document.createElement("script");
    s.src = "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2";
    s.onload = resolve;
    s.onerror = () => reject(new Error("Unable to load Supabase JS library."));
    document.head.appendChild(s);
  });
  return window.__supabaseScriptPromise;
}

async function getSupabaseClient() {
  await loadSupabaseJs();
  if (!supabaseClient) {
    supabaseClient = window.supabase.createClient(
      SUPABASE_URL,
      SUPABASE_PUBLISHABLE_KEY,
      {
        auth: {
          persistSession: true,
          autoRefreshToken: true,
          detectSessionInUrl: true
        }
      }
    );
  }
  return supabaseClient;
}

// Pages can await this before doing auth work.
const supabaseReady = getSupabaseClient();

async function apiGet(action, params = {}) {
  try {
    const sb = await getSupabaseClient();

    if (action === "appointments") {
      const { data, error } = await sb.rpc("get_my_appointments");
      if (error) throw error;

      const rows = Array.isArray(data) ? data : [];
      return {
        configured: true,
        ok: true,
        data: rows.map(a => ({
          "Appointment ID": a["Appointment ID"] || "",
          "Appointment Code": a["Appointment Code"] || "",
          "Patient ID": a["Patient ID"] || "",
          "Patient Name": a["Patient Name"] || "",
          "Mobile": a["Mobile"] || "",
          "Doctor": a["Doctor"] || "",
          "Doctor Name": a["Doctor Name"] || "",
          "Date": a["Date"] || "",
          "Time": String(a["Time"] || "").slice(0, 5),
          "Duration": a["Duration"] || 15,
          "Reason": a["Reason"] || "",
          "Mode": a["Mode"] || "",
          "Payment Preference": a["Payment Preference"] || "",
          "Payment Status": a["Payment Status"] || "",
          "Status": a["Status"] || "",
          "Meet Link": a["Meet Link"] || ""
        }))
      };
    }

    if (action === "prescriptions") {
      let q = sb
        .from("prescriptions")
        .select("id,prescription_code,patient_id,doctor_id,complaints,diagnosis,advice,document_path,pdf_path,created_at,doctors(doctor_code,full_name)")
        .order("created_at", { ascending: false });

      if (params.patientId) q = q.eq("patient_id", params.patientId);
      if (params.doctorId) q = q.eq("doctor_id", params.doctorId);

      const { data, error } = await q;
      if (error) throw error;

      return {
        configured: true,
        ok: true,
        data: (data || []).map(r => ({
          "Prescription ID": r.id,
          "Prescription Code": r.prescription_code,
          "Patient ID": r.patient_id,
          "Doctor": r.doctors?.doctor_code || r.doctors?.full_name || "",
          "Date": r.created_at ? r.created_at.slice(0, 10) : "",
          "Complaints": r.complaints || "",
          "Diagnosis": r.diagnosis || "",
          "Advice": r.advice || "",
          "Document Path": r.document_path || "",
          "PDF Path": r.pdf_path || ""
        }))
      };
    }

    if (action === "availability") {
      let q = sb
        .from("availability")
        .select("id,doctor_id,availability_date,start_time,end_time,slot_duration,doctors!inner(doctor_code,full_name)")
        .eq("active", true)
        .order("availability_date")
        .order("start_time");

      if (params.doctor) q = q.eq("doctors.doctor_code", params.doctor);

      const { data, error } = await q;
      if (error) throw error;
      return { configured: true, ok: true, data: data || [] };
    }

    return { configured: true, ok: false, error: "Unsupported action: " + action };
  } catch (error) {
    return { configured: true, ok: false, error: error.message || String(error) };
  }
}

async function apiPost(action, data = {}) {
  try {
    const sb = await getSupabaseClient();

    if (action === "bookAppointment") {
      const { data: result, error } = await sb.rpc("book_appointment_public", {
        p_doctor_code: data.doctor,
        p_full_name: data.name,
        p_phone: data.mobile || data.phone,
        p_appointment_date: data.date,
        p_appointment_time: to24Hour(data.time),
        p_reason: data.reason || null,
        p_mode: data.mode || "offline",
        p_payment_preference: data.payment || null
      });
      if (error) throw error;
      return { configured: true, ok: true, appointment: result };
    }

    if (action === "setAvailability") {
      const { data: doctorRow, error: doctorError } = await sb.rpc("get_my_doctor");
      if (doctorError) throw doctorError;

      const { data: row, error } = await sb
        .from("availability")
        .upsert({
          doctor_id: doctorRow.doctorId,
          availability_date: data.date,
          start_time: data.startTime,
          end_time: data.endTime,
          slot_duration: data.slotDuration || 15,
          active: true
        }, { onConflict: "doctor_id,availability_date,start_time,end_time" })
        .select()
        .single();
      if (error) throw error;
      return { configured: true, ok: true, availability: row };
    }

    if (action === "createPrescription") {
      const { data: userResult, error: userError } = await sb.auth.getUser();
      if (userError || !userResult.user) throw new Error("Please sign in as a doctor first.");

      const { data: doctorRow, error: doctorError } = await sb
        .from("doctors")
        .select("id,full_name")
        .eq("user_id", userResult.user.id)
        .eq("active", true)
        .single();
      if (doctorError) throw doctorError;

      const { data: rx, error: rxError } = await sb
        .from("prescriptions")
        .insert({
          appointment_id: data.appointmentId,
          patient_id: data.patientId,
          doctor_id: doctorRow.id,
          complaints: data.complaints || null,
          diagnosis: data.diagnosis || null,
          advice: data.advice || null
        })
        .select()
        .single();
      if (rxError) throw rxError;

      const medicines = Array.isArray(data.medicines) ? data.medicines.filter(m => m.name) : [];
      if (medicines.length) {
        const { error: medError } = await sb
          .from("prescription_medicines")
          .insert(medicines.map((m, i) => ({
            prescription_id: rx.id,
            medicine_name: m.name,
            dose: m.dose || null,
            frequency: m.frequency || null,
            instructions: m.instructions || null,
            sort_order: i
          })));
        if (medError) {
          await sb.from("prescriptions").delete().eq("id", rx.id);
          throw medError;
        }
      }

      return { configured: true, ok: true, prescription: rx };
    }

    if (action === "createOrder") {
      const { data: userResult, error: userError } = await sb.auth.getUser();
      if (userError || !userResult.user) throw new Error("Please sign in first.");

      const { data: patientRow, error: patientError } = await sb
        .from("patients")
        .select("id")
        .eq("user_id", userResult.user.id)
        .single();
      if (patientError) throw patientError;

      const { data: row, error } = await sb
        .from("medicine_orders")
        .insert({...data, patient_id: patientRow.id})
        .select()
        .single();
      if (error) throw error;
      return { configured: true, ok: true, order: row };
    }

    return { configured: true, ok: false, error: "Unsupported action: " + action };
  } catch (error) {
    return { configured: true, ok: false, error: error.message || String(error) };
  }
}

function to24Hour(value) {
  const m = String(value || "").trim().match(/^(\d{1,2}):(\d{2})\s*(AM|PM)$/i);
  if (!m) return value;

  let h = Number(m[1]);
  const min = m[2];
  const ap = m[3].toUpperCase();

  if (ap === "PM" && h !== 12) h += 12;
  if (ap === "AM" && h === 12) h = 0;

  return String(h).padStart(2, "0") + ":" + min;
}


async function adminApi(action, data = {}) {
  try {
    const sb = await getSupabaseClient();
    const sessionResult = await sb.auth.getSession();
    if (sessionResult.error) throw sessionResult.error;
    const accessToken = sessionResult.data.session && sessionResult.data.session.access_token;
    if (!accessToken) throw new Error("Authentication required");

    const { data: result, error } = await sb.functions.invoke("admin-user-management", {
      body: { action, ...data },
      headers: { Authorization: "Bearer " + accessToken }
    });
    if (error) {
      let message = error.message || "Admin operation failed.";
      try {
        const details = await error.context?.json?.();
        if (details?.error) message = details.error;
      } catch (_) {}
      return { ok: false, error: message };
    }
    return result || { ok: true };
  } catch (error) {
    return { ok: false, error: error.message || String(error) };
  }
}
