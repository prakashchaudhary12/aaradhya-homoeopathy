/*******************************************************
 * AARADHYA'S HOMOEOPATHY - GOOGLE APPS SCRIPT BACKEND
 *
 * Creates/manages:
 * - Google Sheets: patients, appointments, availability, payments, prescriptions, orders
 * - Google Drive: patient folders + prescription PDFs
 * - Google Docs: prescription letter-pad copies
 *******************************************************/

const CONFIG = {
  CLINIC_NAME: "Aaradhya's Homoeopathy",
  SPREADSHEET_NAME: "Aaradhya's Homoeopathy - Clinic Data",
  ROOT_FOLDER_NAME: "Aaradhya's Homoeopathy",
  PRESCRIPTION_TEMPLATE_ID: "",
  TIMEZONE: Session.getScriptTimeZone() || "Asia/Kolkata"
};

const SHEETS = {
  PATIENTS: "Patients",
  APPOINTMENTS: "Appointments",
  AVAILABILITY: "Availability",
  PAYMENTS: "Payments",
  PRESCRIPTIONS: "Prescriptions",
  ORDERS: "Orders"
};

function setupClinic() {
  const ss = getOrCreateSpreadsheet_();
  Object.values(SHEETS).forEach(name => {
    let sh = ss.getSheetByName(name);
    if (!sh) sh = ss.insertSheet(name);
    setupSheet_(sh, headersFor_(name));
  });
  const root = getOrCreateFolder_(CONFIG.ROOT_FOLDER_NAME);
  const templateFolder = getOrCreateChildFolder_(root, "Prescription Templates");
  const patientsFolder = getOrCreateChildFolder_(root, "Patients");
  const clinicFolder = getOrCreateChildFolder_(root, "Clinic Documents");
  return {ok:true, spreadsheetId:ss.getId(), spreadsheetUrl:ss.getUrl(), rootFolderId:root.getId(), rootFolderUrl:root.getUrl(), templateFolderId:templateFolder.getId(), patientsFolderId:patientsFolder.getId(), clinicFolderId:clinicFolder.getId(), timezone:CONFIG.TIMEZONE};
}

function doGet(e) {
  try {
    const action=(e&&e.parameter&&e.parameter.action)||"health";
    if(action==="health") return json_({ok:true,clinic:CONFIG.CLINIC_NAME});
    if(action==="availability") return json_({ok:true,data:getAvailability_(e.parameter.doctor,e.parameter.date)});
    if(action==="appointments") return json_({ok:true,data:getAppointments_(e.parameter.doctor,e.parameter.patientMobile,e.parameter.status)});
    if(action==="patient") return json_({ok:true,data:getPatientByMobile_(e.parameter.mobile)});
    if(action==="prescriptions") return json_({ok:true,data:getPrescriptions_(e.parameter.patientId,e.parameter.doctor)});
    return json_({ok:false,error:"Unknown GET action"});
  } catch(err) { return json_({ok:false,error:String(err)}); }
}

function doPost(e) {
  try {
    const body=parseBody_(e);
    switch(body.action){
      case "registerPatient": return json_(registerPatient_(body));
      case "bookAppointment": return json_(bookAppointment_(body));
      case "setAvailability": return json_(setAvailability_(body));
      case "createPrescription": return json_(createPrescription_(body));
      case "createOrder": return json_(createOrder_(body));
      case "updateAppointmentStatus": return json_(updateAppointmentStatus_(body));
      default: return json_({ok:false,error:"Unknown POST action"});
    }
  } catch(err) { return json_({ok:false,error:String(err)}); }
}

function registerPatient_(data) {
  require_(data.mobile,"Mobile is required");
  const sh=getOrCreateSpreadsheet_().getSheetByName(SHEETS.PATIENTS);
  const found=findRowBy_(sh,3,String(data.mobile).trim());
  if(found) return {ok:true,patient:rowToObject_(sh,found.row)};
  const id=nextId_("PAT",sh);
  sh.appendRow([id,data.name||"",String(data.mobile).trim(),data.email||"",data.city||"",data.age||"",data.gender||"",new Date(),"Active"]);
  return {ok:true,patient:rowToObject_(sh,sh.getLastRow())};
}

