# Aaradhya's Homoeopathy — Google Sheets + Drive + Docs backend

## What this adds
- Patients stored in Google Sheets
- Appointments stored in Google Sheets
- Doctor availability stored in Google Sheets
- Payments/status records ready in Google Sheets
- Prescriptions stored as Google Docs + PDF in Google Drive
- Patient folders created automatically
- Doctor appointments can be queried by doctor
- Patient appointments can be queried by mobile number

## Create the Google backend

1. Go to https://script.google.com/
2. Create a new Apps Script project.
3. Copy backend/google-apps-script/Code.gs into the Apps Script editor.
4. Set the Apps Script project time zone to Asia/Kolkata.
5. Run setupClinic() once.
6. Allow the requested Google permissions.

The first run creates:
- A spreadsheet named "Aaradhya's Homoeopathy - Clinic Data"
- Sheets: Patients, Appointments, Availability, Payments, Prescriptions, Orders
- Drive folder: "Aaradhya's Homoeopathy"
- Patients/ and prescription folders

## Prescription letterhead

Create a Google Doc for your letterhead. Put these placeholders where you want patient data:

{{PRESCRIPTION_ID}}
{{PATIENT_ID}}
{{PATIENT_NAME}}
{{AGE}}
{{DATE}}
{{DOCTOR}}
{{COMPLAINTS}}
{{DIAGNOSIS}}
{{MEDICINES}}
{{ADVICE}}

Copy the Google Doc ID into CONFIG.PRESCRIPTION_TEMPLATE_ID in Code.gs, then run setupClinic() again.

When a doctor creates a prescription, the backend copies the template, fills the placeholders, stores the Google Doc in the patient's Drive folder, and creates a PDF.

## Deploy the Apps Script API

Apps Script:
Deploy -> New deployment -> Web app

Choose:
- Execute as: Me
- Who has access: Anyone

Copy the resulting URL ending in /exec.

## Connect Netlify

Open js/config.js in this repository and set:

const API_BASE_URL = "PASTE_YOUR_EXEC_URL_HERE";

Commit that change to GitHub. Netlify will redeploy automatically.

## Test

Patient:
1. Open Patient Login.
2. Use any 10-digit number.
3. Use demo OTP 123456.
4. Book an appointment.
5. Select either doctor.
6. Confirm the appointment.

Backend:
- The booking is written to the Google Sheets Appointments tab.
- A patient record is written to Patients.
- The doctor's dashboard queries appointments for only the selected doctor.

## Production requirements

The current browser demo is not suitable for real medical records until:
- Real SMS OTP provider is added.
- Doctor authentication is moved to a secure backend.
- Payment is verified server-side through a proper payment provider.
- Google Drive permissions are restricted to authorized clinic staff.
- Patient access is authenticated and authorized server-side.
- Audit logs, backups, retention and applicable healthcare/privacy requirements are addressed.
