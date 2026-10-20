-- Aaradhya's Homoeopathy
-- Admin access migration.
-- Run once in Supabase SQL Editor after the existing schema/auth migrations.
-- Admin authentication itself is enforced by the Edge Function and
-- public.profiles.role = 'admin'.

-- Admin can manage clinic tables. RLS still applies to every other role.
drop policy if exists "doctors admin all" on public.doctors;
create policy "doctors admin all"
on public.doctors
for all
to authenticated
using (public.current_profile_role() = 'admin')
with check (public.current_profile_role() = 'admin');

drop policy if exists "availability admin all" on public.availability;
create policy "availability admin all"
on public.availability
for all
to authenticated
using (public.current_profile_role() = 'admin')
with check (public.current_profile_role() = 'admin');

drop policy if exists "patients admin all" on public.patients;
create policy "patients admin all"
on public.patients
for all
to authenticated
using (public.current_profile_role() = 'admin')
with check (public.current_profile_role() = 'admin');

drop policy if exists "prescription meds admin all" on public.prescription_medicines;
create policy "prescription meds admin all"
on public.prescription_medicines
for all
to authenticated
using (public.current_profile_role() = 'admin')
with check (public.current_profile_role() = 'admin');

drop policy if exists "payments admin all" on public.payments;
create policy "payments admin all"
on public.payments
for all
to authenticated
using (public.current_profile_role() = 'admin')
with check (public.current_profile_role() = 'admin');

drop policy if exists "orders admin all" on public.medicine_orders;
create policy "orders admin all"
on public.medicine_orders
for all
to authenticated
using (public.current_profile_role() = 'admin')
with check (public.current_profile_role() = 'admin');

drop policy if exists "documents admin all" on public.patient_documents;
create policy "documents admin all"
on public.patient_documents
for all
to authenticated
using (public.current_profile_role() = 'admin')
with check (public.current_profile_role() = 'admin');

drop policy if exists "prescriptions admin all" on public.prescriptions;
create policy "prescriptions admin all"
on public.prescriptions
for all
to authenticated
using (public.current_profile_role() = 'admin')
with check (public.current_profile_role() = 'admin');

-- Data API privileges for the admin browser UI. RLS controls which rows
-- an authenticated admin may access.
grant select (id, doctor_code, full_name, qualification, active) on public.doctors to authenticated;
grant select, insert, update, delete on public.availability to authenticated;
grant select, insert, update, delete on public.patients to authenticated;
grant select, insert, update, delete on public.prescriptions to authenticated;
grant select, insert, update, delete on public.prescription_medicines to authenticated;
grant select, insert, update, delete on public.payments to authenticated;
grant select, insert, update, delete on public.medicine_orders to authenticated;
grant select, insert, update, delete on public.patient_documents to authenticated;
grant select, update on public.appointments to authenticated;
grant select, update on public.profiles to authenticated;
