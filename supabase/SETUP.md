# Supabase setup — Aaradhya's Homoeopathy

1. Open Supabase → SQL Editor.
2. Open/copy `supabase/schema.sql` from this repository.
3. Run the complete SQL script.
4. Confirm these tables appear under Table Editor:
   `profiles`, `doctors`, `patients`, `availability`, `appointments`, `prescriptions`, `prescription_medicines`, `payments`, `medicine_orders`, `patient_documents`.
5. The script seeds Dr. Reshma Singh and Dr. O.P. Singh.

The website uses the Supabase browser publishable key. Never put the database password or Supabase secret/service-role key in GitHub or frontend JavaScript.

Next phase after the schema is running: connect Supabase Auth for patients/doctors and then connect Storage for prescription/report files.
