-- Aaradhya's Homoeopathy
-- FINAL APPOINTMENT VISIBILITY / BOOKING FIX
-- Run once in Supabase SQL Editor in a NEW query.

-- Normalize Indian mobile numbers consistently.
create or replace function public.normalize_phone(p_phone text)
returns text
language sql
immutable
as $$
  select regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
$$;

-- Securely return the current user's appointments.
-- Patient: matches the authenticated patient account by normalized mobile.
-- Doctor: matches the doctor linked to auth.uid().
-- Admin: returns all appointments.
create or replace function public.get_my_appointments()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_phone text;
  v_doctor_id uuid;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select role
    into v_role
  from public.profiles
  where id = auth.uid();

  if v_role = 'patient' then
    select public.normalize_phone(phone)
      into v_phone
    from auth.users
    where id = auth.uid();

    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'Appointment ID', a.id,
          'Appointment Code', a.appointment_code,
          'Patient ID', a.patient_id,
          'Patient Name', p.full_name,
          'Mobile', p.phone,
          'Doctor', d.doctor_code,
          'Doctor Name', d.full_name,
          'Date', a.appointment_date,
          'Time', to_char(a.appointment_time, 'HH24:MI'),
          'Duration', a.duration_minutes,
          'Reason', a.reason,
          'Mode', a.mode,
          'Payment Preference', a.payment_preference,
          'Payment Status', a.payment_status,
          'Status', a.status,
          'Meet Link', a.meet_link
        )
        order by a.appointment_date asc, a.appointment_time asc
      ),
      '[]'::jsonb
    )
    into v_result
    from public.appointments a
    join public.patients p on p.id = a.patient_id
    join public.doctors d on d.id = a.doctor_id
    where public.normalize_phone(p.phone) = coalesce(v_phone, '');

    return v_result;
  end if;

  if v_role = 'doctor' then
    select id
      into v_doctor_id
    from public.doctors
    where user_id = auth.uid()
      and active = true
    limit 1;

    if v_doctor_id is null then
      raise exception 'Doctor account is not linked to this login';
    end if;

    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'Appointment ID', a.id,
          'Appointment Code', a.appointment_code,
          'Patient ID', a.patient_id,
          'Patient Name', p.full_name,
          'Mobile', p.phone,
          'Doctor', d.doctor_code,
          'Doctor Name', d.full_name,
          'Date', a.appointment_date,
          'Time', to_char(a.appointment_time, 'HH24:MI'),
          'Duration', a.duration_minutes,
          'Reason', a.reason,
          'Mode', a.mode,
          'Payment Preference', a.payment_preference,
          'Payment Status', a.payment_status,
          'Status', a.status,
          'Meet Link', a.meet_link
        )
        order by a.appointment_date asc, a.appointment_time asc
      ),
      '[]'::jsonb
    )
    into v_result
    from public.appointments a
    join public.patients p on p.id = a.patient_id
    join public.doctors d on d.id = a.doctor_id
    where a.doctor_id = v_doctor_id;

    return v_result;
  end if;

  if v_role = 'admin' then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'Appointment ID', a.id,
          'Appointment Code', a.appointment_code,
          'Patient ID', a.patient_id,
          'Patient Name', p.full_name,
          'Mobile', p.phone,
          'Doctor', d.doctor_code,
          'Doctor Name', d.full_name,
          'Date', a.appointment_date,
          'Time', to_char(a.appointment_time, 'HH24:MI'),
          'Duration', a.duration_minutes,
          'Reason', a.reason,
          'Mode', a.mode,
          'Payment Preference', a.payment_preference,
          'Payment Status', a.payment_status,
          'Status', a.status,
          'Meet Link', a.meet_link
        )
        order by a.appointment_date asc, a.appointment_time asc
      ),
      '[]'::jsonb
    )
    into v_result
    from public.appointments a
    join public.patients p on p.id = a.patient_id
    join public.doctors d on d.id = a.doctor_id;

    return v_result;
  end if;

  raise exception 'Unsupported account role';
end;
$$;

revoke all on function public.get_my_appointments() from public;
grant execute on function public.get_my_appointments() to authenticated;


