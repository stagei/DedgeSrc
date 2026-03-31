# CodeMonkey by Dedge - Product Store

A professional e-commerce web application for selling software products with Stripe integration.

**Brand**: CodeMonkey by Dedge  
**Purpose**: General-purpose software product store (not limited to SqlMermaid products)

## Features

- ✅ **Dynamic Product Catalog**: JSON-based product management with automatic reload
- ✅ **Stripe Integration**: Ready for payment processing with Stripe Checkout
- ✅ **Tiered Pricing**: Support for Free/Pro/Enterprise pricing tiers
- ✅ **Responsive Design**: Beautiful, modern UI that works on all devices
- ✅ **Real-time Updates**: FileSystemWatcher monitors `products.json` for changes
- ✅ **RESTful API**: Clean .NET 10 minimal API backend
- ✅ **Product Search**: Fast client-side search functionality
- ✅ **Featured Products**: Highlight your best products on the homepage
- ✅ **Category Filtering**: Organize products by category

## Technology Stack

### Backend
- **.NET 10.0**: Modern minimal API with C# 13
- **ASP.NET Core**: High-performance web server
- **File-based Storage**: JSON configuration for easy management

### Frontend
- **HTML5**: Semantic, accessible markup
- **CSS3**: Modern styling with CSS Grid and Flexbox
- **Vanilla JavaScript**: No framework dependencies, fast loading
- **Stripe.js**: Secure payment processing (when configured)

## Project Structure

```
srcWeb/
├── Models/
│   └── Product.cs              # Product data models
├── Services/
│   ├── ProductService.cs       # Product management with FileSystemWatcher
│   └── StripeService.cs        # Stripe payment integration
├── wwwroot/
│   ├── index.html              # Homepage with hero and featured products
│   ├── products.html           # Product listing page
│   ├── product.html            # Product detail page with pricing comparison
│   ├── checkout.html           # Checkout page (Stripe integration point)
│   ├── purchase-success.html   # Post-purchase confirmation page
│   ├── css/
│   │   └── styles.css          # Complete stylesheet
│   └── js/
│       ├── app.js              # Core functionality and API calls
│       ├── products.js         # Products listing page logic
│       └── product-detail.js   # Product detail and pricing display
├── products.json               # Product catalog (auto-reloads on change)
├── Program.cs                  # API endpoints and configuration
├── ProductStore.csproj         # Project file
└── README.md                   # This file
```

## Getting Started

### 1. Run the Application

```bash
cd srcWeb
dotnet run
```

The application will be available at: `http://localhost:5000`

### 2. Edit Products

Edit `products.json` to add/modify products. The changes will be picked up automatically without restarting the server.

### 3. Configure Stripe (Optional)

To enable real payment processing:

1. **Install Stripe.NET SDK**:
   ```bash
   dotnet add package Stripe.net
   ```

2. **Add Stripe Keys** to `appsettings.json`:
   ```json
   {
     "Stripe": {
       "SecretKey": "sk_test_YOUR_SECRET_KEY",
       "PublishableKey": "pk_test_YOUR_PUBLISHABLE_KEY"
     }
   }
   ```

3. **Create Products and Prices in Stripe Dashboard**:
   - Go to https://dashboard.stripe.com/products
   - Create a product for each tier
   - Copy the Price IDs to `products.json` (`stripePriceId` field)

4. **Update `StripeService.cs`**:
   Uncomment the Stripe SDK code in `CreateCheckoutSessionAsync()` method.

5. **Set up Webhooks**:
   - Add webhook endpoint: `/api/stripe/webhook`
   - Listen for `checkout.session.completed` event
   - Generate and email license keys

## API Endpoints

### Products

- `GET /api/products` - Get all products with catalog metadata
- `GET /api/products/{id}` - Get specific product details
- `GET /api/products/category/{category}` - Get products by category
- `GET /api/products/featured` - Get featured products only
- `GET /api/products/search?q={query}` - Search products

### Checkout

- `POST /api/checkout/create-session` - Create Stripe checkout session
  ```json
  {
    "productId": "sqlmermaid-nuget",
    "tier": "pro",
    "email": "customer@example.com"
  }
  ```

### Health

- `GET /api/health` - Health check endpoint

## Product JSON Schema

