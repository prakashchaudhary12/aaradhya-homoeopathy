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

### Admin portal data and password management

The Admin Portal reads Auth users through the secure Edge Function:
`supabase/functions/admin-user-management/index.ts`.
Deploy/redeploy this function after every code change. In the Supabase Dashboard, open **Edge Functions → admin-user-management → Edit → Deploy updates**. Supabase also supports CLI deployment with:
```bash
supabase functions deploy admin-user-management
```
The function uses `withSupabase({ auth: 'user' })` and `ctx.supabaseAdmin` so the browser never receives a secret/service-role key.

The Admin Portal's Patients, Appointments, Schedule, Payments and Medicine Orders tabs also load through this same secure admin endpoint, so the portal is not dependent on browser RLS for admin reads.



## Forgot password by mobile

Patient and doctor login pages now include **Forgot Password?**.

Flow:
1. User enters the 10-digit mobile number.
2. The site sends a Supabase SMS OTP only for the selected account type.
3. User enters the OTP.
4. User enters and confirms a new password.
5. The verified Supabase Auth session is used to update the password.

The public function is:
`supabase/functions/request-password-reset/index.ts`

Because this function is called before the user is authenticated, deploy it with JWT verification disabled. The repository includes `supabase/config.toml`:

```toml
[functions.request-password-reset]
verify_jwt = false
```

After deployment, enable the Supabase **Phone** provider and configure an SMS provider (for production, configure Twilio or another supported provider). Phone OTP flows require an SMS provider. Supabase also recommends rate limits/CAPTCHA to control SMS abuse.

The reset endpoint deliberately returns the same message whether the account exists, so the browser does not get a direct account-existence response.

Do not expose a Supabase secret/service-role key in the website. The secret key is used only inside the Edge Function.
