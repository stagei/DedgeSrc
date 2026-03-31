using Microsoft.AspNetCore.Mvc.RazorPages;

namespace AutoDocNew.Web.Pages;

public class SearchModel : PageModel
{
    public string Query { get; set; } = "";

    public void OnGet()
    {
        Query = Request.Query["q"].FirstOrDefault() ?? "";
    }
}
