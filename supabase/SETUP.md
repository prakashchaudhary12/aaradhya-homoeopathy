# Supabase setup — Aaradhya's Homoeopathy

1. Open Supabase → SQL Editor.
2. Open/copy `supabase/schema.sql` from this repository.
3. Run the complete SQL script.
4. Confirm these tables appear under Table Editor:
   `profiles`, `doctors`, `patients`, `availability`, `appointments`, `prescriptions`, `prescription_medicines`, `payments`, `medicine_orders`, `patient_documents`.
5. The script seeds Dr. Reshma Singh and Dr. O.P. Singh.

The website uses the Supabase browser publishable key. Never put the database password or Supabase secret/service-role key in GitHub or frontend JavaScript.

Next phase after the schema is running: connect Supabase Auth for patients/doctors and then connect Storage for prescription/report files.


## Authentication setup

The website now uses three roles:

- **Patient:** mobile number + password
- **Doctor:** mobile number + password
- **Admin:** email + password

### Patient and doctor mobile/password auth

Supabase → Authentication → Providers → **Phone**:
1. Enable Phone authentication.
2. Keep phone sign-up enabled.
3. To avoid OTP/SMS for password login, keep **phone confirmation disabled**.
4. No SMS provider is required for the normal mobile + password login path when phone confirmation is disabled.

Run `supabase/auth-migration.sql` once after the original database setup. It adds the doctor phone field, safe phone matching, auth-linking RPCs and the final RLS changes.

### Doctor accounts

Doctor accounts are not created from the public website.

In Supabase → Authentication → Users, create one user for each doctor with:
- Phone number
- Strong password
- Phone marked confirmed/verified when the dashboard asks

Then in Table Editor → `doctors`, store the same phone number in the `phone` column:

```sql
update public.doctors set phone = '+91XXXXXXXXXX' where doctor_code = 'reshma';
update public.doctors set phone = '+91XXXXXXXXXX' where doctor_code = 'op';
```

A doctor can log in only when the authenticated phone matches the registered doctor phone. The database links the Auth user to that doctor.

### Admin account

Create the administrator in Supabase → Authentication → Users with an email and password.

Then copy that Auth user's UUID and run:

```sql
insert into public.profiles(id, role, full_name)
values ('AUTH-USER-UUID-HERE', 'admin', 'Clinic Admin')
on conflict (id) do update
set role='admin', full_name=excluded.full_name;
```

The admin login page checks this `profiles.role = 'admin'` value before opening the admin dashboard.

Never put the database password or Supabase secret/service-role key in GitHub or browser JavaScript.
