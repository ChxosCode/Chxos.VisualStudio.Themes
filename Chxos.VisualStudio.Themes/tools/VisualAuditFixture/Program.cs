var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();
app.MapGet("/", () => Results.Ok(new { Theme = "Cosmora", Ready = true, Count = 9 }));
app.Run();
