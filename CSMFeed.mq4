//+------------------------------------------------------------------+
//|                                                    CSMFeed.mq4    |
//|   Headless feed EA: computes currency strength / pair pressure   |
//|   from D1 high/low and ships a JSON snapshot every second         |
//|   to a local web server (WebRequest POST) and/or a file.          |
//|   Setup: Tools > Options > Expert Advisors > Allow WebRequest     |
//|          and add  http://127.0.0.1:8765                           |
//+------------------------------------------------------------------+
#property strict

input string ServerUrl      = "http://127.0.0.1:8765/ingest";
input bool   UseWebRequest  = true;               // POST snapshot to ServerUrl
input bool   WriteFile      = true;               // also write MQL4/Files/csm_snapshot.json
input string FileName       = "csm_snapshot.json";
input int    IntervalSec    = 1;
input double BuyLimit       = 3.19;
input double SellLimit      = -3.19;
input double StrongCut      = 6.5;
input double WeakCut        = 3.5;
input double FadeTol        = 4.0;
input double AtDayEdgePct   = 0.5;
input bool   IncludeGold    = true;
input string GoldSymbol     = "XAUUSD";

#define NCUR 9
string CUR[NCUR]={"AUD","CAD","CHF","EUR","GBP","JPY","NZD","USD","XAU"};
double meter[NCUR], strength[NCUR], psum[NCUR]; int pcnt[NCUR];

#define NPAIR 29
string PAIRS[NPAIR]={
 "AUDCAD","AUDCHF","AUDJPY","AUDNZD","AUDUSD","CADCHF","CADJPY","CHFJPY",
 "EURAUD","EURCAD","EURCHF","EURGBP","EURJPY","EURNZD","EURUSD","GBPAUD",
 "GBPCAD","GBPCHF","GBPJPY","GBPNZD","GBPUSD","NZDCAD","NZDCHF","NZDJPY",
 "NZDUSD","USDCAD","USDCHF","USDJPY","XAUUSD"};

double pBuyPct[NPAIR], pDelta[NPAIR], pPeakBR[NPAIR], pTroughBR[NPAIR];
double pHi[NPAIR], pLo[NPAIR], pMid[NPAIR];
int    pSig[NPAIR], pDig[NPAIR];
string pDay[NPAIR];       // "HIGH","LOW","mid"
datetime pPeakDay=0;
int failCount=0;

//------------------------------------------------------------------
int CurIdx(string c){ for(int i=0;i<NCUR;i++) if(CUR[i]==c) return i; return -1; }
string Suffix(){ string s=Symbol(); return (StringLen(s)>6)?StringSubstr(s,6):""; }
void SplitBQ(string pair,string &b,string &q){
   if(pair=="XAUUSD"){ b="XAU"; q="USD"; return; }
   b=StringSubstr(pair,0,3); q=StringSubstr(pair,3,3);
}

void Compute(){
   for(int c=0;c<NCUR;c++){ psum[c]=0; pcnt[c]=0; }
   datetime today=TimeCurrent()-(TimeCurrent()%86400);
   if(pPeakDay!=today){ for(int i=0;i<NPAIR;i++){ pPeakBR[i]=0; pTroughBR[i]=100; } pPeakDay=today; }

   for(int i=0;i<NPAIR;i++){
      string pair=PAIRS[i];
      if(pair=="XAUUSD" && !IncludeGold){ pBuyPct[i]=-1; continue; }
      string sym=((pair=="XAUUSD")?GoldSymbol:pair)+Suffix();
      double hi=iHigh(sym,PERIOD_D1,0), lo=iLow(sym,PERIOD_D1,0);
      double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK);
      if(bid<=0){ pBuyPct[i]=-1; continue; }
      double mid=(bid+ask)/2.0, rng=hi-lo, press=0, br=0.5;
      if(rng>0){ br=(mid-lo)/rng; press=(br-0.5)*2.0; }
      pBuyPct[i]=br*100.0;
      pHi[i]=hi; pLo[i]=lo; pMid[i]=mid; pDig[i]=(int)MarketInfo(sym,MODE_DIGITS);

      double edge=rng*AtDayEdgePct/100.0;
      if(mid>=hi-edge)      pDay[i]="HIGH";
      else if(mid<=lo+edge) pDay[i]="LOW";
      else                  pDay[i]="mid";

      if(pBuyPct[i]>pPeakBR[i])   pPeakBR[i]=pBuyPct[i];
      if(pBuyPct[i]<pTroughBR[i]) pTroughBR[i]=pBuyPct[i];

      string b,q; SplitBQ(pair,b,q);
      int bi=CurIdx(b), qi=CurIdx(q);
      if(bi>=0){ psum[bi]+=press; pcnt[bi]++; }
      if(qi>=0){ psum[qi]-=press; pcnt[qi]++; }
   }
   for(int c=0;c<NCUR;c++){
      meter[c]=(pcnt[c]>0)?psum[c]/pcnt[c]:0; strength[c]=(meter[c]+1.0)*5.0;
      if(strength[c]<0) strength[c]=0;
      if(strength[c]>10) strength[c]=10;
   }
   for(int i=0;i<NPAIR;i++){
      if(pBuyPct[i]<0){ pDelta[i]=0; pSig[i]=0; continue; }
      string b,q; SplitBQ(PAIRS[i],b,q); int bi=CurIdx(b), qi=CurIdx(q);
      double d=((bi>=0)?strength[bi]:5)-((qi>=0)?strength[qi]:5);
      pDelta[i]=d;
      pSig[i]=(d>=BuyLimit)?1:((d<=SellLimit)?-1:0);
   }
}