function getPatientByMobile_(mobile) {
  if(!mobile) return null;
  const sh=getOrCreateSpreadsheet_().getSheetByName(SHEETS.PATIENTS);
  const found=findRowBy_(sh,3,String(mobile).trim());
  return found?rowToObject_(sh,found.row):null;
}

function bookAppointment_(data) {
  require_(data.mobile,"Mobile is required"); require_(data.doctor,"Doctor is required"); require_(data.date,"Date is required"); require_(data.time,"Time is required");
  const patient=registerPatient_(data).patient;
  const sh=getOrCreateSpreadsheet_().getSheetByName(SHEETS.APPOINTMENTS);
  if(findAppointmentConflict_(sh,data.doctor,data.date,data.time)) throw new Error("This appointment slot is already booked.");
  const id=nextId_("APT",sh);
  const sunday=isSunday_(data.date);
  sh.appendRow([id,data.doctor,patient["Patient ID"],data.name||"",String(data.mobile).trim(),data.date,data.time,Number(data.duration||15),data.mode||(sunday?"online":"offline"),data.reason||"",data.payment||"Pay after consultation",data.paymentStatus||"Pending","Confirmed",data.meetLink||"",data.notes||"",new Date(),""]);
  return {ok:true,appointment:rowToObject_(sh,sh.getLastRow())};
}

function updateAppointmentStatus_(data){
  require_(data.appointmentId,"Appointment ID is required");
  const sh=getOrCreateSpreadsheet_().getSheetByName(SHEETS.APPOINTMENTS);
  const f=findRowBy_(sh,1,data.appointmentId); if(!f) throw new Error("Appointment not found");
  sh.getRange(f.row,13).setValue(data.status||"Completed");
  if(data.status==="Completed") sh.getRange(f.row,17).setValue(new Date());
  return {ok:true,appointment:rowToObject_(sh,f.row)};
}

function getAppointments_(doctor,patientMobile,status){
  const sh=getOrCreateSpreadsheet_().getSheetByName(SHEETS.APPOINTMENTS);
  const vals=sh.getDataRange().getValues(); const headers=vals.shift();
  return vals.filter(r=>r[0]&&(!doctor||String(r[1])===String(doctor))&&(!patientMobile||String(r[4])===String(patientMobile))&&(!status||String(r[12])===String(status))).map(r=>objectFromRow_(headers,r));
}

function getPrescriptions_(patientId,doctor){
  const sh=getOrCreateSpreadsheet_().getSheetByName(SHEETS.PRESCRIPTIONS);
  const vals=sh.getDataRange().getValues(); const headers=vals.shift();
  return vals.filter(r=>r[0]&&(!patientId||String(r[2])===String(patientId))&&(!doctor||String(r[4])===String(doctor))).map(r=>objectFromRow_(headers,r));
}

function findAppointmentConflict_(sh,doctor,date,time){
  const vals=sh.getDataRange().getValues();
  for(let i=1;i<vals.length;i++){const r=vals[i]; if(String(r[1])===String(doctor)&&String(r[5])===String(date)&&String(r[6])===String(time)&&String(r[12])!=="Cancelled") return true;}
  return false;
}

function setAvailability_(data){
  require_(data.doctor,"Doctor is required"); require_(data.date,"Date is required"); require_(data.startTime,"Start time is required"); require_(data.endTime,"End time is required");
  const sh=getOrCreateSpreadsheet_().getSheetByName(SHEETS.AVAILABILITY); const id=nextId_("AVL",sh);
  sh.appendRow([id,data.doctor,data.date,data.startTime,data.endTime,Number(data.slotDuration||15),isSunday_(data.date)?"online":"offline","Open",new Date()]);
  return {ok:true,availability:rowToObject_(sh,sh.getLastRow())};
}

function getAvailability_(doctor,date){
  const sh=getOrCreateSpreadsheet_().getSheetByName(SHEETS.AVAILABILITY); const vals=sh.getDataRange().getValues(); const headers=vals.shift();
  return vals.filter(r=>r[0]&&(!doctor||String(r[1])===String(doctor))&&(!date||String(r[2])===String(date))).map(r=>objectFromRow_(headers,r));
}

