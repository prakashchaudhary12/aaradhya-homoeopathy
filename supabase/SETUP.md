# Supabase setup — Aaradhya's Homoeopathy

1. Open Supabase → SQL Editor.
2. Open/copy `supabase/schema.sql` from this repository.
3. Run the complete SQL script.
4. Confirm these tables appear under Table Editor:
   `profiles`, `doctors`, `patients`, `availability`, `appointments`, `prescriptions`, `prescription_medicines`, `payments`, `medicine_orders`, `patient_documents`.
5. The script seeds Dr. Reshma Singh and Dr. O.P. Singh.

The website uses the Supabase browser publishable key. Never put the database password or Supabase secret/service-role key in GitHub or frontend JavaScript.

Next phase after the schema is running: connect Supabase Auth for patients/doctors and then connect Storage for prescription/report files.


## Authentication migration

Because the original database setup has already been run, run `supabase/auth-migration.sql` once in Supabase SQL Editor.

Then configure Supabase Auth:
- Authentication → Providers → Phone: enable it.
- Configure an SMS provider supported by Supabase.
- Keep Site URL/redirect settings pointed to your deployed Netlify site.

Before doctor login can work, store the two doctors' registered phone numbers in the `doctors.phone` column. Example:

```sql
update public.doctors set phone = '+91XXXXXXXXXX' where doctor_code = 'reshma';
update public.doctors set phone = '+91XXXXXXXXXX' where doctor_code = 'op';
```

Do not commit real patient/doctor secrets to GitHub.

The website no longer trusts the old demo OTP/PIN. Patient and doctor login use Supabase Auth, and dashboards rely on database RLS rather than a doctor value passed in the URL.
