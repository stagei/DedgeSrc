using System.Runtime.Versioning;

namespace MouseJiggler;

[SupportedOSPlatform("windows")]
static class Program
{
    [STAThread]
    static void Main()
    {
        ApplicationConfiguration.Initialize();
        var form = new MouseJiggler();
        
        Application.Run(form);
    }
}
