FROM mcr.microsoft.com/dotnet/core/sdk:3.1 AS build
WORKDIR /src

# Copy everything (simple approach - all projects need each other for references)
COPY . .

# Build the target project
ARG PROJECT_PATH
RUN dotnet publish "${PROJECT_PATH}" -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/core/aspnet:3.1 AS runtime
WORKDIR /app
COPY --from=build /app/publish .

ENV ASPNETCORE_URLS=http://+:80
ENV ASPNETCORE_ENVIRONMENT=Development

ENTRYPOINT ["dotnet"]
# CMD set in docker-compose per service (e.g., "GloboTicket.Services.EventCatalog.dll")
