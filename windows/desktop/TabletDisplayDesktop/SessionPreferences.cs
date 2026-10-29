using System;
using System.Globalization;
using System.IO;
using System.Text;

namespace TabletDisplayDesktop
{
    public sealed class SessionPreferences
    {
        public int Width = 1920;
        public int Height = 1200;
        public int RefreshRate = 60;
        public int FrameRate = 60;
        public int BitrateMbps = 8;
        public bool TouchEnabled = true;
        public int Preset = 0;
        public long Revision;

        public void Validate()
        {
            bool mode = (Width == 1280 && Height == 720) || (Width == 1920 && Height == 1080) ||
                (Width == 1920 && Height == 1200) || (Width == 2560 && Height == 1600);
            if (!mode || (RefreshRate != 60 && RefreshRate != 120) ||
                (FrameRate != 30 && FrameRate != 60 && FrameRate != 120) || FrameRate > RefreshRate ||
                BitrateMbps < 2 || BitrateMbps > 50)
                throw new InvalidOperationException("设置无效：请选择支持的分辨率、60/120 Hz、30/60/120fps 和 2–50 Mbps，帧率不能超过刷新率。");
        }

        public void Save(string path)
        {
            Validate();
            Revision = Math.Max(DateTime.UtcNow.Ticks, Revision + 1);
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            string value = "[Display]\r\nWidth=" + Width + "\r\nHeight=" + Height + "\r\nRefreshRate=" + RefreshRate +
                "\r\n[Stream]\r\nFrameRate=" + FrameRate + "\r\nBitRate=" + (BitrateMbps * 1000000) +
                "\r\nTouchEnabled=" + (TouchEnabled ? 1 : 0) + "\r\nPreset=" + Preset + "\r\nRevision=" + Revision + "\r\n";
            string temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                File.WriteAllText(temporary, value, new UTF8Encoding(false));
                if (File.Exists(path)) File.Replace(temporary, path, null);
                else File.Move(temporary, path);
            }
            finally { if (File.Exists(temporary)) File.Delete(temporary); }
        }

        public static SessionPreferences Load(string path)
        {
            SessionPreferences settings = new SessionPreferences();
            if (!File.Exists(path)) return settings;
            try
            {
                foreach (string line in File.ReadAllLines(path, Encoding.UTF8))
                {
                    int split = line.IndexOf('=');
                    long value;
                    if (split < 0 || !long.TryParse(line.Substring(split + 1), NumberStyles.Integer, CultureInfo.InvariantCulture, out value)) continue;
                    string key = line.Substring(0, split);
                    if (key == "Revision") { settings.Revision = value; continue; }
                    int number = checked((int)value);
                    switch (key)
                    {
                        case "Width": settings.Width = number; break;
                        case "Height": settings.Height = number; break;
                        case "RefreshRate": settings.RefreshRate = number; break;
                        case "FrameRate": settings.FrameRate = number; break;
                        case "BitRate": settings.BitrateMbps = number / 1000000; break;
                        case "TouchEnabled": settings.TouchEnabled = number != 0; break;
                        case "Preset": settings.Preset = number; break;
                    }
                }
                settings.Validate();
                return settings;
            }
            catch { return new SessionPreferences(); }
        }
    }
}
