-- Aaradhya's Homoeopathy - Supabase schema
-- Run this entire file once in Supabase SQL Editor.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('patient','doctor','admin')),
  full_name text,
  phone text,
  created_at timestamptz not null default now()
);

create table if not exists public.doctors (
  id uuid primary key,
  doctor_code text not null unique check (doctor_code in ('reshma','op')),
  user_id uuid unique references auth.users(id) on delete set null,
  phone text,
  full_name text not null,
  qualification text not null default 'MD (Hom) Kolkata',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.patients (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references auth.users(id) on delete set null,
  patient_code text unique not null default ('PAT-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8))),
  full_name text not null,
  phone text not null,
  email text,
  date_of_birth date,
  age integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists patients_phone_idx on public.patients(phone);

create table if not exists public.availability (
  id uuid primary key default gen_random_uuid(),
  doctor_id uuid not null references public.doctors(id) on delete cascade,
  availability_date date not null,
  start_time time not null,
  end_time time not null,
  slot_duration integer not null default 15 check (slot_duration between 5 and 60),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  check (end_time > start_time),
  unique (doctor_id, availability_date, start_time, end_time)
);

create index if not exists availability_date_idx on public.availability(availability_date);
create unique index if not exists doctors_phone_idx on public.doctors(phone) where phone is not null;

create table if not exists public.appointments (
  id uuid primary key default gen_random_uuid(),
  appointment_code text unique not null default ('APT-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8))),
  patient_id uuid not null references public.patients(id) on delete restrict,
  doctor_id uuid not null references public.doctors(id) on delete restrict,
  appointment_date date not null,
  appointment_time time not null,
  duration_minutes integer not null default 15 check (duration_minutes between 5 and 60),
  reason text,
  mode text not null check (mode in ('offline','online')),
  payment_preference text,
  payment_status text not null default 'pending' check (payment_status in ('pending','paid','failed','refunded','not_required')),
  status text not null default 'Confirmed' check (status in ('Confirmed','Pending','Completed','Cancelled','No Show')),
  meet_link text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (doctor_id, appointment_date, appointment_time)
);

create index if not exists appointments_patient_idx on public.appointments(patient_id);
create index if not exists appointments_doctor_date_idx on public.appointments(doctor_id, appointment_date);

create table if not exists public.prescriptions (
  id uuid primary key default gen_random_uuid(),
  prescription_code text unique not null default ('RX-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8))),
  appointment_id uuid not null references public.appointments(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  doctor_id uuid not null references public.doctors(id) on delete restrict,
  complaints text,
  diagnosis text,
  advice text,
  document_path text,
  pdf_path text,
  created_at timestamptz not null default now()
);

create index if not exists prescriptions_patient_idx on public.prescriptions(patient_id);
create index if not exists prescriptions_doctor_idx on public.prescriptions(doctor_id);

create table if not exists public.prescription_medicines (
  id uuid primary key default gen_random_uuid(),
  prescription_id uuid not null references public.prescriptions(id) on delete cascade,
  medicine_name text not null,
  dose text,
  frequency text,
  instructions text,
  sort_order integer not null default 0
);

create index if not exists prescription_medicines_rx_idx on public.prescription_medicines(prescription_id, sort_order);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  appointment_id uuid not null references public.appointments(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  amount numeric(12,2),
  currency text not null default 'INR',
  status text not null default 'pending' check (status in ('pending','paid','failed','refunded')),
  provider text,
  provider_reference text,
  created_at timestamptz not null default now()
);

create table if not exists public.medicine_orders (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete restrict,
  prescription_id uuid references public.prescriptions(id) on delete set null,
  items jsonb not null default '[]'::jsonb,
  status text not null default 'requested' check (status in ('requested','confirmed','processing','shipped','completed','cancelled')),
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.patient_documents (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  document_name text not null,
  storage_path text not null,
  content_type text,
  created_at timestamptz not null default now()
);

alter table public.doctors add column if not exists phone text;
-- Seed the two clinic doctors with stable IDs.
insert into public.doctors (id, doctor_code, full_name, qualification)
values
  ('11111111-1111-4111-8111-111111111111','reshma','Dr. Reshma Singh','MD (Hom) Kolkata'),
  ('22222222-2222-4222-8222-222222222222','op','Dr. O.P. Singh','MD (Hom) Kolkata')
on conflict (doctor_code) do update
set full_name = excluded.full_name,
    qualification = excluded.qualification,
    active = true;

-- Helper functions used by RLS policies.
create or replace function public.current_profile_role()
returns text
language sql
security definer
set search_path = public
stable
as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.current_doctor_id()
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select id from public.doctors where user_id = auth.uid() and active = true;
$$;

create or replace function public.current_patient_id()
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select id from public.patients where user_id = auth.uid();
$$;

-- RLS
alter table public.profiles enable row level security;
alter table public.doctors enable row level security;
alter table public.patients enable row level security;
alter table public.availability enable row level security;
alter table public.appointments enable row level security;
alter table public.prescriptions enable row level security;
alter table public.prescription_medicines enable row level security;
alter table public.payments enable row level security;
alter table public.medicine_orders enable row level security;
alter table public.patient_documents enable row level security;

-- Remove policies so the script is safe to re-run.
drop policy if exists "profiles own select" on public.profiles;
drop policy if exists "profiles own update" on public.profiles;
drop policy if exists "doctors public read active" on public.doctors;
drop policy if exists "patients own select" on public.patients;
drop policy if exists "patients own update" on public.patients;
drop policy if exists "patients admin select" on public.patients;
drop policy if exists "patients doctor select" on public.patients;
drop policy if exists "availability doctor own" on public.availability;
drop policy if exists "availability public read" on public.availability;
drop policy if exists "appointments patient read" on public.appointments;
drop policy if exists "appointments doctor read" on public.appointments;
drop policy if exists "appointments patient update" on public.appointments;
drop policy if exists "appointments admin all" on public.appointments;
drop policy if exists "prescriptions patient read" on public.prescriptions;
drop policy if exists "prescriptions doctor read" on public.prescriptions;
drop policy if exists "prescriptions doctor insert" on public.prescriptions;
drop policy if exists "prescription meds patient read" on public.prescription_medicines;
drop policy if exists "prescription meds doctor all" on public.prescription_medicines;
drop policy if exists "payments patient read" on public.payments;
drop policy if exists "payments admin all" on public.payments;
drop policy if exists "orders patient all" on public.medicine_orders;
drop policy if exists "orders admin all" on public.medicine_orders;
drop policy if exists "documents patient read" on public.patient_documents;
drop policy if exists "documents doctor read" on public.patient_documents;
drop policy if exists "documents admin all" on public.patient_documents;

create policy "profiles own select" on public.profiles
for select to authenticated
using (id = auth.uid() or public.current_profile_role() = 'admin');

create policy "profiles own update" on public.profiles
for update to authenticated
using (id = auth.uid())
with check (id = auth.uid());

create policy "doctors public read active" on public.doctors
for select to anon, authenticated
using (active = true);

create policy "patients own select" on public.patients
for select to authenticated
using (user_id = auth.uid());

create policy "patients own update" on public.patients
for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "patients admin select" on public.patients
for select to authenticated
using (public.current_profile_role() = 'admin');

create policy "patients doctor select" on public.patients
for select to authenticated
using (exists (
  select 1 from public.appointments a
  where a.patient_id = patients.id
    and a.doctor_id = public.current_doctor_id()
));

create policy "availability public read" on public.availability
for select to anon, authenticated
using (active = true);

create policy "availability doctor own" on public.availability
for all to authenticated
using (doctor_id = public.current_doctor_id())
with check (doctor_id = public.current_doctor_id());

create policy "appointments patient read" on public.appointments
for select to authenticated
using (patient_id = public.current_patient_id());

create policy "appointments doctor read" on public.appointments
for select to authenticated
using (doctor_id = public.current_doctor_id());

create policy "appointments patient update" on public.appointments
for update to authenticated
using (patient_id = public.current_patient_id())
with check (patient_id = public.current_patient_id());

create policy "appointments admin all" on public.appointments
for all to authenticated
using (public.current_profile_role() = 'admin')
with check (public.current_profile_role() = 'admin');

create policy "prescriptions patient read" on public.prescriptions
for select to authenticated
using (patient_id = public.current_patient_id());

create policy "prescriptions doctor read" on public.prescriptions
for select to authenticated
using (doctor_id = public.current_doctor_id());

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

create policy "prescription meds patient read" on public.prescription_medicines
for select to authenticated
using (exists (
  select 1 from public.prescriptions p
  where p.id = prescription_id
    and p.patient_id = public.current_patient_id()
));

create policy "prescription meds doctor all" on public.prescription_medicines
for all to authenticated
using (exists (
  select 1 from public.prescriptions p
  where p.id = prescription_id
    and p.doctor_id = public.current_doctor_id()
))
with check (exists (
  select 1 from public.prescriptions p
  where p.id = prescription_id
    and p.doctor_id = public.current_doctor_id()
));

create policy "payments patient read" on public.payments
for select to authenticated
using (patient_id = public.current_patient_id());

create policy "payments admin all" on public.payments
for all to authenticated
using (public.current_profile_role() = 'admin')
with check (public.current_profile_role() = 'admin');

create policy "orders patient all" on public.medicine_orders
for all to authenticated
using (patient_id = public.current_patient_id())
with check (patient_id = public.current_patient_id());

create policy "orders admin all" on public.medicine_orders
for all to authenticated
using (public.current_profile_role() = 'admin')
with check (public.current_profile_role() = 'admin');

create policy "documents patient read" on public.patient_documents
for select to authenticated
using (patient_id = public.current_patient_id());

create policy "documents doctor read" on public.patient_documents
for select to authenticated
using (exists (
  select 1 from public.appointments a
  where a.patient_id = patient_documents.patient_id
    and a.doctor_id = public.current_doctor_id()
));

create policy "documents admin all" on public.patient_documents
for all to authenticated
using (public.current_profile_role() = 'admin')
with check (public.current_profile_role() = 'admin');

-- Secure public booking RPC.
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
begin
  if p_appointment_date < (v_now_ist::date)
     or (p_appointment_date = v_now_ist::date and v_time < v_now_ist::time) then
    raise exception 'Please choose a future appointment slot';
  end if;

  if nullif(trim(p_full_name),'') is null then
    raise exception 'Patient name is required';
  end if;
  if nullif(regexp_replace(p_phone,'\D','','g'),'') is null or length(regexp_replace(p_phone,'\D','','g')) < 10 then
    raise exception 'Valid mobile number is required';
  end if;

  select * into v_doctor from public.doctors
  where doctor_code = lower(trim(p_doctor_code)) and active = true;

  if not found then
    raise exception 'Doctor not found';
  end if;

  -- Clinic schedule: Sunday online 09:00-18:45 start times; Mon-Sat 17:00-20:45 start times.
  if v_dow = 0 then
    v_mode := 'online';
    if v_time < time '09:00' or v_time > time '18:45' then
      raise exception 'Sunday slots are available from 9:00 AM to 6:45 PM';
    end if;
  else
    if v_time < time '17:00' or v_time > time '20:45' then
      raise exception 'Monday-Saturday slots are available from 5:00 PM to 8:45 PM';
    end if;
    if v_mode not in ('offline','online') then
      v_mode := 'offline';
    end if;
  end if;

  insert into public.patients(full_name, phone)
  values (trim(p_full_name), p_phone)
  on conflict do nothing;

  select * into v_patient
  from public.patients
  where regexp_replace(phone,'\D','','g') = regexp_replace(p_phone,'\D','','g')
  order by created_at desc
  limit 1;

  if not found then
    raise exception 'Unable to create patient record';
  end if;

  insert into public.appointments(
    patient_id, doctor_id, appointment_date, appointment_time,
    duration_minutes, reason, mode, payment_preference, payment_status, status
  )
  values (
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
grant execute on function public.book_appointment_public(text,text,text,date,text,text,text,text) to anon, authenticated;

-- Helpful views for the frontend. These are security-barrier views over RLS-protected base tables.
create or replace view public.public_doctor_schedule as
select
  a.id,
  d.doctor_code,
  a.appointment_date,
  a.appointment_time,
  a.duration_minutes,
  a.status,
  a.mode
from public.appointments a
join public.doctors d on d.id = a.doctor_id;

grant select on public.doctors to anon, authenticated;
grant select on public.availability to anon, authenticated;


-- Authentication helpers.
-- Patient/doctor accounts are linked after successful Supabase Phone OTP login.
create or replace function public.normalize_phone(p_phone text)
returns text
language sql
immutable
as $$
  select regexp_replace(coalesce(p_phone,''), '\\D', '', 'g');
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

-- Extra policy so doctors can maintain only their own profile/doctor linkage.
drop policy if exists "doctors own select" on public.doctors;
create policy "doctors own select" on public.doctors
for select to authenticated
using (active = true and (user_id = auth.uid() or public.current_profile_role() in ('admin','doctor')));

-- Existing public read policy remains useful for anonymous booking pages.
