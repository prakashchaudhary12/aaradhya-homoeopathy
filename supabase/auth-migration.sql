-- Run once after the original Database Setup query.
-- Supabase Auth migration for Aaradhya's Homoeopathy.

alter table public.doctors add column if not exists phone text;
create unique index if not exists doctors_phone_idx on public.doctors(phone) where phone is not null;

create or replace function public.normalize_phone(p_phone text)
returns text
language sql
immutable
as $$
  select regexp_replace(coalesce(p_phone,''), '\D', '', 'g');
$$;

create or replace function public.claim_patient_account()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.normalize_phone(coalesce((select phone from auth.users where id = auth.uid()), ''));
  v_patient public.patients%rowtype;
begin
  if auth.uid() is null or v_phone = '' then
    raise exception 'Authenticated phone number is required';
  end if;

  select * into v_patient
  from public.patients
  where public.normalize_phone(phone) = v_phone
  order by (user_id = auth.uid()) desc, created_at desc
  limit 1;

  if not found then
    insert into public.patients(user_id, full_name, phone)
    values(auth.uid(), coalesce((select raw_user_meta_data->>'full_name' from auth.users where id=auth.uid()), 'Patient'), v_phone)
    returning * into v_patient;
  elsif v_patient.user_id is null or v_patient.user_id = auth.uid() then
    update public.patients
    set user_id = auth.uid(), phone = v_phone, updated_at = now()
    where id = v_patient.id
    returning * into v_patient;
  else
    raise exception 'This phone number is already linked to another patient account';
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

create or replace function public.claim_doctor_account(p_doctor_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.normalize_phone(coalesce((select phone from auth.users where id = auth.uid()), ''));
  v_doctor public.doctors%rowtype;
begin
  if auth.uid() is null or v_phone = '' then
    raise exception 'Authenticated phone number is required';
  end if;

  select * into v_doctor
  from public.doctors
  where doctor_code = lower(trim(p_doctor_code)) and active = true;

  if not found then
    raise exception 'Doctor account not found';
  end if;

  if v_doctor.phone is null or public.normalize_phone(v_doctor.phone) <> v_phone then
    raise exception 'This phone number is not registered for the selected doctor';
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

revoke all on function public.claim_doctor_account(text) from public;
grant execute on function public.claim_doctor_account(text) to authenticated;

revoke all on function public.normalize_phone(text) from public;
grant execute on function public.normalize_phone(text) to anon, authenticated;

-- Do not expose doctor phone numbers or user IDs to anonymous visitors.
drop policy if exists "doctors public read active" on public.doctors;
revoke select on public.doctors from anon;

drop policy if exists "patients doctor select" on public.patients;
create policy "patients doctor select" on public.patients
for select to authenticated
using (exists (
  select 1 from public.appointments a
  where a.patient_id = patients.id
    and a.doctor_id = public.current_doctor_id()
));

drop policy if exists "doctors own select" on public.doctors;
create policy "doctors own select" on public.doctors
for select to authenticated
using (active = true and (user_id = auth.uid() or public.current_profile_role() in ('admin','doctor')));

-- The prescription insert policy is tightened so a doctor can only prescribe
-- for one of their own appointments.
drop policy if exists "prescriptions doctor insert" on public.prescriptions;
create policy "prescriptions doctor insert" on public.prescriptions
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