-- Public booking RPC.
-- If the patient is already authenticated, reuse their patient row.
-- For anonymous booking, match/create a patient by mobile.
create or replace function public.book_appointment_public(
  p_doctor_code text,
  p_full_name text,
  p_phone text,
  p_appointment_date date,
  p_appointment_time text,
  p_reason text default null,
  p_mode text default 'offline',
  p_payment_preference text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doctor public.doctors%rowtype;
  v_patient public.patients%rowtype;
  v_appointment public.appointments%rowtype;
  v_mode text := p_mode;
  v_time time := p_appointment_time::time;
  v_dow integer := extract(dow from p_appointment_date);
  v_now_ist timestamptz := timezone('Asia/Kolkata', now());
  v_auth_role text;
  v_phone text := public.normalize_phone(p_phone);
begin
  if p_appointment_date < v_now_ist::date
     or (p_appointment_date = v_now_ist::date and v_time < v_now_ist::time) then
    raise exception 'Please choose a future appointment slot';
  end if;

  if nullif(trim(p_full_name), '') is null then
    raise exception 'Patient name is required';
  end if;

  if length(v_phone) <> 10 then
    raise exception 'Enter a valid 10-digit mobile number';
  end if;

  select *
    into v_doctor
  from public.doctors
  where doctor_code = lower(trim(p_doctor_code))
    and active = true;

  if not found then
    raise exception 'Doctor not found';
  end if;

  if v_dow = 0 then
    v_mode := 'online';
    if v_time < time '09:00' or v_time > time '18:45' then
      raise exception 'Sunday slots are available from 9:00 AM to 6:45 PM';
    end if;
  else
    if v_time < time '17:00' or v_time > time '20:45' then
      raise exception 'Monday-Saturday slots are available from 5:00 PM to 8:45 PM';
    end if;

    if v_mode not in ('offline', 'online') then
      v_mode := 'offline';
    end if;
  end if;

  select role
    into v_auth_role
  from public.profiles
  where id = auth.uid();

  -- Prefer the currently authenticated patient.
  if v_auth_role = 'patient' then
    select *
      into v_patient
    from public.patients
    where user_id = auth.uid()
    limit 1;
  end if;

  -- Otherwise match the mobile number.
  if v_patient.id is null then
    select *
      into v_patient
    from public.patients
    where public.normalize_phone(phone) = v_phone
    order by created_at asc
    limit 1;
  end if;

  if v_patient.id is null then
    insert into public.patients (
      user_id,
      full_name,
      phone
    )
    values (
      case when v_auth_role = 'patient' then auth.uid() else null end,
      trim(p_full_name),
      v_phone
    )
    returning * into v_patient;
  elsif v_auth_role = 'patient'
        and (v_patient.user_id is null or v_patient.user_id = auth.uid()) then
    update public.patients
    set user_id = auth.uid(),
        full_name = coalesce(nullif(trim(p_full_name), ''), full_name),
        phone = v_phone,
        updated_at = now()
    where id = v_patient.id
    returning * into v_patient;
  end if;

  insert into public.appointments (
    patient_id,
    doctor_id,
    appointment_date,
    appointment_time,
    duration_minutes,
    reason,
    mode,
    payment_preference,
    payment_status,
    status
  )
  values (
    v_patient.id,
    v_doctor.id,
    p_appointment_date,
    v_time,
    15,
    p_reason,
    v_mode,
    p_payment_preference,
    'pending',
    'Confirmed'
  )
  returning * into v_appointment;

  return jsonb_build_object(
    'appointmentId', v_appointment.id,
    'appointmentCode', v_appointment.appointment_code,
    'patientId', v_patient.id,
    'patientCode', v_patient.patient_code,
    'doctor', v_doctor.doctor_code,
    'status', v_appointment.status
  );

exception
  when unique_violation then
    raise exception 'This slot is already booked. Please choose another slot.';
end;
$$;

revoke all on function public.book_appointment_public(text,text,text,date,text,text,text,text) from public;
grant execute on function public.book_appointment_public(text,text,text,date,text,text,text,text)
to anon, authenticated;


-- Authenticated patient can also explicitly sync a booking saved locally
-- by an earlier version of the website. This uses the authenticated
-- patient's own record, so it cannot attach a booking to another patient.
create or replace function public.sync_my_legacy_booking(
  p_doctor_code text,
  p_appointment_date date,
  p_appointment_time text,
  p_reason text default null,
  p_mode text default 'offline',
  p_payment_preference text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_patient public.patients%rowtype;
  v_doctor public.doctors%rowtype;
  v_appointment public.appointments%rowtype;
  v_time time := p_appointment_time::time;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select *
    into v_patient
  from public.patients
  where user_id = auth.uid()
  limit 1;

  if not found then
    raise exception 'Patient account is not linked to a patient record';
  end if;

  select *
    into v_doctor
  from public.doctors
  where doctor_code = lower(trim(p_doctor_code))
    and active = true;

  if not found then
    raise exception 'Doctor not found';
  end if;

  select *
    into v_appointment
  from public.appointments
  where patient_id = v_patient.id
    and doctor_id = v_doctor.id
    and appointment_date = p_appointment_date
    and appointment_time = v_time
  limit 1;

  if found then
    return jsonb_build_object(
      'appointmentId', v_appointment.id,
      'appointmentCode', v_appointment.appointment_code,
      'patientId', v_patient.id,
      'status', v_appointment.status,
      'alreadyExists', true
    );
  end if;

  insert into public.appointments (
    patient_id,
    doctor_id,
    appointment_date,
    appointment_time,
    duration_minutes,
    reason,
    mode,
    payment_preference,
    payment_status,
    status
  )
  values (
    v_patient.id,
    v_doctor.id,
    p_appointment_date,
    v_time,
    15,
    p_reason,
    case when extract(dow from p_appointment_date) = 0 then 'online' else p_mode end,
    p_payment_preference,
    'pending',
    'Confirmed'
  )
  returning * into v_appointment;

  return jsonb_build_object(
    'appointmentId', v_appointment.id,
    'appointmentCode', v_appointment.appointment_code,
    'patientId', v_patient.id,
    'status', v_appointment.status,
    'alreadyExists', false
  );
end;
$$;

revoke all on function public.sync_my_legacy_booking(text,date,text,text,text,text) from public;
grant execute on function public.sync_my_legacy_booking(text,date,text,text,text,text) to authenticated;