function createPrescription_(data){
  require_(data.patientId,"Patient ID is required"); require_(data.doctor,"Doctor is required"); require_(data.appointmentId,"Appointment ID is required");
  const sh=getOrCreateSpreadsheet_().getSheetByName(SHEETS.PRESCRIPTIONS);
  const root=getOrCreateFolder_(CONFIG.ROOT_FOLDER_NAME);
  const patientsRoot=getOrCreateChildFolder_(root,"Patients");
  const patientFolder=getOrCreateChildFolder_(patientsRoot,data.patientId);
  const rxFolder=getOrCreateChildFolder_(patientFolder,"Prescriptions");
  const id=nextId_("RX",sh); let docFile;
  if(CONFIG.PRESCRIPTION_TEMPLATE_ID){
    const template=DriveApp.getFileById(CONFIG.PRESCRIPTION_TEMPLATE_ID);
    docFile=template.makeCopy(id+" - Prescription",rxFolder);
    const doc=DocumentApp.openById(docFile.getId()), body=doc.getBody();
    const map={"{{PRESCRIPTION_ID}}":id,"{{PATIENT_ID}}":data.patientId||"","{{PATIENT_NAME}}":data.patientName||"","{{AGE}}":data.age||"","{{DATE}}":data.date||formatDate_(new Date()),"{{DOCTOR}}":data.doctor||"","{{COMPLAINTS}}":data.complaints||"","{{DIAGNOSIS}}":data.diagnosis||"","{{MEDICINES}}":formatMedicines_(data.medicines||[]),"{{ADVICE}}":data.advice||""};
    Object.keys(map).forEach(k=>body.replaceText(k,escapeReplacement_(map[k]))); doc.saveAndClose();
  } else { docFile=createPrescriptionDocument_(rxFolder,id,data); }
  const pdfFile=rxFolder.createFile(docFile.getAs(MimeType.PDF)).setName(id+" - Prescription.pdf");
  sh.appendRow([id,data.appointmentId,data.patientId,data.patientName||"",data.doctor,data.date||formatDate_(new Date()),data.complaints||"",data.diagnosis||"",JSON.stringify(data.medicines||[]),data.advice||"",docFile.getId(),pdfFile.getId(),new Date()]);
  return {ok:true,prescriptionId:id,documentUrl:docFile.getUrl(),pdfUrl:pdfFile.getUrl()};
}

function createPrescriptionDocument_(folder,id,data){
  const doc=DocumentApp.create(id+" - Prescription"); const file=DriveApp.getFileById(doc.getId()); folder.addFile(file); try{DriveApp.getRootFolder().removeFile(file);}catch(e){}
  const body=doc.getBody(); body.appendParagraph(CONFIG.CLINIC_NAME).setHeading(DocumentApp.ParagraphHeading.TITLE); body.appendParagraph("HOMEOPATHIC CONSULTATION"); body.appendParagraph("Dr. Reshma Singh — MD (Hom) Kolkata"); body.appendParagraph("Dr. O.P. Singh — MD (Hom) Kolkata"); body.appendHorizontalRule(); body.appendParagraph("Patient: "+(data.patientName||"")); body.appendParagraph("Patient ID: "+(data.patientId||"")); body.appendParagraph("Date: "+(data.date||formatDate_(new Date()))); body.appendParagraph("Doctor: "+(data.doctor||"")); body.appendParagraph("Complaints: "+(data.complaints||"")); body.appendParagraph("Diagnosis: "+(data.diagnosis||"")); body.appendParagraph("Prescription");
  (data.medicines||[]).forEach((m,i)=>body.appendParagraph((i+1)+". "+(m.name||"")+" — "+(m.dose||"")+" — "+(m.frequency||""))); body.appendParagraph("Advice: "+(data.advice||"")); body.appendHorizontalRule(); body.appendParagraph("Doctor Signature"); doc.saveAndClose(); return file;
}

