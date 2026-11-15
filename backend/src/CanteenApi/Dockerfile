# Build: docker build -t canteen-api .   (chạy trong backend/src/CanteenApi)
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY CanteenApi.csproj .
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .
# Image aspnet mặc định lắng nghe cổng 8080 (ASPNETCORE_HTTP_PORTS).
# Trên Render: đặt biến môi trường PORT=8080.
EXPOSE 8080
ENTRYPOINT ["dotnet", "CanteenApi.dll"]
