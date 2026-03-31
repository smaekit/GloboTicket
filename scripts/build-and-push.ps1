param(
    [Parameter(Mandatory = $true)]
    [string]$AcrName
)

$ErrorActionPreference = "Stop"

$services = @(
    @{ Name = "eventcatalog"; Project = "GloboTicket.Services.EventCatalog/GloboTicket.Services.EventCatalog.csproj" },
    @{ Name = "shoppingbasket"; Project = "GloboTicket.Services.ShoppingBasket/GloboTicket.Services.ShoppingBasket.csproj" },
    @{ Name = "paymentgateway"; Project = "External.PaymentGateway/External.PaymentGateway.csproj" },
    @{ Name = "ordering"; Project = "GloboTicket.Services.Order/GloboTicket.Services.Ordering.csproj" },
    @{ Name = "payment"; Project = "GloboTicket.Services.Payment/GloboTicket.Services.Payment.csproj" },
    @{ Name = "discount"; Project = "GloboTicket.Services.Discount/GloboTicket.Services.Discount.csproj" },
    @{ Name = "marketing"; Project = "GloboTicket.Services.Marketing/GloboTicket.Services.Marketing.csproj" },
    @{ Name = "gateway-webbff"; Project = "GloboTicket.Gateway.WebBff/GloboTicket.Gateway.WebBff.csproj" },
    @{ Name = "gateway-mobilebff"; Project = "GloboTicket.Gateway.MobileBff/GloboTicket.Gateway.MobileBff.csproj" },
    @{ Name = "web-bff"; Project = "GloboTicket.Web.Bff/GloboTicket.Web.Bff.csproj" },
    @{ Name = "webclient"; Project = "GloboTicket.Client/GloboTicket.Web.csproj" }
)

$loginServer = az acr show --name $AcrName --query loginServer -o tsv
az acr login --name $AcrName | Out-Null

foreach ($service in $services) {
    $image = "$loginServer/$($service.Name):latest"
    Write-Host "Building $image"
    docker build --build-arg PROJECT_PATH=$($service.Project) -t $image .
    docker push $image
}