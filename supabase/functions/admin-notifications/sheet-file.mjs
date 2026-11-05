import F from './fichas-core.mjs';
export function holiday(date){
 const y=Number(date.slice(0,4)),mmdd=date.slice(5);
 const fixed={'01-01':'Confraternização Universal','04-21':'Tiradentes','05-01':'Dia Mundial do Trabalho','07-02':'Independência da Bahia','09-07':'Independência do Brasil','10-12':'Nossa Senhora Aparecida','11-02':'Finados','11-15':'Proclamação da República','12-25':'Natal'};
 let name=fixed[mmdd];if(y>=2024&&mmdd==='11-20')name='Dia Nacional de Zumbi e da Consciência Negra';
 const a=y%19,b=Math.floor(y/100),c=y%100,d=Math.floor(b/4),e=b%4,f=Math.floor((b+8)/25),g=Math.floor((b-f+1)/3),h=(19*a+b-d-g+15)%30,i=Math.floor(c/4),k=c%4,l=(32+2*e+2*i-h-k)%7,m=Math.floor((a+11*h+22*l)/451),month=Math.floor((h+l-7*m+114)/31),day=(h+l-7*m+114)%31+1;
 const friday=new Date(Date.UTC(y,month-1,day-2)).toISOString().slice(0,10);
 if(date===friday)name='Paixão de Cristo';
 return name?{date,name,scope:mmdd==='07-02'?'bahia':'brasil'}:null;
}
export function sheetFile(sheet){
 const bytes=F.pdf({month:sheet.month,sheets:[{employee:sheet.employee,company:sheet.company,city:sheet.city}],holiday});
 const data=btoa(Array.from(bytes,b=>String.fromCharCode(b)).join(''));
 return {mimetype:'application/pdf',filename:'Ficha_Ponto_'+sheet.month+'.pdf',data};
}
