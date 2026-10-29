param([Parameter(Mandatory=$true)][string]$EvidenceDirectory,[int]$Seconds=180)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Windows.Forms;
using System.IO;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
public sealed class UsbDisplayTestPattern : Form {
 [DllImport("winmm.dll")] static extern uint timeBeginPeriod(uint p);
 [DllImport("winmm.dll")] static extern uint timeEndPeriod(uint p);
 readonly string evidence; readonly Stopwatch watch=Stopwatch.StartNew(); readonly System.Windows.Forms.Timer timer=new System.Windows.Forms.Timer();
 volatile bool running; int pending,paints; double lastSample; Thread animator;
 int clicks,moves; readonly int seconds;
 public UsbDisplayTestPattern(string folder,int duration){
  timeBeginPeriod(1);evidence=folder;seconds=duration;Text="USB Tablet Display - isolated test pattern";
  FormBorderStyle=FormBorderStyle.None;StartPosition=FormStartPosition.Manual;DoubleBuffered=true;
  Screen target=null;foreach(var s in Screen.AllScreens)if(!s.Primary)target=s;
  if(target==null)throw new Exception("No secondary display for the test pattern");
  Bounds=target.Bounds;TopMost=true;
  MouseDown+=(s,e)=>{clicks++;Save();};MouseMove+=(s,e)=>{if(e.Button!=MouseButtons.None){moves++;Save();}};
  timer.Interval=100;timer.Tick+=(s,e)=>{if(watch.Elapsed.TotalSeconds>=seconds)Close();};
  Shown+=(s,e)=>{File.WriteAllText(Path.Combine(evidence,"pattern-display.txt"),target.DeviceName+" "+target.Bounds);Save();timer.Start();running=true;
   animator=new Thread(()=>{double next=watch.Elapsed.TotalSeconds;while(running){next+=1.0/120;while(running && watch.Elapsed.TotalSeconds<next){if(next-watch.Elapsed.TotalSeconds>0.002)Thread.Sleep(1);else Thread.SpinWait(50);}if(running && Interlocked.Exchange(ref pending,1)==0){try{BeginInvoke((Action)(()=>{Interlocked.Exchange(ref pending,0);if(running){Invalidate();Update();}}));}catch{break;}}}});animator.IsBackground=true;animator.Start();};
 }
 void Save(){File.WriteAllText(Path.Combine(evidence,"pattern-input.txt"),"clicks="+clicks+" dragMoves="+moves);}
 protected override void OnPaint(PaintEventArgs e){
  var g=e.Graphics;g.Clear(Color.FromArgb(8,30,50));int x=(int)(watch.Elapsed.TotalMilliseconds/3)%Math.Max(1,Width);
  paints++;if(watch.Elapsed.TotalSeconds-lastSample>=1){File.WriteAllText(Path.Combine(evidence,"pattern-frames.txt"),"paints="+paints+" elapsed="+watch.Elapsed.TotalSeconds.ToString("F3"));lastSample=watch.Elapsed.TotalSeconds;}
  g.FillRectangle(Brushes.DeepSkyBlue,x,0,100,Height);
  using(var font=new Font("Segoe UI",30))g.DrawString("USB Tablet Display - TEST ONLY\n"+Width+" x "+Height+"\nElapsed: "+watch.Elapsed.TotalSeconds.ToString("F2")+" s\nClicks: "+clicks+"  Drag: "+moves+"\nTap or drag on this test surface",font,Brushes.White,90,90);
 }
 protected override void Dispose(bool disposing){if(disposing){running=false;timer.Dispose();timeEndPeriod(1);}base.Dispose(disposing);}
}
'@
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
[Windows.Forms.Application]::Run([UsbDisplayTestPattern]::new($EvidenceDirectory,$Seconds))
