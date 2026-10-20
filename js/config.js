// Paste your deployed Google Apps Script /exec URL here.
const API_BASE_URL = "https://script.google.com/macros/s/AKfycbwiM_ypsdremrkAN2Rkm-7KDTBEFp2lNDpzCpLvxZq9fEgxrVkJEBeP4qOIFLcnvZ__Lw/exec";

async function apiGet(action, params={}) {
  if (!API_BASE_URL) return {ok:false,configured:false};
  const url=new URL(API_BASE_URL); url.searchParams.set("action",action);
  Object.entries(params).forEach(([k,v])=>{if(v!==undefined&&v!==null&&v!=="")url.searchParams.set(k,v)});
  return (await fetch(url.toString())).json();
}

async function apiPost(action,data={}) {
  if (!API_BASE_URL) return {ok:false,configured:false};
  const res=await fetch(API_BASE_URL,{method:"POST",headers:{"Content-Type":"text/plain;charset=utf-8"},body:JSON.stringify({action,...data})});
  return res.json();
}