string FreshFade(int i){
   if(pSig[i]==1)  return (pBuyPct[i] >= pPeakBR[i]-FadeTol) ? "FRESH" : "FADING";
   if(pSig[i]==-1) return (pBuyPct[i] <= pTroughBR[i]+FadeTol) ? "FRESH" : "FADING";
   return "-";
}

//------------------------------------------------------------------
string Num(double v,int dg){ return DoubleToString(v,dg); }

string BuildJson(){
   string j="{\"time\":\""+TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)+"\""
           +",\"server\":\""+AccountServer()+"\""
           +",\"cfg\":{\"buyLimit\":"+Num(BuyLimit,2)+",\"sellLimit\":"+Num(SellLimit,2)
           +",\"strongCut\":"+Num(StrongCut,2)+",\"weakCut\":"+Num(WeakCut,2)+"}";
   j+=",\"currencies\":[";
   bool first=true;
   for(int c=0;c<NCUR;c++){
      if(CUR[c]=="XAU" && !IncludeGold) continue;
      if(!first) j+=","; first=false;
      j+="{\"code\":\""+CUR[c]+"\",\"strength\":"+Num(strength[c],3)+",\"meter\":"+Num(meter[c],4)+"}";
   }
   j+="],\"pairs\":[";
   first=true;
   for(int i=0;i<NPAIR;i++){
      if(pBuyPct[i]<0) continue;
      if(!first) j+=","; first=false;
      string sig=(pSig[i]==1)?"BUY":((pSig[i]==-1)?"SELL":"WAIT");
      j+="{\"pair\":\""+PAIRS[i]+"\",\"buy\":"+Num(pBuyPct[i],2)+",\"sell\":"+Num(100-pBuyPct[i],2)
        +",\"delta\":"+Num(pDelta[i],3)+",\"signal\":\""+sig+"\",\"state\":\""+FreshFade(i)+"\""
        +",\"day\":\""+pDay[i]+"\",\"high\":"+Num(pHi[i],pDig[i])+",\"low\":"+Num(pLo[i],pDig[i])
        +",\"mid\":"+Num(pMid[i],pDig[i])+"}";
   }
   j+="]}";
   return j;
}

void Push(){
   string json=BuildJson();

   if(WriteFile){
      int h=FileOpen(FileName,FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(h!=INVALID_HANDLE){ FileWriteString(h,json); FileClose(h); }
   }
   if(UseWebRequest){
      char post[], res[]; string rh;
      int n=StringToCharArray(json,post,0,WHOLE_ARRAY,CP_UTF8);
      if(n>0) ArrayResize(post,n-1);   // drop trailing NUL
      int code=WebRequest("POST",ServerUrl,"Content-Type: application/json\r\n",1000,post,res,rh);
      if(code==-1){
         if(failCount++%30==0)
            Print("CSMFeed: WebRequest failed, err=",GetLastError(),
                  " (add ",ServerUrl," to Tools>Options>Expert Advisors allowed URLs; is server.py running?)");
      } else failCount=0;
   }
}

//------------------------------------------------------------------
int OnInit(){
   EventSetTimer(MathMax(1,IntervalSec));
   Comment("CSMFeed running -> ",UseWebRequest?ServerUrl:"(file only)");
   Compute(); Push();
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason){ EventKillTimer(); Comment(""); }
void OnTimer(){ Compute(); Push(); }
void OnTick(){}
//+------------------------------------------------------------------+
