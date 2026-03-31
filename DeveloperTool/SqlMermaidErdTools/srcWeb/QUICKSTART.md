# Quick Start Guide - CodeMonkey by Dedge

Get your product store running in 5 minutes!

**Brand**: CodeMonkey by Dedge - Professional developer tools and software solutions.

## 🚀 Run the Application

```bash
cd srcWeb
dotnet run
```

**Open in browser:** http://localhost:5000

## 📦 What You Get

### Pages Created
- ✅ **Homepage** (`/`) - Hero section, featured products, stats
- ✅ **Products Page** (`/products.html`) - All products with category filters
- ✅ **Product Detail Page** (`/product.html?id=X`) - Pricing comparison table (Free/Pro/Enterprise)
- ✅ **Checkout Page** (`/checkout.html`) - Stripe integration point
- ✅ **Success Page** (`/purchase-success.html`) - Post-purchase confirmation

### Features
- ✅ **3-Tier Pricing**: Free, Pro, Enterprise columns for every product
- ✅ **Stripe Ready**: Product/Price IDs configured in JSON
- ✅ **Auto-Reload**: Edit `products.json` and see changes instantly
- ✅ **Real Logo**: Uses your `Resources/icon.png` as the logo
- ✅ **Beautiful UI**: Modern, responsive design
- ✅ **Search**: Fast product search
- ✅ **Categories**: Filter by Developer Tools, VS Code Extensions, etc.

## 📝 Edit Products

Open `srcWeb/products.json` and edit:

```json
{
  "products": [
    {
      "id": "sqlmermaid-nuget",
      "name": "Your Product Name",
      "pricing": {
        "free": {
          "price": 0,
          "features": ["Up to 10 tables"],
          "limitations": ["10 table limit"]
        },
        "pro": {
          "price": 49,
          "stripePriceId": "price_XXXXX",  ← Add your Stripe Price ID
          "features": ["Unlimited tables", "All dialects"]
        },
        "enterprise": {
          "price": 499,
          "stripePriceId": "price_YYYYY",
          "contactEmail": "sales@yoursite.com"
        }
      }
    }
  ]
}
```

**Save the file** → The website updates automatically!

## 💳 Enable Stripe Payments

### 1. Get Stripe Keys

1. Sign up at https://stripe.com
2. Go to Developers → API Keys
3. Copy your **Publishable Key** and **Secret Key**

### 2. Create Products in Stripe

1. Go to Products → Create Product
2. Add a price (e.g., $49 one-time)
3. Copy the **Price ID** (starts with `price_`)
4. Paste into `products.json` → `stripePriceId` field

### 3. Update Configuration

Edit `products.json`:
```json
{
  "stripe": {
    "publishableKey": "pk_test_YOUR_KEY_HERE",
    "enabled": true
  }
}
```

### 4. Install Stripe SDK

```bash
dotnet add package Stripe.net
```

### 5. Uncomment Code

In `srcWeb/Services/StripeService.cs`, uncomment the Stripe SDK code (lines 34-57).

### 6. Test Checkout

Click "Buy License" → Enter email → Redirected to Stripe Checkout!

## 🎨 Customize

### Change Colors

Edit `srcWeb/wwwroot/css/styles.css`:

```css
:root {
    --primary-color: #2563eb;  /* Your brand color */
    --success-color: #10b981;  /* Free tier color */
}
```

### Replace Logo

The site already uses your logo from `Resources/icon.png` (copied to `srcWeb/wwwroot/images/logo.png`).

To use a different logo:
```bash
Copy-Item "path\to\your\logo.png" "srcWeb\wwwroot\images\logo.png" -Force
```

### Add Product

Add to `products.json`:

```json
{
  "id": "my-new-product",
  "category": "Developer Tools",
  "name": "Amazing Tool",
  "shortDescription": "Does amazing things",
  "icon": "/images/logo.png",
  "features": {
    "free": ["Feature 1", "Feature 2"],
    "pro": ["All Free", "Feature 3"],
    "enterprise": ["All Pro", "Feature 4"]
  },
  "pricing": {
    "free": { "price": 0, ... },
    "pro": { "price": 29, "stripePriceId": "price_XXX", ... },
    "enterprise": { "price": 299, ... }
  },
  "metadata": {
    "version": "1.0.0",
    "downloads": 100,
    "rating": 5.0,
    "reviewCount": 10
  },
  "isActive": true,
  "isFeatured": true
}
```

## 📊 Current Products

The store is pre-loaded with all your SqlMermaid products:

1. **SqlMermaid NuGet Package**
   - Free: Up to 10 tables ($0)
   - Pro: Unlimited ($49)
   - Enterprise: Site license ($499/year)

2. **SqlMermaid CLI Tool**
   - Free: Up to 10 tables ($0)
   - Pro: Unlimited ($29)
   - Enterprise: Unlimited servers ($299/year)

3. **VS Code Basic Extension**
   - Free: Basic features ($0)
   - Pro: Advanced features ($9)
   - Enterprise: Team license ($199/year)

4. **VS Code Advanced Extension**
   - Pro: Professional split editor ($19)
   - Enterprise: Team license + custom features ($399/year)

## 🔧 Troubleshooting

### Port Already in Use

```bash
dotnet run --urls "http://localhost:5001"
```

### Changes Not Showing

- Hard refresh: `Ctrl+F5` in browser
- Clear cache
- Check browser console for errors

### Stripe Checkout Not Working

1. Verify `stripePriceId` is set in `products.json`
2. Check Stripe keys are correct
3. Ensure you're using HTTPS in production

## 📚 Next Steps

- [ ] Read full [README.md](README.md) for Stripe integration
- [ ] Set up webhook endpoint for payment confirmation
- [ ] Implement license key generation
- [ ] Configure email delivery (SendGrid, etc.)
- [ ] Deploy to production (Azure, AWS, etc.)

## 🎉 You're Ready!

Your professional product store is now running with:
- ✅ All products with Free/Pro/Enterprise tiers
- ✅ Beautiful pricing comparison tables
- ✅ Stripe checkout integration points
- ✅ Your logo and branding
- ✅ Auto-updating product catalog

**Happy selling!** 💰

