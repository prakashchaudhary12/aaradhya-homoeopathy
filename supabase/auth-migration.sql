-- Run once after the original Aaradhya's Homoeopathy database setup.
-- This migration changes Patient/Doctor auth to mobile + password.
-- It intentionally does not create a public Doctor signup.

alter table public.doctors add column if not exists phone text;

create or replace function public.normalize_phone(p_phone text)
returns text
language sql
immutable
as $$
  select regexp_replace(coalesce(p_phone,''), '\D', '', 'g');
$$;

-- Recreate the index after normalize_phone exists.
drop index if exists doctors_phone_idx;
create unique index doctors_phone_idx
  on public.doctors(public.normalize_phone(phone)) where phone is not null;

create unique index if not exists patients_phone_normalized_idx
  on public.patients(public.normalize_phone(phone));

create or replace function public.claim_patient_account()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.normalize_phone(coalesce((select phone from auth.users where id = auth.uid()), ''));
  v_patient public.patients%rowtype;
  v_role text := (select role from public.profiles where id = auth.uid());
  v_name text := coalesce(
    (select raw_user_meta_data->>'full_name' from auth.users where id=auth.uid()),
    'Patient'
  );
begin
  if auth.uid() is null or v_phone = '' then
    raise exception 'Authenticated mobile number is required';
  end if;

  if v_role in ('doctor','admin') then
    raise exception 'This login is not a patient account';
  end if;

  select * into v_patient
  from public.patients
  where public.normalize_phone(phone) = v_phone
  order by (user_id = auth.uid()) desc, created_at desc
  limit 1;

  if not found then
    insert into public.patients(user_id, full_name, phone)
    values(auth.uid(), v_name, v_phone)
    returning * into v_patient;
  elsif v_patient.user_id is null or v_patient.user_id = auth.uid() then
    update public.patients
    set user_id = auth.uid(),
        full_name = coalesce(nullif(v_name,''), full_name),
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

create or replace function public.claim_doctor_account_by_phone()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.normalize_phone(coalesce((select phone from auth.users where id = auth.uid()), ''));
  v_doctor public.doctors%rowtype;
  v_role text := (select role from public.profiles where id = auth.uid());
begin
  if auth.uid() is null or v_phone = '' then
    raise exception 'Authenticated mobile number is required';
  end if;

  if v_role in ('patient','admin') then
    raise exception 'This login is not a doctor account';
  end if;

  select * into v_doctor
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

  insert into public.profiles(id, role, full_name, phone)
  values(auth.uid(), 'doctor', v_doctor.full_name, v_phone)
  on conflict (id) do update
  set role='doctor', full_name=excluded.full_name, phone=excluded.phone;

  return jsonb_build_object(
    'doctorId', v_doctor.id,
    'doctorCode', v_doctor.doctor_code,
    'fullName', v_doctor.full_name,
    'phone', v_phone
  );
end;
$$;

revoke all on function public.claim_patient_account() from public;
grant execute on function public.claim_patient_account() to authenticated;

revoke all on function public.claim_doctor_account_by_phone() from public;
grant execute on function public.claim_doctor_account_by_phone() to authenticated;

revoke all on function public.normalize_phone(text) from public;
grant execute on function public.normalize_phone(text) to anon, authenticated;

-- Safe doctor directory: anonymous/authenticated visitors can read names/qualifications,
-- but never doctor phone numbers or Auth user IDs.
drop policy if exists "doctors public read active" on public.doctors;
drop policy if exists "doctors own select" on public.doctors;
create policy "doctors public read active"
on public.doctors
for select to anon, authenticated
using (active = true);

revoke select on public.doctors from anon, authenticated;
grant select (id, doctor_code, full_name, qualification, active)
  on public.doctors to anon, authenticated;

-- Patient access for doctors.
drop policy if exists "patients doctor select" on public.patients;
create policy "patients doctor select"
on public.patients
for select to authenticated
using (
  exists (
    select 1 from public.appointments a
    where a.patient_id = patients.id
      and a.doctor_id = public.current_doctor_id()
  )
);

-- Doctors can prescribe only for their own appointment/patient pair.
drop policy if exists "prescriptions doctor insert" on public.prescriptions;
create policy "prescriptions doctor insert"
on public.prescriptions
for insert to authenticated
with check (
  doctor_id = public.current_doctor_id()
  and exists (
    select 1 from public.appointments a
    where a.id = appointment_id
      and a.doctor_id = public.current_doctor_id()
      and a.patient_id = prescriptions.patient_id
  )
);

-- Remove the unused appointment view because it could bypass the intended
-- table-level access model depending on PostgreSQL view security configuration.
drop view if exists public.public_doctor_schedule;

