# ミニマップのアイコンを色で切り出し、連結成分の重心・外接矩形を出す（map_proto 用）。
param([string]$Image, [string]$Out)
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System; using System.Drawing; using System.Drawing.Imaging; using System.Collections.Generic; using System.Text;
public static class Icons {
  static string Cls(int r,int g,int b){
    float h,s,v; Color c=Color.FromArgb(r,g,b); h=c.GetHue(); s=c.GetSaturation(); v=c.GetBrightness();
    int mx=Math.Max(r,Math.Max(g,b)); float V=mx/255f; int mn=Math.Min(r,Math.Min(g,b)); float S=mx==0?0:(mx-mn)/(float)mx;
    if(V<0.62f||S<0.45f) return null;
    if(h>=340||h<=12) return "red";
    if(h>=285&&h<=325) return "pink";
    if(h>=85&&h<=140) return "green";
    if(h>=175&&h<=195&&S>0.6f) return "cyan";
    if(h>=196&&h<=230) return "blue";
    return null;
  }
  public static string Run(string path,int x0,int y0,int x1,int y1){
    var bmp=new Bitmap(path); int w=x1-x0, h=y1-y0;
    var data=bmp.LockBits(new Rectangle(0,0,bmp.Width,bmp.Height),ImageLockMode.ReadOnly,PixelFormat.Format32bppArgb);
    byte[] px=new byte[data.Stride*bmp.Height]; System.Runtime.InteropServices.Marshal.Copy(data.Scan0,px,0,px.Length); bmp.UnlockBits(data);
    string[] cls=new string[w*h];
    for(int y=0;y<h;y++)for(int x=0;x<w;x++){int i=(y+y0)*data.Stride+(x+x0)*4; cls[y*w+x]=Cls(px[i+2],px[i+1],px[i]);}
    bool[] seen=new bool[w*h]; var sb=new StringBuilder();
    for(int s=0;s<w*h;s++){ if(cls[s]==null||seen[s])continue; string c=cls[s]; var st=new Stack<int>(); st.Push(s); seen[s]=true; long n=0,sx=0,sy=0; int mnx=w,mny=h,mxx=0,mxy=0;
      while(st.Count>0){int u=st.Pop(); int ux=u%w,uy=u/w; n++; sx+=ux; sy+=uy; if(ux<mnx)mnx=ux; if(ux>mxx)mxx=ux; if(uy<mny)mny=uy; if(uy>mxy)mxy=uy;
        for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++){int nx=ux+dx,ny=uy+dy; if(nx<0||ny<0||nx>=w||ny>=h)continue; int v=ny*w+nx; if(seen[v]||cls[v]!=c)continue; seen[v]=true; st.Push(v);}}
      if(n>=60) sb.AppendLine(c+","+n+","+(sx/(double)n+x0).ToString("F2")+","+(sy/(double)n+y0).ToString("F2")+","+(mnx+x0)+","+(mny+y0)+","+(mxx+x0)+","+(mxy+y0)); }
    return sb.ToString();
  }
}
"@
[System.IO.File]::WriteAllText($Out, [Icons]::Run($Image, 95, 0, 985, 880))
