-- Aaradhya's Homoeopathy
-- ADMIN TEST MODE
-- Allows the existing Admin Auth account to test Patient and Doctor portals
-- without changing public.profiles.role or overwriting real doctor user links.
-- Run once in Supabase SQL Editor.

create table if not exists public.admin_test_portal (
  user_id uuid primary key references auth.users(id) on delete cascade,
  portal_role text not null check (portal_role in ('patient','doctor')),
  doctor_code text,
  updated_at timestamptz not null default now()
);

alter table public.admin_test_portal enable row level security;

drop policy if exists "admin test own select" on public.admin_test_portal;
create policy "admin test own select"
on public.admin_test_portal
for select
to authenticated
using (user_id = auth.uid());

create index if not exists admin_test_portal_role_idx
  on public.admin_test_portal(portal_role);

create or replace function public.get_admin_test_portal()
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(
    (
      select jsonb_build_object(
        'portalRole', portal_role,
        'doctorCode', doctor_code
      )
      from public.admin_test_portal
      where user_id = auth.uid()
    ),
    jsonb_build_object('portalRole', null, 'doctorCode', null)
  );
$$;

create or replace function public.set_admin_test_portal(
  p_portal_role text,
  p_doctor_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_phone text;
  v_name text;
  v_email text;
  v_doctor public.doctors%rowtype;
  v_patient public.patients%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select role into v_role
  from public.profiles
  where id = auth.uid();

  if v_role <> 'admin' then
    raise exception 'Only an admin account can use test mode';
  end if;

  if p_portal_role not in ('patient','doctor') then
    raise exception 'Invalid test portal role';
  end if;

  if p_portal_role = 'doctor' then
    if lower(trim(coalesce(p_doctor_code,''))) not in ('reshma','op') then
      raise exception 'Choose Dr. Reshma Singh or Dr. O.P. Singh for test mode';
    end if;

    select * into v_doctor
    from public.doctors
    where doctor_code = lower(trim(p_doctor_code))
      and active = true
    limit 1;

    if not found then
      raise exception 'Selected doctor is not active';
    end if;
  end if;

  select
    coalesce((select phone from auth.users where id=auth.uid()), ''),
    coalesce((select raw_user_meta_data->>'full_name' from auth.users where id=auth.uid()), 'Admin Test User'),
    coalesce((select email from auth.users where id=auth.uid()), '')
  into v_phone, v_name, v_email;

  if p_portal_role = 'patient' then
    select * into v_patient
    from public.patients
    where user_id = auth.uid()
    limit 1;

    if not found then
      insert into public.patients (
        user_id,
        patient_code,
        full_name,
        phone,
        email
      )
      values (
        auth.uid(),
        'TEST-ADMIN-' || upper(substr(replace(auth.uid()::text,'-',''),1,8)),
        coalesce(nullif(trim(v_name),''),'Admin Test Patient'),
        case
          when public.normalize_phone(v_phone) <> ''
          then public.normalize_phone(v_phone)
          else '9999900000'
        end,
        nullif(v_email,'')
      )
      returning * into v_patient;
    end if;
  end if;

  insert into public.admin_test_portal(user_id, portal_role, doctor_code, updated_at)
  values(auth.uid(), p_portal_role, case when p_portal_role='doctor' then lower(trim(p_doctor_code)) else null end, now())
  on conflict (user_id)
  do update set
    portal_role = excluded.portal_role,
    doctor_code = excluded.doctor_code,
    updated_at = now();

  return jsonb_build_object(
    'portalRole', p_portal_role,
    'doctorCode', case when p_portal_role='doctor' then lower(trim(p_doctor_code)) else null end
  );
end;
$$;

create or replace function public.clear_admin_test_portal()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  delete from public.admin_test_portal
  where user_id = auth.uid();

  return jsonb_build_object('cleared', true);
end;
$$;

revoke all on function public.get_admin_test_portal() from public;
grant execute on function public.get_admin_test_portal() to authenticated;

revoke all on function public.set_admin_test_portal(text,text) from public;
grant execute on function public.set_admin_test_portal(text,text) to authenticated;

revoke all on function public.clear_admin_test_portal() from public;
grant execute on function public.clear_admin_test_portal() to authenticated;


-- Make the identity helpers test-mode aware.
create or replace function public.current_patient_id()
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(
    (
      select p.id
      from public.patients p
      join public.admin_test_portal t on t.user_id = auth.uid()
      where t.portal_role = 'patient'
        and p.user_id = auth.uid()
      limit 1
    ),
    (
      select id
      from public.patients
      where user_id = auth.uid()
      limit 1
    )
  );
$$;

create or replace function public.current_doctor_id()
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(
    (
      select d.id
      from public.doctors d
      join public.admin_test_portal t on t.user_id = auth.uid()
      where t.portal_role = 'doctor'
        and d.doctor_code = t.doctor_code
        and d.active = true
      limit 1
    ),
    (
      select id
      from public.doctors
      where user_id = auth.uid()
        and active = true
      limit 1
    )
  );
$$;


-- Patient claim now supports the admin account while in explicit test mode.
create or replace function public.claim_patient_account()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.normalize_phone(coalesce((select phone from auth.users where id = auth.uid()), ''));
  v_patient public.patients%rowtype;
  v_role text;
  v_name text;
  v_email text;
  v_test_role text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select role into v_role
  from public.profiles
  where id = auth.uid();

  select portal_role into v_test_role
  from public.admin_test_portal
  where user_id = auth.uid();

  if v_test_role = 'patient' and v_role = 'admin' then
    select * into v_patient
    from public.patients
    where user_id = auth.uid()
    limit 1;

    if not found then
      select
        coalesce((select raw_user_meta_data->>'full_name' from auth.users where id=auth.uid()), 'Admin Test Patient'),
        coalesce((select email from auth.users where id=auth.uid()), '')
      into v_name, v_email;

      insert into public.patients(
        user_id, patient_code, full_name, phone, email
      )
      values(
        auth.uid(),
        'TEST-ADMIN',
        coalesce(nullif(trim(v_name),''),'Admin Test Patient'),
        case when v_phone <> '' then v_phone else '9999900000' end,
        nullif(v_email,'')
      )
      returning * into v_patient;
    end if;

    return jsonb_build_object(
      'patientId', v_patient.id,
      'patientCode', v_patient.patient_code,
      'fullName', v_patient.full_name,
      'phone', v_patient.phone,
      'testMode', true
    );
  end if;

  if v_role in ('doctor', 'admin') then
    raise exception 'This login is not a patient account';
  end if;

  if v_phone = '' then
    raise exception 'Authenticated mobile number is required';
  end if;

  select coalesce(raw_user_meta_data ->> 'full_name', 'Patient')
  into v_name
  from auth.users
  where id = auth.uid();

  select *
  into v_patient
  from public.patients
  where public.normalize_phone(phone) = v_phone
  order by case when user_id = auth.uid() then 0 else 1 end,
           created_at desc
  limit 1;

  if not found then
    insert into public.patients(user_id, full_name, phone)
    values(auth.uid(), coalesce(nullif(trim(v_name), ''), 'Patient'), v_phone)
    returning * into v_patient;
  elsif v_patient.user_id is null or v_patient.user_id = auth.uid() then
    update public.patients
    set user_id = auth.uid(),
        full_name = coalesce(nullif(trim(v_name), ''), full_name),
        phone = v_phone,
        updated_at = now()
    where id = v_patient.id
    returning * into v_patient;
  else
    raise exception 'This mobile number is already linked to another patient account';
  end if;

  insert into public.profiles(id, role, full_name, phone)
  values(auth.uid(), 'patient', v_patient.full_name, v_phone)
  on conflict (id) do update
  set role='patient', full_name=excluded.full_name, phone=excluded.phone;

  return jsonb_build_object(
    'patientId', v_patient.id,
    'patientCode', v_patient.patient_code,
    'fullName', v_patient.full_name,
    'phone', v_patient.phone
  );
end;
$$;

revoke all on function public.claim_patient_account() from public;
grant execute on function public.claim_patient_account() to authenticated;


-- Doctor profile lookup becomes test-mode aware.
create or replace function public.get_my_doctor()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doctor public.doctors%rowtype;
  v_test_role text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select portal_role into v_test_role
  from public.admin_test_portal
  where user_id = auth.uid();

  if v_test_role = 'doctor' then
    select * into v_doctor
    from public.doctors
    where id = public.current_doctor_id()
      and active = true
    limit 1;
  else
    select * into v_doctor
    from public.doctors
    where user_id = auth.uid()
      and active = true
    limit 1;
  end if;

  if not found then
    raise exception 'Doctor account is not linked to this login';
  end if;

  return jsonb_build_object(
    'doctorId', v_doctor.id,
    'doctorCode', v_doctor.doctor_code,
    'fullName', v_doctor.full_name,
    'qualification', v_doctor.qualification,
    'testMode', (v_test_role = 'doctor')
  );
end;
$$;

revoke all on function public.get_my_doctor() from public;
grant execute on function public.get_my_doctor() to authenticated;


-- Appointment visibility becomes test-mode aware while preserving normal behavior.
create or replace function public.get_my_appointments()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_test_role text;
  v_phone text;
  v_doctor_id uuid;
  v_patient_id uuid;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select role into v_role
  from public.profiles
  where id = auth.uid();

  select portal_role into v_test_role
  from public.admin_test_portal
  where user_id = auth.uid();

  if v_test_role is not null and v_role = 'admin' then
    v_role := v_test_role;
  end if;

  if v_role = 'patient' then
    v_patient_id := public.current_patient_id();

    if v_patient_id is null then
      raise exception 'Patient account is not linked to this login';
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
    where a.patient_id = v_patient_id;

    return v_result;
  end if;

  if v_role = 'doctor' then
    v_doctor_id := public.current_doctor_id();

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


-- Public booking RPC becomes test-patient aware.
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
  v_test_role text;
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

  select * into v_doctor
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

  select role into v_auth_role
  from public.profiles
  where id = auth.uid();

  select portal_role into v_test_role
  from public.admin_test_portal
  where user_id = auth.uid();

  if v_auth_role = 'admin' and v_test_role = 'patient' then
    select * into v_patient
    from public.patients
    where user_id = auth.uid()
    limit 1;

    if not found then
      insert into public.patients(user_id, patient_code, full_name, phone)
      values(auth.uid(), 'TEST-ADMIN', trim(p_full_name), v_phone)
      returning * into v_patient;
    end if;

  else
    if v_auth_role = 'patient' then
      select * into v_patient
      from public.patients
      where user_id = auth.uid()
      limit 1;
    end if;

    if v_patient.id is null then
      select * into v_patient
      from public.patients
      where public.normalize_phone(phone) = v_phone
      order by created_at asc
      limit 1;
    end if;

    if v_patient.id is null then
      insert into public.patients(user_id, full_name, phone)
      values(
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
  end if;

  insert into public.appointments(
    patient_id, doctor_id, appointment_date, appointment_time,
    duration_minutes, reason, mode, payment_preference, payment_status, status
  )
  values(
    v_patient.id, v_doctor.id, p_appointment_date, v_time,
    15, p_reason, v_mode, p_payment_preference, 'pending', 'Confirmed'
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