function createOrder_(data){
  require_(data.patientId,"Patient ID is required"); const sh=getOrCreateSpreadsheet_().getSheetByName(SHEETS.ORDERS); const id=nextId_("ORD",sh);
  sh.appendRow([id,data.patientId,data.patientName||"",data.mobile||"",JSON.stringify(data.items||[]),Number(data.amount||0),data.address||"",data.paymentStatus||"Pending","New",new Date()]);
  return {ok:true,order:rowToObject_(sh,sh.getLastRow())};
}

function headersFor_(name){
  const H={};
  H[SHEETS.PATIENTS]=["Patient ID","Name","Mobile","Email","City","Age","Gender","Created At","Status"];
  H[SHEETS.APPOINTMENTS]=["Appointment ID","Doctor","Patient ID","Patient Name","Mobile","Date","Time","Duration","Mode","Reason","Payment Preference","Payment Status","Status","Meet Link","Notes","Created At","Completed At"];
  H[SHEETS.AVAILABILITY]=["Availability ID","Doctor","Date","Start Time","End Time","Slot Duration","Mode","Status","Created At"];
  H[SHEETS.PAYMENTS]=["Payment ID","Appointment ID","Patient ID","Amount","Method","Status","Transaction ID","Created At"];
  H[SHEETS.PRESCRIPTIONS]=["Prescription ID","Appointment ID","Patient ID","Patient Name","Doctor","Date","Complaints","Diagnosis","Medicines JSON","Advice","Google Doc ID","PDF File ID","Created At"];
  H[SHEETS.ORDERS]=["Order ID","Patient ID","Patient Name","Mobile","Items JSON","Amount","Address","Payment Status","Order Status","Created At"];
  return H[name];
}
function getOrCreateSpreadsheet_(){const p=PropertiesService.getScriptProperties(),id=p.getProperty("SPREADSHEET_ID");if(id)try{return SpreadsheetApp.openById(id)}catch(e){}const ss=SpreadsheetApp.create(CONFIG.SPREADSHEET_NAME);p.setProperty("SPREADSHEET_ID",ss.getId());return ss;}
function setupSheet_(sh,h){if(sh.getLastRow()===0){sh.getRange(1,1,1,h.length).setValues([h]);sh.setFrozenRows(1);}}
function getOrCreateFolder_(name){const it=DriveApp.getFoldersByName(name);return it.hasNext()?it.next():DriveApp.createFolder(name);}
function getOrCreateChildFolder_(parent,name){const it=parent.getFoldersByName(name);return it.hasNext()?it.next():parent.createFolder(name);}
function findRowBy_(sh,col,value){const n=Math.max(sh.getLastRow()-1,0);if(!n)return null;const vals=sh.getRange(2,col,n,1).getValues();for(let i=0;i<vals.length;i++)if(String(vals[i][0])===String(value))return {row:i+2};return null;}
function rowToObject_(sh,row){const h=sh.getRange(1,1,1,sh.getLastColumn()).getValues()[0];const v=sh.getRange(row,1,1,sh.getLastColumn()).getValues()[0];return objectFromRow_(h,v);}
function objectFromRow_(h,row){const o={};h.forEach((x,i)=>o[x]=row[i] instanceof Date?row[i].toISOString():row[i]);return o;}
function nextId_(prefix,sh){return prefix+"-"+String(Math.max(sh.getLastRow()-1,0)+1).padStart(5,"0");}
function parseBody_(e){if(!e||!e.postData)return {};try{return JSON.parse(e.postData.contents||"{}")}catch(err){return {};}}
function json_(obj){return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);}
function require_(v,m){if(v===undefined||v===null||v==="")throw new Error(m);}
function isSunday_(d){return new Date(d+"T12:00:00").getDay()===0;}
function formatDate_(d){return Utilities.formatDate(d,CONFIG.TIMEZONE,"dd MMM yyyy");}
function formatMedicines_(items){return (items||[]).map((m,i)=>(i+1)+". "+(m.name||"")+" | "+(m.dose||"")+" | "+(m.frequency||"")).join("\\n");}
function escapeReplacement_(v){return String(v||"").replace(/\\\\/g,"\\\\\\\\").replace(/\\$/g,"\\\\$");}
