-- Aaradhya's Homoeopathy
-- Supabase Auth migration for:
--   Patient = Mobile + Password
--   Doctor  = Mobile + Password
--   Admin   = Email + Password
--
-- Run this file once in Supabase SQL Editor after the original schema.sql.

alter table public.doctors
  add column if not exists phone text;

create or replace function public.normalize_phone(p_phone text)
returns text
language sql
immutable
as $$
  select regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
$$;

drop index if exists doctors_phone_idx;
create unique index doctors_phone_idx
  on public.doctors (public.normalize_phone(phone))
  where phone is not null and public.normalize_phone(phone) <> '';

create index if not exists patients_phone_normalized_idx
  on public.patients (public.normalize_phone(phone));

-- Link the currently authenticated Supabase user to a patient record
-- using the verified Auth phone number.
create or replace function public.claim_patient_account()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text;
  v_patient public.patients%rowtype;
  v_existing_role text;
  v_name text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  v_phone := public.normalize_phone(
    coalesce(
      (select phone from auth.users where id = auth.uid()),
      ''
    )
  );

  if v_phone = '' then
    raise exception 'Authenticated mobile number is required';
  end if;

  v_existing_role := (
    select role from public.profiles where id = auth.uid()
  );

  if v_existing_role in ('doctor', 'admin') then
    raise exception 'This login is not a patient account';
  end if;

  v_name := coalesce(
    (select raw_user_meta_data ->> 'full_name'
     from auth.users
     where id = auth.uid()),
    'Patient'
  );

  select *
  into v_patient
  from public.patients
  where public.normalize_phone(phone) = v_phone
  order by case when user_id = auth.uid() then 0 else 1 end, created_at desc
  limit 1;

  if not found then
    insert into public.patients (user_id, full_name, phone)
    values (auth.uid(), coalesce(nullif(trim(v_name), ''), 'Patient'), v_phone)
    returning * into v_patient;

  elsif v_patient.user_id is null or v_patient.user_id = auth.uid() then
    update public.patients
    set user_id = auth.uid(),
        full_name = case
          when coalesce(nullif(trim(v_name), ''), '') <> '' then trim(v_name)
          else full_name
        end,
        phone = v_phone,
        updated_at = now()
    where id = v_patient.id
    returning * into v_patient;

  else
    raise exception 'This mobile number is already linked to another patient account';
  end if;

  insert into public.profiles (id, role, full_name, phone)
  values (auth.uid(), 'patient', v_patient.full_name, v_phone)
  on conflict (id) do update
  set role = 'patient',
      full_name = excluded.full_name,
      phone = excluded.phone;

  return jsonb_build_object(
    'patientId', v_patient.id,
    'patientCode', v_patient.patient_code,
    'fullName', v_patient.full_name,
    'phone', v_patient.phone
  );
end;
$$;

-- Link the currently authenticated Supabase user to one of the two
-- pre-created doctor records using the doctor's registered mobile number.
create or replace function public.claim_doctor_account_by_phone()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text;
  v_doctor public.doctors%rowtype;
  v_existing_role text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  v_phone := public.normalize_phone(
    coalesce(
      (select phone from auth.users where id = auth.uid()),
      ''
    )
  );

  if v_phone = '' then
    raise exception 'Authenticated mobile number is required';
  end if;

  v_existing_role := (
    select role from public.profiles where id = auth.uid()
  );

  if v_existing_role in ('patient', 'admin') then
    raise exception 'This login is not a doctor account';
  end if;

  select *
  into v_doctor
  from public.doctors
  where public.normalize_phone(phone) = v_phone
    and active = true
  limit 1;

  if not found then
    raise exception 'This mobile number is not registered for a doctor';
  end if;

  if v_doctor.user_id is not null and v_doctor.user_id <> auth.uid() then
    raise exception 'This doctor account is already linked to another login';
  end if;

  update public.doctors
  set user_id = auth.uid()
  where id = v_doctor.id
  returning * into v_doctor;

  insert into public.profiles (id, role, full_name, phone)
  values (auth.uid(), 'doctor', v_doctor.full_name, v_phone)
  on conflict (id) do update
  set role = 'doctor',
      full_name = excluded.full_name,
      phone = excluded.phone;

  return jsonb_build_object(
    'doctorId', v_doctor.id,
    'doctorCode', v_doctor.doctor_code,
    'fullName', v_doctor.full_name,
    'phone', v_phone
  );
end;
$$;

-- Secure doctor profile lookup used by the doctor dashboard.
create or replace function public.get_my_doctor()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doctor public.doctors%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select *
  into v_doctor
  from public.doctors
  where user_id = auth.uid()
    and active = true
  limit 1;

  if not found then
    raise exception 'Doctor account is not linked to this login';
  end if;

  return jsonb_build_object(
    'doctorId', v_doctor.id,
    'doctorCode', v_doctor.doctor_code,
    'fullName', v_doctor.full_name,
    'qualification', v_doctor.qualification
  );
end;
$$;

revoke all on function public.claim_patient_account() from public;
grant execute on function public.claim_patient_account() to authenticated;

revoke all on function public.claim_doctor_account_by_phone() from public;
grant execute on function public.claim_doctor_account_by_phone() to authenticated;

revoke all on function public.get_my_doctor() from public;
grant execute on function public.get_my_doctor() to authenticated;

revoke all on function public.normalize_phone(text) from public;
grant execute on function public.normalize_phone(text) to anon, authenticated;

-- Public users can see only active doctors' non-sensitive directory fields.
drop policy if exists "doctors public read active" on public.doctors;
drop policy if exists "doctors own select" on public.doctors;

create policy "doctors public read active"
on public.doctors
for select to anon, authenticated
using (active = true);

revoke all on public.doctors from anon, authenticated;

grant select (id, doctor_code, full_name, qualification, active)
on public.doctors
to anon, authenticated;

-- Doctors can see patients who have an appointment with that doctor.
drop policy if exists "patients doctor select" on public.patients;

create policy "patients doctor select"
on public.patients
for select to authenticated
using (
  exists (
    select 1
    from public.appointments a
    where a.patient_id = patients.id
      and a.doctor_id = public.current_doctor_id()
  )
);

-- Doctors can create prescriptions only for their own appointments.
drop policy if exists "prescriptions doctor insert" on public.prescriptions;

create policy "prescriptions doctor insert"
on public.prescriptions
for insert to authenticated
with check (
  doctor_id = public.current_doctor_id()
  and exists (
    select 1
    from public.appointments a
    where a.id = appointment_id
      and a.doctor_id = public.current_doctor_id()
      and a.patient_id = prescriptions.patient_id
  )
);

-- The old demo appointment view is not needed with the RLS-protected tables.
drop view if exists public.public_doctor_schedule;
