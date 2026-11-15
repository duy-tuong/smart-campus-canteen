using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CanteenApi.Controllers;

/// <summary>
/// Endpoint kiểm tra server còn sống. Dùng để "đánh thức" server trên Render trước buổi demo.
/// </summary>
[ApiController]
[Route("api/[controller]")]
[AllowAnonymous]
public class HealthController : ControllerBase
{
    /// <summary>GET /api/health</summary>
    [HttpGet]
    public IActionResult Get() => Ok(new { status = "ok", time = DateTimeOffset.UtcNow });
}
