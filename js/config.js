// Supabase public browser configuration for Aaradhya's Homoeopathy.
// The publishable key is safe to use in browser code when RLS is configured.
// Never place the database password or secret/service-role key here.

const SUPABASE_URL = "https://frjxsybhycfyzvywwmlt.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_gVote-0exfIDEFFEMOZVWQ_bB2ORMEq";

if (!window.supabase || !window.supabase.createClient) {
  throw new Error("Supabase JS library is not loaded. Load @supabase/supabase-js before config.js.");
}

const supabaseClient = window.supabase.createClient(
  SUPABASE_URL,
  SUPABASE_PUBLISHABLE_KEY,
  { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true } }
);

// Compatibility helpers while the pages are being migrated from Apps Script.
async function apiGet(action, params = {}) {
  try {
    if (action === "appointments") {
      let q = supabaseClient
        .from("appointments")
        .select("id,appointment_code,appointment_date,appointment_time,duration_minutes,reason,mode,payment_preference,payment_status,status,meet_link,patient_id,doctor_id, patients(full_name,phone), doctors(doctor_code,full_name)")
        .order("appointment_date", { ascending: true })
        .order("appointment_time", { ascending: true });

      if (params.doctor) q = q.eq("doctors.doctor_code", params.doctor);
      if (params.patientMobile) q = q.eq("patients.phone", params.patientMobile);

      const { data, error } = await q;
      if (error) throw error;

      return {
        configured: true, ok: true,
        data: (data || []).map(a => ({
          "Appointment ID": a.id,
          "Appointment Code": a.appointment_code,
          "Patient ID": a.patient_id,
          "Patient Name": a.patients?.full_name || "",
          "Mobile": a.patients?.phone || "",
          "Doctor": a.doctors?.doctor_code || "",
          "Doctor Name": a.doctors?.full_name || "",
          "Date": a.appointment_date,
          "Time": String(a.appointment_time || "").slice(0,5),
          "Duration": a.duration_minutes,
          "Reason": a.reason || "",
          "Mode": a.mode || "",
          "Payment Preference": a.payment_preference || "",
          "Payment Status": a.payment_status || "",
          "Status": a.status || "",
          "Meet Link": a.meet_link || ""
        }))
      };
    }

    if (action === "prescriptions") {
      let q = supabaseClient
        .from("prescriptions")
        .select("id,prescription_code,patient_id,doctor_id,complaints,diagnosis,advice,document_path,pdf_path,created_at,doctors(doctor_code,full_name)")
        .order("created_at", { ascending: false });

      if (params.patientId) q = q.eq("patient_id", params.patientId);
      if (params.doctorId) q = q.eq("doctor_id", params.doctorId);

      const { data, error } = await q;
      if (error) throw error;

      return {
        configured: true, ok: true,
        data: (data || []).map(r => ({
          "Prescription ID": r.id,
          "Prescription Code": r.prescription_code,
          "Patient ID": r.patient_id,
          "Doctor": r.doctors?.doctor_code || r.doctors?.full_name || "",
          "Date": r.created_at ? r.created_at.slice(0,10) : "",
          "Complaints": r.complaints || "",
          "Diagnosis": r.diagnosis || "",
          "Advice": r.advice || "",
          "Document Path": r.document_path || "",
          "PDF Path": r.pdf_path || ""
        }))
      };
    }

    if (action === "availability") {
      let q = supabaseClient.from("availability").select("*, doctors(doctor_code,full_name)")
        .eq("active", true).order("availability_date").order("start_time");
      if (params.doctor) q = q.eq("doctors.doctor_code", params.doctor);
      const { data, error } = await q;
      if (error) throw error;
      return { configured:true, ok:true, data:data || [] };
    }

    return { configured:true, ok:false, error:"Unsupported action: "+action };
  } catch (error) {
    return { configured:true, ok:false, error:error.message || String(error) };
  }
}

async function apiPost(action, data = {}) {
  try {
    if (action === "bookAppointment") {
      const { data: result, error } = await supabaseClient.rpc("book_appointment_public", {
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
      return { configured:true, ok:true, appointment: result };
    }

    if (action === "setAvailability") {
      const { data: doctorRow, error: doctorError } = await supabaseClient
        .from("doctors").select("id").eq("doctor_code", data.doctor).single();
      if (doctorError) throw doctorError;

      const { data: row, error } = await supabaseClient
        .from("availability")
        .upsert({
          doctor_id: doctorRow.id,
          availability_date: data.date,
          start_time: data.startTime,
          end_time: data.endTime,
          slot_duration: data.slotDuration || 15,
          active: true
        }, { onConflict: "doctor_id,availability_date,start_time,end_time" })
        .select().single();
      if (error) throw error;
      return { configured:true, ok:true, availability: row };
    }

    if (action === "createOrder") {
      const { data: row, error } = await supabaseClient.from("medicine_orders").insert(data).select().single();
      if (error) throw error;
      return { configured:true, ok:true, order:row };
    }

    return { configured:true, ok:false, error:"Unsupported action: "+action };
  } catch (error) {
    return { configured:true, ok:false, error:error.message || String(error) };
  }
}

function to24Hour(value) {
  const m = String(value || "").trim().match(/^(\d{1,2}):(\d{2})\s*(AM|PM)$/i);
  if (!m) return value;
  let h = Number(m[1]), min = m[2], ap = m[3].toUpperCase();
  if (ap === "PM" && h !== 12) h += 12;
  if (ap === "AM" && h === 12) h = 0;
  return String(h).padStart(2,"0")+":"+min;
}