```json
{
  "id": "unique-product-id",
  "category": "Developer Tools",
  "name": "Product Name",
  "shortDescription": "Brief description",
  "fullDescription": "Detailed description",
  "icon": "/images/logo.png",
  "features": {
    "free": ["Feature 1", "Feature 2"],
    "pro": ["All Free features", "Feature 3", "Feature 4"],
    "enterprise": ["All Pro features", "Feature 5"]
  },
  "pricing": {
    "free": {
      "price": 0,
      "currency": "USD",
      "label": "Free",
      "billingPeriod": "forever",
      "stripePriceId": null,
      "downloadUrl": "https://...",
      "action": "Download",
      "limitations": ["10 table limit"]
    },
    "pro": {
      "price": 49,
      "currency": "USD",
      "label": "Professional",
      "billingPeriod": "one-time",
      "stripePriceId": "price_XXXXX",
      "stripeProductId": "prod_XXXXX",
      "action": "Buy License"
    },
    "enterprise": {
      "price": 499,
      "currency": "USD",
      "label": "Enterprise",
      "billingPeriod": "annually",
      "stripePriceId": "price_XXXXX",
      "action": "Contact Sales",
      "contactEmail": "sales@example.com"
    }
  },
  "metadata": {
    "version": "1.0.0",
    "downloads": 1000,
    "rating": 4.8,
    "reviewCount": 25
  },
  "isActive": true,
  "isFeatured": true
}
```

## Pricing Tiers Explained

### Free Tier
- **Price**: $0
- **Best For**: Personal projects, evaluation, small schemas
- **Limitations**: Clearly defined in JSON (e.g., table limits, feature restrictions)
- **Action**: Direct download link

### Pro Tier
- **Price**: One-time or subscription
- **Best For**: Professional developers, commercial use
- **Features**: All features, unlimited usage, priority support
- **Action**: Stripe Checkout for instant purchase

### Enterprise Tier
- **Price**: Annual or custom pricing
- **Best For**: Large teams, custom requirements
- **Features**: Everything in Pro + team licenses, custom development, SLA
- **Action**: Contact sales (email link)

## Customization

### Change Logo
Replace `/images/logo.png` with your own logo (currently using `Resources/icon.png`)

### Modify Colors
Edit CSS variables in `styles.css`:
```css
:root {
    --primary-color: #2563eb;      /* Main brand color */
    --primary-hover: #1d4ed8;      /* Hover state */
    --success-color: #10b981;      /* Success/Free tier */
    ...
}
```

### Add New Product
Add a new object to the `products` array in `products.json`. The UI will update automatically.

### Add New Category
Add to `categories` array in `products.json`:
```json
{
  "id": "new-category",
  "name": "New Category",
  "description": "Category description",
  "icon": "/images/category-icon.png"
}
```

## Deployment

### Production Checklist

- [ ] Replace Stripe test keys with live keys
- [ ] Set up SSL/TLS certificate (HTTPS required for Stripe)
- [ ] Configure proper CORS for your domain
- [ ] Set up webhook endpoint and verify signature
- [ ] Implement license key generation and delivery
- [ ] Set up email service (SendGrid, Mailgun, etc.)
- [ ] Configure logging and monitoring
- [ ] Set up database for order history (optional)
- [ ] Add privacy policy and terms of service
- [ ] Test checkout flow end-to-end

### Deploy to Azure App Service

```bash
dotnet publish -c Release
# Deploy the publish folder to Azure App Service
```

### Deploy to Docker

```dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS base
WORKDIR /app
EXPOSE 80

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY ["ProductStore.csproj", "./"]
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o /app/publish

FROM base AS final
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "ProductStore.dll"]
```

## License Management Integration

For automated license delivery:

1. Generate unique license keys on successful payment
2. Store licenses in database with customer email
3. Send email with download links and license key
4. Implement activation endpoint in your CLI/product
5. Validate licenses against your database or licensing service (like Gumroad, LemonSqueezy)

## Support

For questions or issues:
- Email: support@codemonkey.dedge.no
- Sales: sales@codemonkey.dedge.no
- GitHub: https://github.com/yourusername/SqlMermaidErdTools

## Future Enhancements

- [ ] Shopping cart for multiple products
- [ ] Subscription management dashboard
- [ ] Download history for customers
- [ ] License key management portal
- [ ] Automated renewal reminders
- [ ] Discount codes and promotions
- [ ] Affiliate system
- [ ] Customer reviews and ratings

---

Built with ❤️ using .NET 10 and modern web technologies.

